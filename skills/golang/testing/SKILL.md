---
name: golang-testing
description: Use when writing, reviewing, or fixing tests in a Go project — deciding what deserves a test, structuring table-driven scenarios, faking dependencies, testing concurrency or time, and reading coverage. Standard library testing, table-driven by default.
---

# Testing in Go

Standard library `testing`. Table-driven scenarios by default. Tests exist to
catch the failures that would cost data, money, or a night of sleep — not to
move a coverage number.

## What deserves a test

Test **every branch that changes an outcome**, and everything whose silent
failure is expensive:

- Business rules and decisions: eligibility, pricing, state transitions, retries, limits.
- Selection logic: anything deciding *which* records get written, deleted, notified, or skipped. For a destructive path, the test that matters is the one proving it never selects live data.
- Boundaries: empty, one, many, nil, zero, max, duplicate, out-of-order, unicode.
- Error paths that change behaviour — a fallback, a partial success, a degraded mode. An error path that only returns the error needs no test of its own.
- Defaults whose wrong value is dangerous: a flag defaulting to destructive, a feature defaulting to on, a rollout defaulting to everyone.
- Every bug fixed: the regression test comes first and fails before the fix.

Don't test: getters, `String()` on a plain struct, generated code, a wrapper that
only forwards arguments, or the framework itself. A test asserting that Cobra
parses flags tests Cobra.

**Where coverage should be high:** domain logic and use cases. **Where it is
legitimately low:** wiring, adapters whose behaviour is really the database's,
`main`. Chasing a percentage produces tests that assert what the code does
instead of what it must do.

## Table-driven by default

One test function per behaviour, one row per scenario:

```go
func TestPriceForOrder(t *testing.T) {
	for _, tt := range []struct {
		name string
		in   Order
		want int64
	}{
		{
			name: "a single item is charged at list price",
			in:   Order{Items: []Item{{Cents: 1000}}},
			want: 1000,
		},
		{
			name: "the third identical item is free",
			in:   Order{Items: []Item{{Cents: 1000}, {Cents: 1000}, {Cents: 1000}}},
			want: 2000,
		},
		{
			name: "an empty order costs nothing rather than erroring",
			in:   Order{},
			want: 0,
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got := PriceForOrder(tt.in); got != tt.want {
				t.Errorf("got %d, want %d", got, tt.want)
			}
		})
	}
}
```

Rules that make the table worth having:

- **`name` is a sentence describing the behaviour**, not `"case 1"` or `"success"`. The name is what a failing CI run shows; it should explain the rule without opening the file.
- **One row per scenario, not per input.** Two rows differing only in an irrelevant field are one row.
- **Always `t.Run`.** Subtests give per-case names, let one case fail without hiding the rest, and allow `-run 'TestX/the_third'`.
- **Only fields the cases actually vary.** A table with a mostly-unused column is two tests wearing one coat — split it.
- **A `want`-shaped field per assertion dimension** (`want`, `wantErr`, `avoid`) rather than an `assert func(t)` field. A closure per row is a second test body and defeats the point.
- **Loop over the literal directly** when the table is used once; assign it to a variable only if it is shared.

Not everything is a table. A single guarantee — "this destructive flag defaults
to false" — is one direct test, three lines, no table:

```go
flag := cleanUpCmd.PersistentFlags().Lookup("apply")
if flag == nil {
	t.Fatal("the --apply flag is missing")
}
if flag.DefValue != "false" {
	t.Fatalf("--apply defaults to %q, it must default to false", flag.DefValue)
}
```

## Assertions

Standard library first: `t.Errorf` to record and continue, `t.Fatalf` when the
rest of the case is meaningless. Always report both sides —
`got %q, want %q` — plus the input if it isn't obvious.

`stretchr/testify` is fine where it earns its keep (deep equality on config
structs, long assertion lists): `require` for what invalidates the rest,
`assert` for values. One style per package; mixing `assert.Equal` and `t.Errorf`
in one file makes failures read inconsistently.

Compare errors with `errors.Is` against sentinel errors, never by string.
Message text is not API.

## Fakes over generated mocks

Hand-written, in the same package as the port (see the hexagonal skill):

