---
name: golang-godoc
description: Use when writing or reviewing comments in Go — doc comments on an exported function, method, type, constant, variable, interface, or package, or deciding whether a comment belongs inside a function body. Exported identifiers are documented by purpose; logic is not commented.
---

# Go doc comments

**Every exported identifier carries a doc comment**: package, type, function,
method, constant, variable, and any exported field whose meaning is not obvious
from its name. Exported means someone outside the package will read it without
reading its body — the comment is the only thing they get.

**The comment states the purpose, never the content.** What it is for and what a
caller must know, not what the code does step by step. A comment narrating the
body doubles the maintenance, goes stale on the first refactor, and adds nothing
a reader could not get by looking down.

## Form

- **Starts with the identifier's name**, is a complete sentence, ends with a period: `// ReserveStock holds items for an order until it is confirmed.`
- **One sentence for most things.** A second paragraph only when the contract holds a surprise.
- Directly above the declaration, no blank line between.
- `//` with a single space. No banners, no decoration.
- Present tense, third person: "returns", not "will return".

## Purpose, not content

The test for every sentence: **would this still be true after the body was
rewritten with the same behaviour?** If not, it describes content — it belongs
inside the body as an inline comment, or nowhere.

```go
// Bad — narrates the implementation.
// ReserveStock loops over the order items, calls the repository for each SKU,
// decrements the count, and rolls back on the first error.

// Good — states the purpose and the contract.
// ReserveStock holds every item in the order until the order is confirmed or
// the reservation expires. It is all-or-nothing: on failure nothing is held.
func (s *Service) ReserveStock(ctx context.Context, o *Order) error
```

The other failure, more common and easier to miss — the tautology that restates
the name:

```go
// GetUser gets the user.                    // adds nothing
// SetTimeout sets the timeout.              // adds nothing
// Timeout is the timeout.                   // adds nothing
```

If the only honest sentence restates the name, the useful content is elsewhere:
the unit, the default, the bound, the consequence.

```go
// Timeout bounds a single attempt, not the whole retry sequence. Zero means no
// deadline, which is only safe for background work.
Timeout time.Duration
```

## What a caller actually needs

Cover these when they apply — this is what earns the line:

- **Error conditions and sentinel errors** — "Returns [ErrNotFound] if no order matches."
- **Nil, zero, and empty behaviour** — is the zero value usable, is a nil argument allowed, is an empty slice an error?
- **Side effects** — writes, publishes, deletes, mutates its argument.
- **Ownership** — may the caller keep or modify a returned slice, map, or pointer?
- **Blocking and cancellation** — does it block, does it honour `ctx`, what happens when cancelled?
- **Concurrency** — "Safe for concurrent use." Silence forces the caller into the source, so state it either way on types meant to be shared.
- **Units and bounds** — milliseconds, cents, percent, inclusive or exclusive.

## Per kind of declaration

**Package.** One comment per package, in `doc.go` or the file named after the
package, starting `Package order ...`. What the package is for and how it fits —
not a table of contents of its files.

```go
// Package order holds the order lifecycle: intake, validation, stock
// reservation, and handoff to fulfilment. It depends on no transport or
// storage package.
package order
```

**Interfaces.** Document the contract every implementation must honour, not what
one implementation happens to do. Each method gets its own line, phrased as an
obligation.

```go
// Repository stores orders. Implementations must be safe for concurrent use.
type Repository interface {
	// Get returns the order, or [ErrNotFound] if it does not exist.
	Get(ctx context.Context, id int64) (*Order, error)
}
```

**Methods implementing an interface** need no repeated prose — a short line
naming the contract is enough, since the contract lives on the interface.

**Constants and enums.** Document the block once; a value individually only when
its meaning is not evident from its name.

```go
// Status values track an order through its lifecycle.
const (
	StatusPending Status = iota
	StatusReserved
	// StatusPartial means some lines were fulfilled and the rest cancelled.
	StatusPartial
)
```

**Variables.** Sentinel errors and package-level state always: say when it
occurs, not what it contains.

```go
// ErrInsufficientStock is returned when an order cannot be fully reserved.
var ErrInsufficientStock = errors.New("insufficient stock")
```

**Structs.** Document the type by its role. Document fields carrying units,
constraints, defaults, or an easily-misread meaning; skip fields whose name says
everything.

## Unexported code

Unexported identifiers need no doc comment. Write one only when the *reason* is
not obvious — and then give the why, since the what is readable two lines below.

## Inside function bodies: no comments

**Logic carries no commentary.** A comment inside a body competes with the code
for attention, pushes the reader's eye sideways, and is the first thing to go
stale — the compiler never checks it. Code that needs a comment to be followed
needs a better name or a smaller function instead:

```go
// Bad — the comment is doing work the code should do.
// check if the order is old enough to expire
if time.Since(o.CreatedAt) > 30*time.Minute && o.Status == StatusPending {

// Good — the condition names itself, nothing to explain.
if o.ReservationExpired() {
```

Extract a named function, name the intermediate value, or split the block. Every
one of those survives a refactor; a comment does not.

Two things may appear inside a body:

**`// TODO:` for work deliberately left undone.** Say what and why, and attach a
name or an issue so it can be chased:

```go
// TODO(erfan): batch these writes once the bulk endpoint ships — issue #412.
```

A TODO with no owner and no reason is a decoration; it will still be there in
three years.

**A short `why` when the reason cannot live in the code.** Not what the line
does — why it is there at all, when a reader would otherwise "fix" it:

```go
// The provider rejects a second call within 500ms with a 200 and an empty
// body, which is indistinguishable from success. Serialise instead of retrying.
mu.Lock()
```

Workarounds for another system's behaviour, a deliberate deviation from the
obvious approach, an ordering constraint, a performance trade-off measured and
chosen. These are facts about the world, not about the code, so no amount of
renaming expresses them — and without them the next reader deletes the line.

Keep them to one or two lines, above the statement they explain. If a body needs
several, the explanation belongs on the function's doc comment.

## Deprecation and links

- Mark removals in the recognised form, as its own paragraph at the end, so tools can flag callers: `// Deprecated: use ReserveStock instead.`
- Link identifiers with brackets — `[ErrNotFound]`, `[time.Duration]`, `[Repository.Get]`. They render as links and survive renames better than plain text.
- Indent code samples by one tab to render as a block.

## Examples beat prose

An `Example` function in `_test.go` renders in the documentation, is compiled,
and is checked against its `// Output:` comment — so it cannot drift the way a
prose sample can. Prefer one wherever usage is not obvious from the signature.

## Enforcement

Let a linter carry the rule instead of review: `revive`'s exported rule (every
exported identifier documented, comment starts with the name) and `godot`
(comments end in a period) in `.golangci.yml`. `go doc ./...` shows what a
consumer sees — read it once for any package others import.
