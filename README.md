# skills

Personal, portable skills. Grouped by topic, one sub-skill per folder, each
with a `SKILL.md` — so a topic can grow without one file growing to 500 lines.


| Topic | Skill | Covers |
|---|---|---|
| golang | [golang-structure](skills/golang/structure/SKILL.md) | Project layout: where code goes, scaled by project size |
| golang | [golang-config](skills/golang/config/SKILL.md) | Viper config: types/load split, precedence, flags, tests |
| golang | [golang-cmd](skills/golang/cmd/SKILL.md) | Commands with Cobra: main/cmd layout, command tree, flags, tests |
| golang | [golang-hexagonal](skills/golang/hexagonal/SKILL.md) | Ports and adapters: what becomes an interface, who implements it, mocks |
| golang | [golang-database](skills/golang/database/SKILL.md) | Native DB clients, hand-written SQL, pools, transactions, migrations |
| golang | [golang-testing](skills/golang/testing/SKILL.md) | What to test, table-driven scenarios, fakes, determinism, coverage |
| docs | [docs-readme](skills/docs/readme/SKILL.md) | README for end users: use case, features, solution design, how to run |
| docs | [docs-openapi](skills/docs/openapi/SKILL.md) | Mandatory docs/swagger.yaml for HTTP APIs, schemas, CI drift check |

Planned: `golang-deps`.

## Install

`install.sh` symlinks every skill into whichever tool you name. Links point
back at this repo, so editing a skill here updates every install, and re-running
replaces links instead of duplicating them.

**Claude Code** — all skills, globally:

```sh
./install.sh claude          # → ~/.claude/skills/<topic>-<skill>/
```

Restart the session afterwards. (Claude Code discovers skills one level deep, so
`golang/structure` is linked as `golang-structure`.)

**Cursor** — per project, since Cursor rules are project-scoped:

```sh
./install.sh cursor              # → ./.cursor/rules/<topic>-<skill>.mdc
./install.sh cursor ~/work/api   # or a specific project
```

The `.mdc` extension is required — Cursor ignores plain `.md` in
`.cursor/rules`. Each skill's `description` makes it agent-requested, so Cursor
pulls one in when it is relevant. Add `globs:` or `alwaysApply:` to a skill's
frontmatter to have it auto-attach to matching files instead.

**GitHub Copilot** — per project:

```sh
./install.sh copilot         # → ./.github/instructions/<topic>-<skill>.instructions.md
```

**Single skill, any tool** — one link, no script:

```sh
ln -sfn "$PWD/skills/golang/structure" ~/.claude/skills/golang-structure
```

**Anything else** (Gemini CLI, Codex, Windsurf, a coworker) — `SKILL.md` is
plain markdown with YAML frontmatter. Paste it, `@`-reference it, or point the
tool's rules directory at it with the same one-liner.

## Adding a skill

New sub-skill = folder under its topic + `SKILL.md` with `name` and
`description` frontmatter. `name` is `<topic>-<subskill>`, matching the link
the install creates. New topic = new dir under `skills/`; keep the depth at
exactly two.

Write `description` as a trigger ("Use when …"), not a summary — it decides
whether the skill loads, so keep triggers from overlapping between siblings of
the same topic.

Split a sub-skill when it passes ~200 lines; keep it one file below that.

Rules for content:

- If a generic best-practice doc would say it, leave it out. These files hold
  conventions specific to how I work.
- Inline the rules; don't send the agent to a URL to learn them. The agent may
  have no network, and a link is an invitation to burn tokens re-fetching what
  is already written.
- **Do** cite the repo of every library a skill prescribes, and say to take the
  newest release. Conventions are stable; library APIs are not, so the module
  path plus a "check upstream, don't code from memory" line is what keeps a
  skill from teaching a dead dependency. Pin no versions beyond a floor.
