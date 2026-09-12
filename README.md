# skills

Opinionated engineering conventions packaged as agent skills for Claude Code,
Cursor, and GitHub Copilot.

Organised by topic, and not tied to one language: the documentation skills
(README structure, OpenAPI) apply to any project, while language topics hold
their own conventions. Today that is Go and docs; new topics are new folders.

## What this is

Coding agents write plausible code that ignores how your project actually does
things: where a file belongs, how config is loaded, what gets an interface, how
tests are shaped. These skills answer those questions once, so the agent follows
a real convention instead of inventing one per session.

Each skill is a single markdown file with a trigger line. The agent loads one
only when it is relevant — writing a repository, adding a command, editing a
README — so they cost nothing until they apply.

They are opinionated on purpose, and they say why: no ORM, ports and adapters,
table-driven tests, hand-written mocks, a committed OpenAPI spec. Read one
before installing to see whether you agree.

## Skills

| Topic | Skill | Covers |
|---|---|---|
| golang | [golang-structure](skills/golang/structure/SKILL.md) | Project layout: where code goes, scaled by project size |
| golang | [golang-config](skills/golang/config/SKILL.md) | Viper config: types/load split, precedence, feature flags, tests |
| golang | [golang-cmd](skills/golang/cmd/SKILL.md) | Commands with Cobra: main/cmd layout, command tree, flags, tests |
| golang | [golang-hexagonal](skills/golang/hexagonal/SKILL.md) | Ports and adapters: what becomes an interface, who implements it, mocks |
| golang | [golang-database](skills/golang/database/SKILL.md) | Native DB clients, hand-written SQL, pools, transactions, migrations |
| golang | [golang-testing](skills/golang/testing/SKILL.md) | What to test, table-driven scenarios, fakes, determinism, coverage |
| golang | [golang-logging](skills/golang/logging/SKILL.md) | Structured logging with zap: port, levels, field naming, what never gets logged |
| docs | [docs-readme](skills/docs/readme/SKILL.md) | README for end users: use case, features, solution design, how to run |
| docs | [docs-openapi](skills/docs/openapi/SKILL.md) | Mandatory `docs/swagger.yaml` for HTTP APIs, schemas, CI drift check |

## Install

### Claude Code — plugin marketplace

Nothing to clone. Two commands in any Claude Code session:

```
/plugin marketplace add ErfanMomeniii/skills
/plugin install skills@erfan
```


Restart the session. Skills are then available as `skills:golang-structure`,
`skills:docs-readme`, and so on, and the agent picks the right one from its
description.

Pin to a tag or branch if you prefer:

```
/plugin marketplace add ErfanMomeniii/skills@v1
```

Pull later changes with:

```
/plugin marketplace update erfan
```

### Cursor, Copilot, or Claude Code without the plugin

These link the files into a tool's rules directory, so clone the repo first and
keep it somewhere permanent — the links point back at it.

```sh
git clone https://github.com/ErfanMomeniii/skills.git
cd skills
```

Then pick a target:

```sh
./install.sh claude                 # → ~/.claude/skills/<topic>-<skill>/        (global)
./install.sh cursor                 # → ./.cursor/rules/<topic>-<skill>.mdc      (this project)
./install.sh cursor ~/work/api      # → that project's .cursor/rules/
./install.sh copilot ~/work/api     # → that project's .github/instructions/
```

Re-run any time; links are replaced, never duplicated. Notes:

- **Claude Code** discovers skills one level deep, so `golang/structure` installs as `golang-structure`. Restart the session afterwards.
- **Cursor** rules are project-scoped, and the `.mdc` extension is required — Cursor ignores plain `.md` in `.cursor/rules`. Each skill's `description` makes it agent-requested; add `globs:` or `alwaysApply:` to a skill's frontmatter if you want it auto-attached to matching files.
- **One skill only**, no script: `ln -sfn "$PWD/skills/golang/structure" ~/.claude/skills/golang-structure`
- **Any other tool** (Gemini CLI, Codex, Windsurf): `SKILL.md` is plain markdown with YAML frontmatter. Paste it, `@`-reference it, or link it into that tool's rules directory the same way.

## Using them

Once installed, nothing else is required — the agent reads a skill's description
and loads it when the work matches. You can also ask for one by name: "use
golang-hexagonal and add a payments repository".

Skills disagree with each other on nothing, but they do assume each other: the
database skill expects repositories behind ports, the README skill expects an
OpenAPI spec for HTTP services. Installing the whole set is the intended use;
installing one is fine too.

## Forking and editing

The conventions here are one team's answers. Fork the repo, edit the markdown,
and re-install — there is no build step, no code, and no generation.

Layout is `skills/<topic>/<skill>/SKILL.md`, exactly two levels deep. Each file
starts with:

```yaml
---
name: golang-structure
description: Use when creating, structuring, or reorganizing a Go project — ...
---
```

- `name` is `<topic>-<skill>` and is what the agent invokes. It comes from the frontmatter, not the directory, so it stays stable across installs.
- `description` is a trigger ("Use when …"), not a summary. It decides whether the skill loads, so keep triggers from overlapping.
- Split a skill when it passes ~200 lines.

To serve your fork as a marketplace, edit `.claude-plugin/marketplace.json`
(`name`, `owner`) and `.claude-plugin/plugin.json` (`name`, `skills`). A new
topic directory needs one line added to that `skills` array; a new skill inside
an existing topic needs nothing. Push to the default branch — that is the whole
publishing process, no CI and no release.

Content rules the existing skills follow:

- If a generic best-practice document would say it, leave it out. These files exist to hold decisions a team actually made.
- Inline the rules rather than linking out. The agent may have no network, and a link invites re-fetching what is already written.
- Do cite the repository of every library a skill prescribes, and say to take the newest release. Conventions are stable; library APIs are not.

## License

MIT — see [LICENSE](LICENSE).
