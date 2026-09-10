---
name: docs-openapi
description: Use when a service exposes an HTTP API — adding or changing an endpoint, request or response body, or status code. Requires a committed OpenAPI (Swagger) spec at docs/swagger.yaml, kept in sync with the code and drift-checked in CI.
---

# OpenAPI / Swagger

**If the service exposes HTTP, `docs/swagger.yaml` is mandatory.** Not optional,
not "once the API stabilises". An HTTP endpoint without a spec is an
undocumented integration contract, and the cost lands on every consumer who has
to read handler code, guess from a curl, or ask in chat.

Language-agnostic: the spec is the deliverable, whatever generates it.

## The artifact

```
docs/
  swagger.yaml     the spec — committed, reviewed, the source of truth for consumers
  swagger.json     same content for tools that want JSON (optional)
```

- **Committed to the repo**, next to the code it describes, reviewed in the same pull request as the endpoint it documents.
- **YAML for the checked-in copy** — it diffs readably in review, which is the whole reason it lives in git.
- **One spec per service.** A spec shared across services becomes nobody's responsibility.
- The rendered UI is a convenience; the file is the artifact. It works with the service not running, diffs in review, and feeds client generation.

## Spec-first or code-first — pick per project

**Code-first.** Annotate the handlers, generate the spec. The annotation sits
next to the function it documents, so a changed response is visible in review
and the spec cannot describe an endpoint that doesn't exist. Default for a
service whose API you own.

**Spec-first.** Write the spec by hand, generate server interfaces, models, and
clients from it, implement against them. Right when the API is a negotiated
contract with another team, when it must exist before the code, or when several
services must implement the same interface.

Never both directions at once: whichever side generates, the other is generated.
Hand-editing a generated file is how a spec starts lying.

Generators exist for every ecosystem — annotation-based ones that emit the spec,
and spec-based ones that emit types, servers, and clients. Take the newest
release of whichever the project uses, put the invocation in a `make swagger`
target, and record the choice in the README. Nobody remembers the flags, and two
developers on different generators produce noisy diffs.

## What every operation must document

Per path and method:

- **Summary** — one line, imperative: "Create an order".
- **Description** — what it does *to the system*: side effects, idempotency, what a retry does, ordering guarantees. Not a restatement of the summary.
- **Tag** by resource (`orders`, `stock`) so the UI groups usefully.
- **Parameters** — path, query, and header params with types, whether required, and bounds.
- **Request body** — a named schema, with an example.
- **Every response the code can actually return**, each with a schema: success codes *and* every failure. A 409 the code returns but the spec omits is precisely the case the consumer won't handle.
- **Security** — declared on everything authenticated, deliberately absent on what is public. A reader must be able to tell which is which.

```yaml
paths:
  /orders:
    post:
      summary: Create an order
      description: >
        Validates the order and reserves stock atomically. A rejected order
        leaves no partial reservation. Safe to retry with the same
        Idempotency-Key.
      tags: [orders]
      security: [{ bearerAuth: [] }]
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CreateOrderRequest' }
      responses:
        '201':
          description: created
          content:
            application/json:
              schema: { $ref: '#/components/schemas/OrderResponse' }
        '400':
          description: validation failed
          content:
            application/json:
              schema: { $ref: '#/components/schemas/ErrorResponse' }
        '409':
          description: insufficient stock
          content:
            application/json:
              schema: { $ref: '#/components/schemas/ErrorResponse' }
```

## Schemas

- **Transport types only.** The spec describes request/response DTOs, never internal domain models. Publishing a domain type exposes internal fields, couples the wire format to a refactor, and leaks whatever sensitive field the struct happens to carry.
- **Named schemas under `components`, referenced with `$ref`.** Inline schemas can't be reused and can't generate a client type worth having.
- **No free-form objects.** `type: object` with no properties, or a map of `any`, makes the spec useless for generation — which is most of its value.
- **One shared `ErrorResponse`** for the whole service, so every failure has the same shape and consumers write one error path.
- **`required`, formats, enums, and bounds** stated. They are the validation contract, and generators turn them into real types.
- **`example` on every field.** It makes the UI's "try it" body real instead of `"string"`, and it is the fastest documentation a reader gets.

## Versioning

- Version in the base path (`/api/v1`) and in `info.version`.
- Changing the meaning of an existing field or response is **breaking**: add a field or a version, never redefine one.
- The spec diff is the clearest statement of what an API change does to consumers — often clearer than the handler diff. Read it that way in review.

## Serving the UI

- Behind a config flag: on in development, in production only behind auth or an internal-only route. A public UI is a free map of the API surface for anyone scanning.
- Serve the file that is committed, not a second copy generated at boot.

## Keeping it true — the part that matters

A spec rots the moment someone forgets to regenerate or update it. Close that in
CI:

```sh
make swagger
git diff --exit-code docs/     # fails the build if the committed spec is stale
```

- **Drift check in CI, failing the build.** Without it, none of the above survives a month.
- **Validate the spec** with a linter in the same job; a spec that doesn't parse generates nothing.
- **Spec-first projects** get the mirror check: regenerate the types and diff them, so an edited spec cannot silently diverge from the code.

## Consuming someone else's API

When calling a service that publishes a spec, generate the client instead of
hand-writing request structs, then wrap it behind your own interface so the
generated code stays at the edge and their spec changes don't reach your core
logic.

## In the README

A spec nobody finds does no work. Per the README skill: link `docs/swagger.yaml`
and the UI path from the API reference section, and show one real request and
response in the usage section — a reader should be able to call the service
before opening the spec.
