---
name: docs-readme
description: Use when writing or restructuring a project README — deciding what sections it needs, in what order, and what belongs in deeper docs instead. Written for end users: purpose first, brief architecture, then how to run it.
---

# Writing a project README

The README is for **someone who has never seen the project**. They arrive with
four questions, in this order:

1. What is this, and is it for me?
2. What can it do?
3. Roughly how does it solve the problem?
4. How do I run or use it?

Answer them in that order. Everything else is optional and comes after.

The reader is a **user, not a contributor**. They do not care how the code is
layered, which package owns what, or what the internal conventions are — that
belongs in `docs/` or `CONTRIBUTING.md`.

## Required sections

### 1. Title and one-line summary

```markdown
# ordersvc

Accepts orders from the storefront, reserves stock, and hands them to fulfilment.
```

One sentence stating what it does. No "Introduction", no "Welcome to". A reader
who stops here should still know whether to keep reading.

### 2. Use case — what problem it solves

Two short paragraphs at most:

- **The problem**, in the domain's language, not the code's. What was painful, manual, or missing before this existed.
- **What it does about that**, and **who it is for** — the storefront team, an operator, an end customer.

Name the boundaries too. What it deliberately does *not* do saves the reader
more time than another feature bullet.

### 3. Features — what it can do

The list the reader scans to decide whether it covers their case. Capabilities
in their terms, one line each, each one something they could ask for by name:

```markdown
## Features

- **Order intake** — validates and accepts orders over HTTP or bulk CSV
- **Stock reservation** — atomic, so two orders can never take the last item
- **Fulfilment handoff** — retried on failure, with a report of what is stuck
- **Partial cancellation** — cancel single lines without voiding the order
- **Audit trail** — every status change recorded with who and when
```

Rules:

- **Group by capability, not by component.** "Stock reservation", not "the repository layer".
- **A benefit or guarantee per line**, not an implementation note. "Atomic, so two orders can't take the last item" tells them something; "uses a transaction" does not.
- **Only what works today.** Planned features belong in a roadmap link, never in this list — a reader who tries one and finds it missing stops trusting the whole page.
- **Say what is out of scope** if the project is easily mistaken for something bigger.
- Long or per-feature detail goes in `docs/`, one link per feature at most.

### 4. Solution design — a little, conceptually

How the solution works, **not how the code is organised**. The reader wants the
shape of the approach and the guarantees that follow from it:

```markdown
## How it works

An order arrives, is validated, and stock is reserved in one step — so a
rejected order never leaves a partial hold. Accepted orders go onto a queue and
are handed to fulfilment asynchronously, retried with backoff until accepted,
and surfaced in the stuck-orders report if they never are.

- Orders are processed at-least-once; handoff is idempotent per order ID
- Reservations expire after 30 minutes if the order is not confirmed
- State is durable: a restart resumes in-flight orders, nothing is lost
```

Rules:

- **One screen maximum**, prose or a short flow diagram of the *domain* steps (order → reserved → handed off), not of packages and layers.
- **Lead with the guarantees a user can feel**: ordering, at-least-once vs exactly-once, durability, expiry windows, retry behaviour, consistency. These change how they use it.
- **Name the external systems and datastores it depends on** — that is an operational fact a user needs, unlike the internal layering.
- **Explain a non-obvious choice in one sentence** when the reader would otherwise be surprised (why asynchronous, why eventual consistency here).
- Internal structure — packages, ports and adapters, naming conventions — goes in `docs/` or `CONTRIBUTING.md`. Link it for the curious; don't spend the README's first screen on it.

### 5. Running and using it — the essential part

This is where most READMEs fail, and it is the section people arrive for. It
must work from a **fresh clone**, in order, with nothing assumed:

