# CLI Entry Point and Command Dispatch

PSF for the `hermes-fly` entry point script and its command routing logic.

**Related PSFs**: [00-architecture](00-hermes-fly-architecture-overview.md) | [07-deployment](07-deployment.md) | [03-operations](03-infrastructure-and-operations.md)

## 1. Scope

This document covers the main `hermes-fly` executable — the single entry point for the entire CLI. It handles:

- Shell configuration (`set -euo pipefail`)
- Symlink resolution to find `lib/` relative to the real script location
- Sourcing all 13 library modules
- Help text rendering
- Command dispatch via `case` statement
- App name resolution (`-a APP` flag or `current_app` from config)

## 2. File

| Path | Lines | Role |
|------|-------|------|
| `hermes-fly` | ~152 | Entry point, dispatcher |

## 3. Initialization Sequence

```text
1. set -euo pipefail
2. HERMES_FLY_VERSION="0.1.14"
3. Resolve symlinks to find real script location → SCRIPT_DIR
4. Source lib/ui.sh
5. Source lib/prereqs.sh
6. Source lib/fly-helpers.sh
7. Source lib/docker-helpers.sh
8. Source lib/messaging.sh
9. Source lib/config.sh
10. Source lib/status.sh
11. Source lib/logs.sh
12. Source lib/doctor.sh
13. Source lib/destroy.sh
14. Source lib/list.sh
15. Source lib/openrouter.sh
16. Source lib/deploy.sh
17. Call main() with all arguments
```

Symlink resolution loop (lines 6-12) ensures `hermes-fly` works when invoked via a symlink (e.g., after `ln -s` installation):

```bash
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
```

## 4. Command Dispatch

The `main()` function (line 84) uses a `case` statement:

| Argument | Handler | App resolution |
|----------|---------|----------------|
| `deploy` | `cmd_deploy "$@"` | Not needed (wizard collects config) |
| `status` | `cmd_status "$app"` | `config_resolve_app "$@"` |
| `logs` | `cmd_logs "$app"` | `config_resolve_app "$@"` |
| `doctor` | `cmd_doctor "$app"` | `config_resolve_app "$@"` |
| `list` | `cmd_list` | Not needed (lists all tracked apps) |
| `destroy` | `cmd_destroy "$app" "$@"` | `config_resolve_app "$@"` |
| `help`/`--help`/`-h` | `show_help` | N/A |
| `version`/`--version`/`-v` | Prints version | N/A |
| *(default)* | `show_help`, exits 1 | N/A |
| *(no args)* | `show_help` | N/A |

### App Name Resolution

For all management commands (`status`, `logs`, `doctor`, `destroy`), the app name is resolved via `config_resolve_app`:

1. Parse args for `-a APP` flag — use that if found
2. Otherwise, read `current_app` from `~/.hermes-fly/config.yaml`
3. If neither exists, print error and return 1

The `deploy` command does not resolve app name — it collects it interactively during the wizard.

## 5. Help System

Two help functions:

- `show_help()` — General CLI usage (commands, options, examples)
- `show_deploy_help()` — Deploy-specific help (triggered by `hermes-fly deploy --help`)

Help output is plain text via heredoc (`cat <<'EOF'`). No external man page or help generator.

## 6. Global State

| Variable | Set by | Purpose |
|----------|--------|---------|
| `HERMES_FLY_VERSION` | Entry point (line 4) | Version string, displayed by `version` command |
| `SCRIPT_DIR` | Entry point (line 12) | Root directory of the project, used for sourcing `lib/` |

## 7. Error Handling

- Default command (no args) shows help text (exit 0)
- Unknown commands show error message + help text (exit 1)
- Failed app resolution shows actionable error: `"No app specified. Use -a APP or run 'hermes-fly deploy' first."`
- All errors from subcommands propagate naturally via `set -e`

## 8. Extension Points

To add a new command:

1. Create `lib/newcommand.sh` with a `cmd_newcommand()` function
2. Add `source "${SCRIPT_DIR}/lib/newcommand.sh"` to the entry point
3. Add a `case` branch in `main()` dispatching to `cmd_newcommand`
4. Add the command to `show_help()` text

## 9. Testing

The entry point itself is tested via `tests/scaffold.bats` and `tests/integration.bats`:

- `scaffold.bats` — Verifies all modules load without error, all commands exist
- `integration.bats` — End-to-end smoke tests for help, version, and error cases
