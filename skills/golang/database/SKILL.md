---
name: golang-database
description: Use when reading from or writing to a database in Go — adding a query, a repository adapter, a transaction, a migration, or tuning a connection pool. Native driver per database with hand-written SQL. No ORM.
---

# Database access in Go

**Use each database's own client and write the SQL by hand.** No gorm, no ent,
no ORM.

Why, concretely: an ORM decides the SQL for you, so the query you review is not
the query that runs. Lazy associations become N+1 round trips no test catches;
reflection-heavy mapping costs allocations on every row; a hand-tuned join has
to be smuggled in as a raw string anyway, at which point the ORM is only
overhead. Written SQL is greppable, `EXPLAIN`-able, and reviewable by whoever
knows the database best.

## Clients

```
github.com/jackc/pgx/v5             https://github.com/jackc/pgx           Postgres
github.com/go-sql-driver/mysql      https://github.com/go-sql-driver/mysql MySQL
github.com/redis/go-redis/v9        https://github.com/redis/go-redis      Redis
github.com/golang-migrate/migrate   https://github.com/golang-migrate/migrate
```

**Always take the newest release**; check upstream rather than writing from
memory, since pool APIs and scan helpers change:

```sh
go get -u github.com/jackc/pgx/v5
go list -m -u all | grep -E 'pgx|mysql|go-redis'
```

Choice per database:

- **Postgres → pgx's native interface** (`pgxpool`), not `database/sql`. The native path uses the binary protocol, caches statements, and gives real Postgres types, arrays, and `COPY`. Going through `database/sql` throws all of that away for an abstraction you don't need.
- **MySQL → `database/sql` + go-sql-driver/mysql.** That is the driver; there is no better native surface.
- **Redis → go-redis.** A cache client, not a database abstraction: keys and TTLs are designed, not generated.

`jmoiron/sqlx` is acceptable on the MySQL side purely to remove `Scan`
boilerplate (`StructScan`, `Select`). It executes the SQL you wrote; it is not
an ORM. On Postgres, pgx's `pgx.CollectRows` + `RowToStructByName` already
covers it, so don't add sqlx.

## Where the SQL lives

Per ports and adapters: the port is `repository.go`, the adapter is
`postgres_repository.go` / `mysql_repository.go`. SQL exists only inside the
adapter — never in a use case, handler, or command.

Queries are `const` strings at the top of the adapter file, named for what they
do, and formatted to be read:

```go
const selectOrderByID = `
SELECT id,
       customer_id,
       status,
       total_cents,
       created_at
  FROM orders
 WHERE id = $1`
```

- Name every column. `SELECT *` breaks scans on the next migration and ships columns nobody reads.
- Keywords uppercase, one column per line once there are more than three, joins and conditions on their own lines. A query that takes a screen to read is where the bug hides.
- Comment *why* on anything non-obvious: an index hint, a deliberate `FOR UPDATE`, an unusual `ORDER BY`.

## Parameters

**Always bind. Never format.**

```go
row := pool.QueryRow(ctx, selectOrderByID, id)   // pgx:   $1
row := db.QueryRowContext(ctx, q, id)            // mysql: ?
```

`fmt.Sprintf` into SQL is an injection hole even when the value "comes from our
own code" — that assumption survives exactly until the next caller. Dynamic
`IN` lists use `= ANY($1)` on Postgres with a slice, or generated placeholders
on MySQL, never concatenated values.

For an optional filter, prefer one query per shape, or a
`WHERE (col = $1 OR $1 IS NULL)` predicate, over string-building a WHERE clause.

## Context and timeouts

Every call takes `ctx` — `QueryContext`, `ExecContext`, `QueryRowContext`, or
pgx's `ctx`-first methods. Nothing uses the non-context variants.

Give queries a deadline. If the caller's context has none (a consumer, a cron
job), the adapter sets one, and says what it prevents:

```go
// A query with no deadline holds a pool connection until the server kills it;
// under load that starves every other caller of this pool.
ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
defer cancel()
```

## Pool configuration

Defaults are wrong for a service. Set them explicitly, from config:

```go
db.SetMaxOpenConns(n)                  // ceiling; must fit the server's max_connections
db.SetMaxIdleConns(n)                  // default is 2 — a busy service reopens constantly
db.SetConnMaxLifetime(30 * time.Minute)
db.SetConnMaxIdleTime(5 * time.Minute)
```

pgxpool: `MaxConns`, `MinConns`, `MaxConnLifetime`, `MaxConnIdleTime`,
`HealthCheckPeriod`.

