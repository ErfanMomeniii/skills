---
name: golang-logging
description: Use when adding, changing, or reviewing logging in a Go service — choosing a level, naming fields, wiring the logger, logging an error, or deciding whether to log at all. Structured logging with zap behind a logger port.
---

# Logging in Go

**Tool: zap**, structured and JSON-encoded, behind a `Logger` interface the core
owns. Logs are data for machines first: they get filtered, aggregated, and
alerted on.

```
go.uber.org/zap                         https://github.com/uber-go/zap
```

Take the newest release; check upstream rather than writing encoder config from
memory (`go get -u go.uber.org/zap`).

## The port

A dependency like any other, behind an interface (see the hexagonal skill), with
two implementations — the zap adapter and a no-op for tests.

```
internal/logger/
  logger.go        the Logger interface
  zap_logger.go    zap adapter
  noop_logger.go   NewNoop() for tests
```

```go
// Logger writes structured, levelled entries. Fields are alternating key/value
// pairs: Info("order created", "order_id", id, "total_cents", total).
type Logger interface {
	Debug(msg string, fields ...any)
	Info(msg string, fields ...any)
	Warn(msg string, fields ...any)
	Error(msg string, fields ...any)
	With(fields ...any) Logger
	Sync() error
}
```

- **Key/value pairs, not `zap.Field`.** A `zap.Field` in the port makes every package import zap — exactly what the port prevents. The adapter converts pairs, mapping an `error` value to `zap.Error` and using typed constructors (`zap.String`, `zap.Int64`, `zap.Duration`) rather than `zap.Any`, which reflects on every call.
- **No `Infof`/`Errorf`.** A formatted message is a unique string per call, so it cannot be grouped, counted, or alerted on.
- **No `Fatal`.** It calls `os.Exit`, skipping deferred cleanup, and eventually lands in a request path. Startup failures return an error to `main`, the one place allowed to exit.
- `With` returns a child logger carrying fields — the mechanism for request scope.

## Anatomy of a log call

Every entry answers three questions: **where it happened, what happened and
why, and on what data.**

```go
log.Error("failed to reserve items",
	"operation", "ReserveStock",   // where — the method this came from
	"order_id", o.ID,              // details
	"sku", item.SKU,
	"err", err,                    // error last
)
```

**`operation` — where the entry came from.** The name of the method, handler, or
job doing the work, spelled exactly as in the code so a reader can jump straight
to it. This is the "where" of a log line, and it is the field a reader reaches
for first: it turns a lone error into "which part of the system is failing".

Two reasons it is a field rather than a `[ReserveStock]` prefix on the message:

- **It stays queryable.** `operation:ReserveStock AND level:error` is an indexed filter that groups and charts; `msg:"[ReserveStock]*"` is a wildcard scan that does neither.
- **The message stays constant and comparable.** Message says *what*, `operation` says *where*, and neither has to carry the other.

It does not replace `caller` — `caller` is the exact `file.go:line`, which moves
with every edit; `operation` is the stable name of the work being done, and it
survives refactors, extraction, and inlining.

**The message — what happened, constant and lowercase.** `failed to reserve
items`, `stock reserved`, `retrying after timeout`. Say what the code was trying
to do; the error's own text is already a field. "error occurred" is useless.
Never interpolate a value: `fmt.Sprintf("order %d failed", id)` destroys
aggregation, and the id belongs in a field.

**Details — every value that answers the next question.** The ids involved, the
input that was rejected, the attempt number, the limit that was hit. Log the
*discriminating* value, not only the entity id: if a rule rejected the input,
log what failed it.

Success entries take the same shape minus the error:

```go
log.Info("stock reserved", "operation", "ReserveStock", "order_id", o.ID, "items", len(o.Items))
```

Same `operation` value on every entry of one piece of work — `Debug` included —
so a single filter reconstructs the whole sequence, successes and failures
together.

## Standard format

One JSON object per line:

```json
{"ts":"2026-04-28T08:41:03.221Z","level":"error","msg":"failed to reserve items","service":"ordersvc","env":"production","version":"1.4.2","caller":"usecase/order.go:88","operation":"ReserveStock","request_id":"01JQ8ZK3","order_id":91823,"err":"insufficient stock: sku ABC-1"}
```

| Key | Always | Meaning |
|---|---|---|
| `ts` | yes | RFC3339 with milliseconds, **UTC** |
| `level` | yes | lowercase: `debug`, `info`, `warn`, `error` |
| `msg` | yes | the constant message |
| `service`, `env`, `version` | yes | bound once at startup |
| `caller` | yes | `package/file.go:line` — the exact source position |
| `operation` | yes | the method, handler, or job the entry came from |
| `request_id` | per request | correlation id; plus `trace_id`/`span_id` when tracing exists |
| `err` | on failures | the error, from the error field |
| `stacktrace` | error and above | attached automatically, never by hand |

Everything else is domain fields (`order_id`, `duration_ms`), **`snake_case`,
consistent service-wide** — `orderID` in one file and `order_id` in another
makes a dashboard impossible. Durations carry the unit in the key.

