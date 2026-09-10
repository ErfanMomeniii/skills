---
name: golang-cmd
description: Use when adding or changing a command or entry point in a Go service — wiring main and the cmd package, adding a subcommand or flag, grouping commands, or testing command behaviour. Cobra, with commands as thin wiring over internal packages.
---

# Go cmd

**Tool: Cobra.** Every entry point into the service — server, consumer, cron
job, one-off maintenance task — is a command, not a separate binary and not a
`main` branching on `os.Args`.

## Package

```
github.com/spf13/cobra                  https://github.com/spf13/cobra
```

**Always take the newest release.** Check upstream before writing from memory:

```sh
go get -u github.com/spf13/cobra
go list -m -u all | grep cobra
```

Examples here are written against cobra v1.10 — a floor, not a target. Cobra
ships a generator (`cobra-cli`); skip it. It scaffolds Viper wiring and a
license header you will delete. Writing `root.go` by hand is ten lines.

## Layout

```
main.go              calls cmd.Execute(), nothing else
cmd/
  root.go            root command, persistent flags, command tree, Execute()
  <command>.go       one file per command, named after the command
  <command>_test.go  tests for that command's own logic
```

One file per command, file name matching the command (`clean_up.go` →
`clean-up`). A single `commands.go` holding six commands is a merge conflict
generator, and it hides how many entry points the service really has.

## main

`main` does one thing, and it is the only place in the codebase that exits:

```go
func main() {
	if err := cmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
```

No flag parsing, no config loading, no dependency construction. Anything else
in `main` is unreachable from tests.

`os.Exit` anywhere else — inside a command, inside a use case — skips deferred
cleanup and makes the code untestable. Return an error instead.

## root.go

Root owns three things: the persistent flags, the config load, and the command
tree.

```go
var (
	cfgFile   string
	appConfig *config.Config
)

var rootCmd = &cobra.Command{
	Use:          "myservice",
	Short:        "One line, shown in the parent's command list",
	Long:         `...`,
	SilenceUsage: true,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		var err error
		appConfig, err = config.Init(cfgFile)
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}
		return nil
	},
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file path (default is ./config.yaml)")

	rootCmd.AddCommand(startCmd, versionCmd, cleanUpCmd)
	startCmd.AddCommand(serverCmd, consumerCmd)
}

func Execute() error { return rootCmd.Execute() }
```

- **Config loads once, in `PersistentPreRunE`.** Every command needs it, none should load it itself, and returning the error (not `log.Fatal`) means a bad config prints one line instead of a stack trace.
- **`SilenceUsage: true`.** Without it, a runtime failure — an unreachable dependency — dumps the full usage text after the error, burying it. Usage is for wrong *usage*, not for a failed run.
- **The whole tree is visible in one `init()`.** Reading `root.go` tells you every entry point. Commands registering themselves in their own `init()` scatter that.
- **`Execute()` returns the error**, it doesn't handle it. `main` decides the exit code.

## A command

```go
var serverCmd = &cobra.Command{
	Use:   "server",
	Short: "Start the HTTP API server",
	Long: `Starts the HTTP server.

The server is responsible for:
  • ...
  • ...`,
	Args: cobra.NoArgs,
	RunE: runServer,
}

func runServer(cmd *cobra.Command, args []string) error { ... }
```

- **The run function is a named function**, never an inline closure. A closure in a struct literal cannot be called from a test and grows without anyone noticing.
- **`RunE`, not `Run`.** Return the error and let `Execute` and `main` handle it. `Run` forces the command to swallow the error or exit on its own.
- **Set `Args`** — `cobra.NoArgs`, `cobra.ExactArgs(1)`. The default is "anything goes", so a mistyped flag silently becomes a positional argument and the command runs with defaults.
- **`Short` is one line** (it renders in the parent's list). **`Long` says what the command actually touches** — the reader is often an operator at 3am deciding whether it is safe to run.

## Grouping

A parent command with no `Run` is a namespace:

```go
var startCmd = &cobra.Command{
	Use:   "start",
	Short: "Run service components",
	Long:  `...`,   // no Run: bare `start` prints help
}
```

`myservice start server`, `myservice start consumer`. Group when a verb has
several targets; don't invent a namespace for a single command.

## Flags

- Bind flags to package-level vars in the command's `init()`; `PersistentFlags` when subcommands inherit them, `Flags` when they don't.
- **Required inputs use `MarkFlagRequired`**, not a manual empty-string check in the run function. Cobra then reports it consistently, before any dependency is constructed.
- **Destructive work is opt-in.** A command that deletes or mutates data defaults to reporting what it *would* do, with an `--apply` (or `--force`) flag defaulting to `false`. A bare run during an investigation must never destroy anything.
- Flag defaults belong to the flag, not to config. Anything an operator sets per-run is a flag; anything set per-environment is config.

## Commands stay thin

A command is wiring only: build dependencies from config, hand them to a use
case or job in `internal/`, wait, return.

```go
func runRefine(cmd *cobra.Command, args []string) error {
	a := app.New(appConfig)                  // dependencies
	defer a.Close()
	return job.NewRefineJob(a.Repo, a.Logger).Start(cmd.Context())  // logic lives there
}
```

Business logic in `cmd/` is untestable without building the whole CLI, and
unreachable from any other entry point. If a run function has branches worth
testing, the branches belong in `internal/`.

Use `cmd.Context()`, not `context.Background()` — cobra's context carries
cancellation, so Ctrl-C reaches the job.

Every service gets a `version` command printing build and runtime facts. It is
the fastest answer to "what is actually deployed".

## Tests — `<command>_test.go`

Don't test cobra; test the function the command calls and the guarantees the
command declares.

- **The extracted logic**, table-driven, with fakes for dependencies. Embed the dependency interface in a fake struct and implement only the methods this command calls — an unimplemented call then panics with the method name, which is the fastest possible diagnosis.
- **Selection rules that decide what gets touched.** For a command that deletes, the test that matters is the one proving it never selects live data.
- **Flag defaults for destructive commands.** Three lines, and they pin the one mistake that costs data:

```go
flag := cleanUpCmd.PersistentFlags().Lookup("apply")
if flag == nil {
	t.Fatal("the --apply flag is missing")
}
if flag.DefValue != "false" {
	t.Fatalf("--apply defaults to %q, it must default to false", flag.DefValue)
}
```

Comment *why* each test exists when the failure it prevents is data loss or a
silent no-op. That sentence is worth more than the assertion.
