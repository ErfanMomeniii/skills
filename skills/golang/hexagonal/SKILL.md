---
name: golang-hexagonal
description: Use when adding a dependency, repository, external service client, HTTP handler, consumer, or use case to a Go service — decides what becomes a port interface, where it is declared, which package implements it, and how it gets mocked. Hexagonal / ports and adapters.
---

# Hexagonal architecture in Go

The core — domain types and use cases — knows nothing about Redis, Postgres,
HTTP, Kafka, or any vendor. Every crossing to the outside world is an
**interface (port)**, and each concrete dependency is an **adapter** that
implements exactly one port.

The payoff is not purity. It is that a use case can be tested with no
infrastructure, and replacing a datastore or a vendor touches one file.

## Two kinds of port

**Inbound (driving)** — something outside calls the core: HTTP handler, queue
consumer, CLI command, cron job. The port is the use case interface; the adapter
is the handler or consumer.

**Outbound (driven)** — the core calls something outside: repository, external
API client, publisher, cache, mailer. The port is declared for the core's
benefit; the adapter wraps the vendor SDK.

Imports only ever point inward: adapters import the core, never the reverse.
Core code importing an adapter package has broken the pattern, and nothing in
the compiler will tell you.

## Layout

Substitute your own domains for `<domain>` — one per aggregate the service owns
(`order`, `invoice`, `subscription`), not one per database table.

```
internal/
  models/                    domain types — imports no infrastructure, ever
  usecase/<domain>/
    usecase.go               UseCase interface — the inbound port
    <domain>.go              implementation
    mock.go                  mock for other packages' tests
    <domain>_test.go
  repository/<domain>/
    repository.go            Repository interface — the outbound port
    postgres_repository.go   adapter, named after the technology
    mock.go
  delivery/http/             inbound adapter: handlers, middlewares
  queue/consumers/           inbound adapter: one file per consumer
  logger/, tracing/          infrastructure behind an interface
pkg/<service>/
  <service>.go               Contract interface + client implementation
  mock.go
```

**One file per port, one file per adapter, adapter file named after its
technology.** `postgres_repository.go` beside `repository.go` means a second
adapter arrives as `redis_repository.go` with nothing renamed and nothing else
touched. A `repository.go` holding both the interface and the SQL forces a
rewrite the day a second store appears.

## Declaring a port

Name it by role, never by implementation. `Repository`, not `PostgresStore`;
`Notifier`, not `TwilioClient`. Conventional names:

- `Repository` — persistence for one domain aggregate
- `UseCase` — business operations for one domain
- `Contract` — an external service client, in its own `pkg/<service>` package
- A narrow role name for a single job — `Publisher`, `Notifier`, `SessionStore`, `TokenIssuer`, `RateLimiter`

**Declare the port where it is consumed, sized to that consumption.** A package
that only needs to read and clear a session declares exactly that:

```go
// SessionStore reads and clears a subject's session.
type SessionStore interface {
	Session(ctx context.Context, subject string) (bool, error)
	ClearSession(ctx context.Context, subject string) error
}
```

Two methods, satisfied implicitly by the store adapter — no adapter change, no
import from consumer into store package. Handing that package a full 12-method
repository interface instead forces its tests to fake twelve methods to exercise
two, and lets a later change quietly reach for anything.

A wide `Repository` port is right when the consumer genuinely owns the
aggregate's CRUD. Both sizes coexist in one codebase; size per consumer, not per
codebase.

Port hygiene:

- `ctx context.Context` first, `error` last, on every method.
- Only domain types in signatures. A `*sql.DB`, `*redis.Client`, `*http.Request`, `echo.Context`, or vendor message type in a port means the abstraction leaked and the port buys nothing.
- Document each method on the interface. The port is the contract; the adapter is one way of keeping it.
- **Accept interfaces, return structs.** Constructors take ports and return the concrete adapter.
- No port method exposes a transaction handle. If a use case must span writes atomically, the port takes a function to run inside the unit of work; the adapter owns what a transaction is.

## Adapters

**Each dependency implements exactly one port and nothing else.** An adapter
package must not also export helpers the core reaches around the port to call —
that is a second, undocumented port, and it is how the pattern dies.

Translate at the boundary: vendor errors become domain errors (`ErrNotFound`),
vendor rows become domain types. A `pgx.ErrNoRows` or an HTTP 404 escaping into
a use case makes the core depend on the vendor by another name.

Bound the outbound call inside the adapter when the caller's context may have no
deadline:

```go
// callTimeout bounds this call independently of the client's own timeout.
// It runs in the request hot path and workers are handed a context with no
// deadline, so a slow — not failing — dependency would hold a worker for the
// client's full timeout per item, and the breaker never trips because nothing
// errors.
const callTimeout = 3 * time.Second
```

The comment is the point: name the failure the timeout prevents, or the next
reader deletes it as noise.

**An optional dependency is a nil port.** When a feature is off, its adapter is
never constructed and the field stays nil; the core checks nil once, at the edge
of that feature, instead of every use case learning about the flag.

## Consumers hold ports, never concretes

```go
type Handler struct {
	orderUseCase   order.UseCase       // port
	invoiceUseCase invoice.UseCase     // port
	cache          cache.Repository    // port
	logger         logger.Logger       // port
}
```

Every dependency an interface, injected through the constructor. No
package-level singletons, no client construction inside a handler or use case.
If a type is hard to build in a test, it is holding a concrete dependency.

Construction happens once, at the entry point — the `cmd` wiring or an app
bootstrap — never inside the core.

## Mocks

Hand-write `mock.go` in the same package as the port. Skip mockery and gomock:
the generated file is bigger than the honest one, needs regenerating on every
signature change, and its call-expectation style tests the mock rather than the
behaviour.

Two shapes, both useful:

- **Scenario mock** — an in-memory implementation of a full port, with per-key behaviour (success / failure) and exported sentinel errors (`ErrMockFailure`) so tests assert on error identity, not on strings. Guard state with a mutex; parallel tests will find it otherwise.
- **Embedded fake** — for a narrow port, embed the interface and implement only the methods under test. Any unplanned call panics naming the method, which is the fastest diagnosis available.

```go
type fakeStore struct {
	order.Repository   // everything else deliberately unimplemented
	orders []*models.Order
}
```

## Tests follow the ports

- **Use cases** — real logic, mocked outbound ports. No database, no network, no sleeping.
- **Adapters** — tested against the real technology or its test double; this is where query, wire-format, and error-translation bugs live.
- **Inbound adapters** — thin, so test routing, decoding, and validation, not the business rules underneath.

If a use-case test needs a running dependency, a port is missing or too wide.

## When not to bother

A single-binary tool, a PoC, or a service with one dependency and no domain
logic does not need a hexagon. Ports pay for themselves when a dependency has a
plausible second implementation, or when a use case has branches worth testing
without infrastructure. Below that, one package and a struct is the honest
answer — and the pattern can be introduced later, one port at a time, since
extracting an interface from working code is a mechanical change.