```markdown
## Getting started

### Prerequisites
- Go 1.25+
- Docker (for Postgres and Redis)

### Run it
git clone <repo> && cd ordersvc
cp config.example.yml config.yml     # then set the two required secrets
make up                              # starts dependencies
make run                             # starts the service on :8080

### Verify
curl localhost:8080/healthz          # {"status":"ok"}
```

Rules that keep it true:

- **Every command copy-pasteable, in order, tested from a clean checkout.** A README that needs an undocumented step is worse than no README: it costs the reader an hour before they ask.
- **Pin prerequisites with versions.** "Go" is not a prerequisite; "Go 1.25+" is.
- **Include a verification step** — the one command that proves it is up, with its expected output. Without it, the reader cannot tell "started" from "working".
- **Point at the example config**, listing only the values that must be set and which are secrets. Don't duplicate every key; the example file is the reference.
- **Prefer `make` targets over raw command lines**, and use the same targets CI uses. A command that exists in both places cannot silently rot.
- **Then show how to *use* it**: the main endpoints or CLI commands, with one real request and its response, or `--help` output. A reader who can start the service but not call it is still stuck.
- **For an HTTP service, link the API spec here** — `docs/swagger.yaml` plus the Swagger UI URL. One example request in the README, the full surface in the spec; don't list every endpoint by hand, because a hand-maintained endpoint list is wrong within a month.
- Common operations belong here too, briefly: run the tests, run migrations, build the image.

## Optional sections — pick what fits the project

Only what a real reader of *this* project would want, and always after the
essentials:

- **Configuration reference** — a table of the settings that matter (name, default, what changes if you change it). Long lists go in `docs/`.
- **Observability** — metrics endpoint, the handful of metrics worth watching, dashboards. If a dashboard is committed, link it and show a screenshot; that is the fastest way to make a service feel real to a newcomer.
- **Numbers that build confidence** — throughput, p99 latency, batch sizes, benchmark output. Say how they were measured, or they read as marketing.
- **Screenshots or a short GIF** for anything with a UI or a conversational flow. One image outperforms three paragraphs.
- **Examples** — an `examples/` walkthrough, a Postman collection, real request/response pairs.
- **API reference — required, not optional, for any HTTP service.** Link `docs/swagger.yaml` and the Swagger UI path; never inline the spec. See the OpenAPI skill.
- **Troubleshooting** — the three failures every newcomer actually hits, with the fix.
- **Contributing / development** — how to run tests and lint, coding conventions. Move it to `CONTRIBUTING.md` once it is more than a few lines: the README's reader is a user first, a contributor second.

## Minimal, but never at the user's expense

Be terse. Cut adjectives, background, history, and anything a reader does not
act on. **Do not cut what they need.** A README that omits a required
environment variable to stay short has not saved anyone time — it has moved the
cost from the writer to every reader, and multiplied it.

The test for every line: **would a first-time user get stuck, or make a wrong
assumption, without it?**

- Yes → it stays, however long the page gets. Required steps, config values, guarantees, the verify command, the failure they will hit.
- No → delete it. Prose about the design's elegance, dependency history, three ways to do the same thing, tutorials for tools they already know.

So brevity is applied to **wording**, not to coverage. Compress a paragraph into
a bullet; never drop the bullet. If the essentials genuinely need three screens
because the project has real setup, take three screens — then move the *detail*
(full config reference, per-feature docs, deep architecture) into `docs/` and
link it, so the README stays scannable while nothing is lost.

- **Aim for one to two screens** for the essentials, and treat overflow as a signal to move detail into `docs/`, not to delete it.
- **A table of contents only when the README is long enough to need one.**
- **No badge wall.** Build and coverage, if any; a row of twelve badges is decoration.
- **Never inline** the licence text, the changelog, or a roadmap — link them.
- **Delete aspirational content.** A documented flag that doesn't exist is a bug report waiting to happen, and "coming soon" sections rot in place.
- **Update it in the same commit** as the change that invalidates it. A README correct on day one and wrong by month three is the default outcome unless this is a habit.