- **Embedded fake** for a narrow port — embed the interface, implement only the methods under test. An unplanned call panics naming the method, which is the fastest diagnosis available.
- **Scenario mock** for a full port — in-memory state, per-key success/failure behaviour, exported sentinel errors (`ErrMockFailure`), mutex-guarded.

```go
type fakeStore struct {
	order.Repository   // everything else deliberately unimplemented
	orders []*models.Order
	err    error
}
```

Skip mockery/gomock: the generated file is larger than the honest one, must be
regenerated on every signature change, and its expectation style asserts *how*
the code called a dependency rather than *what* it achieved.

## Determinism

- **No `time.Sleep`.** Waiting for a goroutine means a channel, `sync.WaitGroup`, or `context`. A sleep is either flaky or slow, usually both.
- **Inject time.** A `now func() time.Time` field, or a clock port. `time.Now()` inside logic makes a test that fails at midnight or on a leap day.
- **No network, no shared database, no ordering dependence between tests.** Each test builds its own state.
- **`t.TempDir()`** for files — it cleans itself up. `t.Cleanup` for anything else that must be released.
- **`t.Helper()`** in every helper, so failures point at the caller's line.
- Map iteration is random: sort before comparing, or compare as sets.

## Parallel and race

Add `t.Parallel()` to tests with no shared mutable state — top level and inside
each subtest. It shortens the suite and, more usefully, surfaces accidental
shared state. (Go 1.22+ gives each iteration its own loop variable, so no
`tt := tt` shadow is needed.)

Run `go test -race ./...` in CI. Anything with a goroutine, a cache, or a
package-level variable is worth the race detector, and it costs one flag.

## Integration tests — narrow on purpose

Add integration tests **only where the pieces meeting each other is the risk**:

- **HTTP handlers / API endpoints** — real router, real middleware chain, real request and response bodies. This is where routing, auth, decoding, validation, and status codes only work if they agree, and unit tests of each part in isolation all pass while the endpoint is broken.
- **User-facing flows** — the paths a user actually walks: sign-up, checkout, a message arriving and being answered. One test per flow, covering the happy path plus the failure the user would notice.
- **Queries whose correctness cannot be judged by reading them** — a join, an upsert, a conditional update. Against a real database with the production migrations applied, because the bugs there are wrong column order, an unexpected NULL, a constraint firing.

**Do not** integration-test every package. A use case with a mocked port, a
pure function, a config loader, a mapper — those are unit tests, and turning
them into integration tests buys nothing while multiplying setup, runtime, and
flakiness. Two hundred fast unit tests plus a dozen integration tests that walk
the real flows beats a slow suite that tests everything twice.

The rule: **an integration test earns its place when it can fail while every
unit test passes.** If it cannot, delete it.

Keep them separately runnable — a build tag (`//go:build integration`) or a
`testing.Short()` skip — so `go test ./...` stays fast in the edit loop while CI
runs both. Each one builds and tears down its own data (`t.Cleanup`), so the
suite has no order dependence and can be re-run against a dirty environment.

## Extras worth their cost

- **Fuzz** (`func FuzzX(f *testing.F)`) for parsers, validators, and anything decoding untrusted input. Cheap, and it finds the input nobody imagined.
- **Benchmarks** (`testing.B`, `b.ReportAllocs()`) only for paths measured to be hot. A benchmark on cold code is noise to maintain.
- **Golden files** for large output, with an `-update` flag to regenerate. Review the diff; a golden file nobody reads is a rubber stamp.

## Running

```sh
go test ./...                                   # the edit loop
go test -race ./...                             # CI
go test -coverprofile=cover.out ./... && go tool cover -func=cover.out
go tool cover -html=cover.out                   # find the untested branch
```

Read coverage to *locate* untested branches, then decide whether each one
matters. `gotestsum` gives readable output and JUnit XML for CI.

## Comment the why

When a test guards against data loss or a silent no-op, say so above it:

```go
// The destructive path must be opt-in: a default of true would make a bare run
// during an investigation delete live records.
```

That sentence outlives the assertion. Without it, the next person deletes the
test as redundant.