- **MySQL: `ConnMaxLifetime` must be below the server's `wait_timeout`**, or the server closes connections the pool still believes are good and callers get random errors.
- Size `MaxOpenConns` against the database, not the app: every replica multiplies it. The total across replicas has to stay under the server limit.
- Export `db.Stats()` / `pool.Stat()` as metrics. Pool exhaustion looks like slow queries in a dashboard and like nothing at all in the code.

## Reading rows

```go
rows, err := pool.Query(ctx, selectOrdersByCustomer, customerID)
if err != nil {
	return nil, fmt.Errorf("query orders: %w", err)
}
defer rows.Close()

var out []*models.Order
for rows.Next() {
	var o models.Order
	if err := rows.Scan(&o.ID, &o.CustomerID, &o.Status, &o.TotalCents, &o.CreatedAt); err != nil {
		return nil, fmt.Errorf("scan order: %w", err)
	}
	out = append(out, &o)
}
return out, rows.Err()
```

- `defer rows.Close()` always; a leaked `Rows` holds a pool connection.
- **`rows.Err()` after the loop, and return it.** Otherwise `rows.Next()` returning false hides a mid-iteration failure, and the caller sees a short result set with no error — the worst possible outcome.
- Nullable columns scan into `*T`, `sql.NullString`, or pgx types. Scanning NULL into a `string` errors at runtime, on the row that happens to be null in production.
- On pgx, `pgx.CollectRows(rows, pgx.RowToStructByName[models.Order])` replaces the loop when column names match the struct.

## Transactions

`BeginTx`, defer a rollback, commit explicitly:

```go
tx, err := pool.Begin(ctx)
if err != nil {
	return fmt.Errorf("begin: %w", err)
}
defer tx.Rollback(ctx)   // no-op after a successful commit

// ... writes ...

return tx.Commit(ctx)
```

The port never exposes a transaction handle. When a use case must span writes
atomically, the port takes a function the adapter runs inside the transaction —
so "what a transaction is" stays in the adapter.

Keep transactions short and free of calls to other services: an open transaction
holds locks, and an HTTP call inside one turns a slow dependency into a database
incident.

## Performance

- **Bulk insert** — Postgres `CopyFrom` is an order of magnitude faster than looping `INSERT`. MySQL: one multi-row `INSERT` per batch, not one per row.
- **`pgx.Batch`** pipelines several statements into one round trip.
- **Round trips dominate.** One query returning a joined result beats a loop of lookups, every time. A repository method running a query per element of a slice is the N+1 an ORM would have given you for free.
- **`EXPLAIN (ANALYZE, BUFFERS)`** before claiming a query is slow, and again after adding an index. A plan is evidence; an opinion about an index is not.
- Statement caching is on by default in pgx; on MySQL, prepare once and reuse for hot statements — never inside the loop.
- Ask for what you use: no `SELECT *`, `LIMIT` on anything unbounded, keyset pagination (`WHERE id > $1 ORDER BY id LIMIT n`) instead of `OFFSET` on large tables.

## Errors

Translate driver errors into domain errors at the adapter boundary, so no use
case ever imports a driver:

```go
if errors.Is(err, pgx.ErrNoRows) {
	return nil, models.ErrOrderNotFound
}

var pgErr *pgconn.PgError
if errors.As(err, &pgErr) && pgErr.Code == "23505" {   // unique_violation
	return nil, models.ErrDuplicateOrder
}
```

MySQL: `*mysql.MySQLError`, `Number == 1062` for duplicate key. Match on codes,
never on message text.

Wrap everything else with `%w` and the operation name. "sql: no rows" with no
context is a wasted debugging session.

## Migrations

SQL files in `/migrations`, applied by golang-migrate or goose. Never an ORM
auto-migrate: schema changes are reviewed, ordered, reversible artifacts, not a
side effect of a struct edit.

- One concern per migration, with a working `down`.
- Additive first: add a nullable column, backfill, then enforce. A single migration adding a `NOT NULL` column to a live table is an outage.
- Postgres: `CREATE INDEX CONCURRENTLY` on large tables — and it cannot run inside a transaction.

## Tests

Test against the real database — docker-compose or testcontainers, schema
applied by the same migrations as production. Mocking a driver tests the mock;
the bugs here are real SQL bugs: typos, wrong column order, a NULL nobody
expected, a constraint that fires.

Be selective. Cover the queries whose correctness **cannot be judged by reading
them**: joins, upserts, conditional updates, anything with `ORDER BY`+`LIMIT`
semantics, anything relying on a constraint or a transaction boundary. A
single-column `SELECT ... WHERE id = $1` needs no test of its own.

Use cases stay infrastructure-free: they take the repository port and get the
hand-written mock (see the hexagonal skill).
