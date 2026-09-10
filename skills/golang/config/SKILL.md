---
name: golang-config
description: Use when defining, loading, or extending configuration in a Go service — adding a config field or block, wiring a dependency's settings, adding a feature flag, or writing config tests. Viper + mapstructure, typed structs, layered precedence.
---

# Go config definition and loading

**Tool: Viper**, decoding into typed structs via mapstructure. Nothing else.

Config is a struct the compiler checks. Not `viper.GetString("x.y")` at the call
site, not `os.Getenv` sprinkled through packages — both turn a typo into a
runtime zero value and put config parsing in every file that reads a setting.

## Packages

```
github.com/spf13/viper                  https://github.com/spf13/viper
github.com/go-viper/mapstructure/v2     https://github.com/go-viper/mapstructure
```

**Always take the newest release.** These APIs move — decode hooks, option
names, and struct-tag behaviour have all changed across versions. Check the
upstream repo or module proxy before writing code from memory, and never copy a
config package forward from an older service without re-checking it:

```sh
go get -u github.com/spf13/viper github.com/go-viper/mapstructure/v2
go list -m -u all | grep -E 'viper|mapstructure'   # what's outdated
```

`github.com/mitchellh/mapstructure` is **dead** — last release v1.5.0 in 2022.
Viper itself moved to `github.com/go-viper/mapstructure/v2`. If an existing
service still imports the mitchellh path, that is a migration to do, not a
pattern to copy. The v2 fork keeps the same function names, so imports and
hook signatures are what change.

Examples below are written against viper v1.21 / mapstructure v2. Treat any
version number in this file as a floor, not a target.

## Package layout

One package, `internal/config`, split by rate of change:

```
internal/config/
  types.go        config structs, enums, String() methods
  config.go       Load() and Init() — loading logic only
  builtin.go      embedded default config
  config_test.go  tests for loading behaviour
```

`types.go` is read and edited constantly — every new setting lands there.
`config.go` is read rarely, only when loading behaviour changes. Split, adding a
field never touches loading code and a loading change never risks a struct. In
one file, every field addition rides on top of the parsing logic in the same
diff.

Commit an example config at the repo root with every block filled with
realistic non-secret values. It is the only honest documentation of what the
service accepts. The real config file is gitignored.

## Layered precedence

Three sources, lowest priority first. This ordering is the whole design:

1. **Embedded defaults** — a default config compiled into the binary. The
   service must start with no external file. Anything that can have a sane
   default has one here.
2. **Operator file** — optional path from a flag, *merged* over the defaults, so
   a partial file is valid and overrides only the keys it names. Never
   `ReadInConfig` over the defaults; that replaces instead of merging and turns
   every deploy file into a full copy that rots.
3. **Environment** — highest priority, via `AutomaticEnv`. This is how secrets
   and per-environment values arrive in a container, without a file.

Register an env key replacer so nested keys map predictably
(`some.nested_key` ← `SOME_NESTED_KEY`). Without it, only top-level keys
resolve from the environment and the failure is silent.

## Loading

`Load` takes the default bytes as a parameter and returns the struct. That
parameter is what makes defaults substitutable in tests; a function reaching for
a package-level variable is not testable against fixture defaults.

```go
import (
	"bytes"
	"fmt"
	"strings"

	"github.com/go-viper/mapstructure/v2"
	"github.com/spf13/viper"
)

func Load(configFilename string, builtinConfig []byte) (Config, error) {
	cfg := &Config{}
	v := viper.New()
	v.SetConfigType("yaml")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_", "-", "_"))
	v.AutomaticEnv()

	if err := v.ReadConfig(bytes.NewReader(builtinConfig)); err != nil {
		return *cfg, fmt.Errorf("config: reading builtin defaults: %w", err)
	}
	if configFilename != "" {
		v.SetConfigFile(configFilename)
		if err := v.MergeInConfig(); err != nil {
			return *cfg, fmt.Errorf("config: merging %q: %w", configFilename, err)
		}
	}

	hooks := mapstructure.ComposeDecodeHookFunc(
		mapstructure.StringToTimeDurationHookFunc(),
		mapstructure.StringToSliceHookFunc(","),
		// plus one hook per custom type the config uses
	)
	if err := v.Unmarshal(cfg, viper.DecodeHook(hooks)); err != nil {
		return *cfg, fmt.Errorf("config: unmarshalling %q: %w", configFilename, err)
	}
	return *cfg, nil
}
```

`Init(path)` is the thin wrapper the app calls, passing the real defaults.

Wrap every error with `%w` and the file it came from. A config failure is the
first thing an operator sees at 3am; "unmarshal error" without the path is a
wasted hour.

Any type Viper can't decode gets a **decode hook**, not a `string` field parsed
at each use. One hook converts once, at the boundary, and a bad value fails at
startup instead of on the request that first touches it.

## Types

- One struct per dependency or concern, nested in the root `Config`. The struct boundary is the unit you pass around.
- `mapstructure:"snake_case"` on every field. A wrong or missing tag decodes to the zero value with no error — the most common and most expensive config bug.
- Durations are `time.Duration`, written `"2s"` / `"250ms"`. An int of unstated unit is a bug waiting for the next reader.
- Give the same kind of dependency the same shape across the codebase (e.g. every HTTP client block: base URL, timeout, credential). Predictable beats bespoke.
- Enums are a typed int (or string) with a `String()` method, not bare strings compared at call sites.
- Mark values with no safe default as required and fail loudly at startup. A service that boots with an empty upstream URL fails later, in production, on a user's request.
- Mask credentials in `String()`. Config gets logged.

## Feature flags

A flag lives in config like anything else. Two rules, and they are non-negotiable:

- **Default to off.** The embedded default disables the feature.
- **The zero value must be the safe value.** If a flag has a scope (percentage, allowlist, tenant set), zero/empty must mean *nobody*. An operator file written before the flag existed will supply exactly that zero — it must never read as "everyone".

Shape follows the project: a bare `Enabled bool` when that is the decision, plus
scope and limit fields only when the rollout actually needs them. Don't
scaffold percentages for a flag that is on or off.

## Wiring

Load once, at the process entry point — wherever the project already starts:
`main`, or the CLI root's pre-run hook if it uses one. Never load twice, never
load lazily inside a package; two loads mean two truths.

Pass each component the **narrow struct it needs**, not the root `*Config`. A
constructor taking the whole config can reach anything, so its real dependencies
are invisible and its tests need a full config to build. Take `config.Server`
and the signature states the truth.

## Tests — `config_test.go`

Package-internal, so tests can reach the embedded defaults.

Write a helper that puts YAML in `t.TempDir()` and returns the path; file cases
need a real file, and `t.TempDir()` cleans itself up.

Cover, per config block:

- **Defaults** — load with no file, against the *real* embedded defaults. This is what catches a broken tag or wrong nesting; a fixture-only test proves nothing about what ships.
- **File override** — a partial file, asserting the fields whose zero value would be dangerous.
- **Missing-key safety** — a file omitting a newly added key leaves the feature off.
- **Masking** — `String()` output has no credential in it.

`require` for what invalidates the rest of the test (the error), `assert` for
values. When a field's silent zero would break a feature, say so in a comment —
that sentence is the reason the test exists.
