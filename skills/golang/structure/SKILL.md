---
name: golang-structure
description: Use when creating, structuring, or reorganizing a Go project — choosing where a file or package goes, adding a top-level directory or a new binary, or reviewing a repo's structure. Applies golang-standards/project-layout, scaled to project size.
---

# Go project structure

Use the `golang-standards/project-layout` convention. It is inlined in full
below — nothing here requires looking anything up.

Two caveats belong to the convention itself, and both are rules:

- It is **not an official standard from the core Go dev team.** It is community convention.
- For learning Go, a PoC, or a small personal project it is **overkill**: a single `main.go` plus `go.mod` is more than enough.

So pick the tier before creating anything.

## Pick the tier

| Project | Layout |
|---|---|
| Learning, PoC, script | `main.go` + `go.mod` at root. Nothing else. |
| Library | Packages at root (`captcha/`, `observer/`). No `/pkg`, no `/cmd`. |
| Single service | `/cmd/<name>` + `/internal`, then `/api`, `/configs`, `/build`, `/deployments` as needed. |
| Multi-binary / platform | Full tree below. |

Create a directory when there is a file to put in it. An empty `/tools` is
noise, not structure. Moving up a tier later is a `git mv`, not a rewrite.

## Modules

- Use Go Modules unless there is a specific reason not to.
- Module path's first component should contain a dot (`github.com/user/repo`) — no longer strictly enforced, still correct.

## Go directories

### `/cmd`

Main applications. One directory per binary, **directory name = executable name** (`/cmd/myapp` builds `myapp`).

Keep it tiny: "a small `main` function that imports and invokes the code from the `/internal` and `/pkg` directories and nothing else." Flag/env parsing and wiring only. Reusable code → `/pkg`; non-reusable → `/internal`.

### `/internal`

Private application and library code — code you don't want others importing. **The Go compiler enforces this**: a package under `internal/` can only be imported by packages sharing a common ancestor.

Not limited to the root; an `internal/` may sit at any level of the tree, scoping privacy to that subtree.

Optional inner structure when the repo is big:

```
/internal/app/myapp        application code
/internal/pkg/myprivlib    code shared across your apps, still private
```

Skip that split until more than one app shares code. `/internal/<domain>` is fine and usually better.

### `/pkg`

Library code that's OK for external applications to use (`/pkg/mypubliclib`). Its value is the signal: "importing this is supported."

Optional and **not universally accepted** — for smaller projects "an extra level of nesting doesn't add much value." Promote from `/internal` when an external module actually imports it. Don't start here.

### `/vendor`

Application dependencies. Created with `go mod vendor`; pre-1.14 needs `-mod=vendor`. With module proxy support you usually don't need it at all. **Don't commit dependencies if you're building a library.**

## Service and web

- `/api` — OpenAPI/Swagger specs, JSON schema files, protocol definition files (proto).
- `/web` — web-specific components: static assets, server-side templates, SPAs.

## Application directories

- `/configs` — configuration file templates or default configs. `confd`/`consul-template` files live here. Templates, not real secrets.
- `/init` — system init (systemd, upstart, sysv) and process manager/supervisor configs (runit, supervisord).
- `/scripts` — build, install, analysis and similar operations. Purpose: **keep the root-level Makefile small and simple** — Makefile targets call scripts, they don't inline logic.
- `/build` — packaging and CI:
  - `/build/package` — cloud (AMI), container (Docker), OS package configs.
  - `/build/ci` — CI tool configs. Some CI tools are picky about config location; if the tool demands the root or `.github/`, obey the tool.
- `/deployments` — IaaS/PaaS/orchestration configs and templates (docker-compose, kubernetes/helm, terraform). Often named `/deploy` in Kubernetes repos; either is fine, pick one per repo.
- `/test` — additional external test apps and test data. Structure is flexible; larger projects use `/test/data` or `/test/testdata`. Go ignores directories and files beginning with `.` or `_`. Unit tests stay next to their code as `*_test.go`.

## Supporting directories

- `/docs` — design and user documents, *in addition to* godoc-generated docs.
- `/tools` — supporting tools for this project; may import from `/pkg` and `/internal`.
- `/examples` — examples for your applications and public libraries.
- `/third_party` — external helper tools, forked code, other third-party utilities (e.g. Swagger UI).
- `/githooks` — git hooks.
- `/assets` — images, logos, other repo assets.
- `/website` — project website data, if not using GitHub Pages.

## Directories you shouldn't have

- **`/src`** — a Java habit. `$GOPATH/src` is a *workspace* directory and has nothing to do with your project; a project-level `/src` only adds nesting and confusion. The module path is the namespace.
- **Layer directories at root** — `/models`, `/controllers`, `/services`, `/utils`, `/helpers`, `/common`. Group by domain inside `/internal` (`internal/order`, `internal/billing`), not by technical role.

## Review checklist

- Does the tier match the project, or are there empty directories?
- Is anything in `/pkg` that no external module imports? → `/internal`.
- Does any `main()` hold business logic? → `/internal`.
- Any `/src`, `/utils`, `/common`, or root-level layer directories? → regroup by domain.
- Does the root Makefile inline logic that belongs in `/scripts`?
- Naming, formatting, style questions: run `gofmt` and `staticcheck` before arguing.