```go
encCfg := zapcore.EncoderConfig{
	TimeKey: "ts", LevelKey: "level", MessageKey: "msg",
	CallerKey: "caller", StacktraceKey: "stacktrace",
	LineEnding:  zapcore.DefaultLineEnding,
	EncodeLevel: zapcore.LowercaseLevelEncoder,
	// ISO8601TimeEncoder uses local time — force UTC explicitly.
	EncodeTime: func(t time.Time, enc zapcore.PrimitiveArrayEncoder) {
		enc.AppendString(t.UTC().Format("2006-01-02T15:04:05.000Z"))
	},
	EncodeDuration: zapcore.MillisDurationEncoder,
	EncodeCaller:   zapcore.ShortCallerEncoder,
}

encoder := zapcore.NewJSONEncoder(encCfg)      // production
if cfg.Format == "console" {                   // development only
	encCfg.EncodeLevel = zapcore.CapitalColorLevelEncoder
	encoder = zapcore.NewConsoleEncoder(encCfg)
}

core := zapcore.NewCore(encoder, zapcore.Lock(os.Stdout), level) // level from config
l := zap.New(core,
	zap.AddCaller(),
	zap.AddCallerSkip(1),                      // report the caller, not the adapter
	zap.AddStacktrace(zapcore.ErrorLevel),
).With(
	zap.String("service", cfg.Service),
	zap.String("env", cfg.Env),
	zap.String("version", build.Version),
)
```

- **JSON to stdout.** The runtime collects it; a service writing its own files reinvents rotation, shipping, and disk-full incidents.
- **UTC explicitly** — two services in different zones are otherwise unreadable side by side during an incident.
- **`AddCallerSkip(1)`**, or every line reports `zap_logger.go` instead of the real call site.
- **Stack traces on `Error` and above only**; elsewhere they are noise and cost.
- **`service`/`env`/`version` bound once**, so no call site can forget them and every line maps to a deployment.

## Levels

| Level | Means | Example |
|---|---|---|
| `Debug` | Development detail; off in production | payload contents, branch taken |
| `Info` | A state change worth seeing in production | service started, order created |
| `Warn` | Degraded but handled; nobody is paged | retry succeeded, fallback used |
| `Error` | A human must look at it | write failed, dependency unreachable after retries |

- **`Error` means actionable.** If nobody would act, it is `Warn`. An error firing a thousand times a day trains everyone to ignore the level.
- **`Info` is for state changes, not narration.** "entering function" is `Debug`, or nothing.
- **Log an error once**, where it is handled. Lower layers wrap with `%w` and return; the boundary logs. Otherwise one failure produces four entries.
- Level comes from config: `debug` in development, `info` in production.

## Scope and wiring

- **Child logger at the entry point**, not repeated fields at every call site: `reqLog := log.With("request_id", requestID, "route", route)`. One correlation id per request or message, generated at the edge if absent and propagated downstream — without it, concurrent requests interleave into unreadable output.
- **Carry the logger explicitly** (parameter or struct field). Hiding it in a `context.Value` conceals a dependency and is untyped at every retrieval.
- **Built once at startup** from config, injected through constructors. No package-level `var log`, no `zap.L()`: a global cannot be swapped in tests.
- **`defer logger.Sync()`** in `main`; ignore its error, since syncing stderr fails spuriously on some platforms.
- **Sample hot paths** so a failure loop cannot produce gigabytes and take the aggregator down with it.

## What not to log, and why

The service obviously has this data — it is processing it. The problem is not
secrecy, it is that a log line is a **second copy with worse properties** than
the database row it came from:

- **Wider access.** The database is behind credentials, roles, and an audit trail. The log store is readable by the whole engineering team, on-call, and often a third-party SaaS, with no record of who read what.
- **Longer life.** A user row can be deleted or anonymised on request. The same value in months of log archives and their backups usually cannot be surgically removed — so logging it creates an undeletable copy, which is exactly what erasure obligations forbid.
- **More exits.** Log lines get pasted into tickets, chat, and screenshots, and shipped to vendors. Database rows rarely travel that way.

Three tiers:

**Never, unconditionally — secrets.** Passwords, tokens, API keys, session ids,
authorization headers, signing keys. These are not sensitive *data*, they are
**reusable credentials**: anyone reading the log becomes an authenticated user,
and the leak is silent. A token in a log is a live incident.

**Never raw — personal data.** Full phone numbers, emails, addresses, national
ids, payment details. Log what lets you *find* the record instead of the record
itself:

- an internal id (`customer_id`, `candidate_id`) — join to the database when actually needed, through the access control the database already has;
- a mask when a human must recognise it at a glance (`+98•••••1234`);
- a salted hash when the value itself is the correlation key, so the same user is traceable across lines without the raw identifier being present.

If the domain is keyed on a personal identifier — a phone-number-driven flow,
for instance — keep the raw value out of routine `Info` logs and put the masked
or hashed form there instead. That keeps every debugging workflow working, since
what debugging needs is *correlation*, not the digits.

**Never wholesale — request and response bodies.** They contain both categories
above, and they are where the "just this once, for debugging" exception always
begins. Log the few fields that matter, named individually.

## Logs are not metrics

A counter or histogram answers "how many, how slow, how often" cheaply and
forever; a line per event to count later is expensive and imprecise. Per-item
lines in a loop become one aggregated line with counts when the batch finishes,
and latency belongs in a metric — log only the outliers.

## Tests

Inject the no-op logger: test output should hold test results, and a logger
writing to stdout in a parallel suite interleaves into noise. Assert on logging
only when the line *is* the feature (an audit record, a security event);
otherwise it welds tests to wording nobody considers API.
