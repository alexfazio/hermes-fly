# Maintainability

PSF for code conventions, extension patterns, dependency management, and long-term maintenance concerns.

**Related PSFs**: [00-architecture](00-hermes-fly-architecture-overview.md) | [05-testing](05-testing-and-qa.md) | [09-security](09-security.md)

## 1. Scope

This document covers the patterns and conventions that keep hermes-fly maintainable as it evolves. It addresses code organization, naming, error handling, testing expectations, and how to extend the system with new features.

## 2. Code Conventions

### 2.1 Shell Settings

Every executable file starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Flag | Effect |
|------|--------|
| `-e` | Exit on any unhandled error |
| `-u` | Treat unset variables as errors |
| `-o pipefail` | Propagate pipe failures |

This ensures fail-fast behavior. Any unhandled error terminates the script rather than silently continuing with corrupt state.

### 2.2 Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Module files | `lib/{name}.sh` | `lib/deploy.sh` |
| Public functions | `module_action` or `cmd_name` | `deploy_preflight`, `cmd_status` |
| Internal functions | `_module_action` or `_action` | `_remove_app_entry`, `_deploy_fallback_mem` |
| Constants | `UPPER_SNAKE_CASE`, `readonly` | `EXIT_SUCCESS`, `EXIT_AUTH` |
| Global state variables | `DEPLOY_*` (exported) | `DEPLOY_APP_NAME`, `DEPLOY_REGION` |
| Module-local globals | `_MODULE_*` | `_UI_SPINNER_PID`, `_ORG_SLUGS` |
| Environment overrides | `HERMES_FLY_*` | `HERMES_FLY_VERBOSE`, `HERMES_FLY_CONFIG_DIR` |

### 2.3 Function Documentation

Each public function has a block comment:

```bash
# --------------------------------------------------------------------------
# function_name "arg1" "arg2" — short description
# Longer explanation if needed.
# Returns: 0 on success, 1 on failure
# --------------------------------------------------------------------------
```

Internal functions use shorter comments:

```bash
# _helper — short description
```

### 2.4 Error Messages

Follow the pattern: **what went wrong** + **how to fix it**:

```bash
ui_error "Required tool not found: ${tool}"
# vs. just: "Error: missing tool"

doctor_report "machine" "fail" "Machine not running. Start with: fly machine start -a ${app_name}"
# vs. just: "Machine not running"
```

### 2.5 Module Guard Pattern

Every `lib/*.sh` file starts with:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi
```

And guards against re-sourcing dependencies:

```bash
if [[ -z "${EXIT_SUCCESS+x}" ]]; then
  source "${_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi
```

The `2>/dev/null || true` ensures sourcing failures don't crash during testing when modules are sourced individually.

## 3. Module Architecture

### 3.1 Separation of Concerns

Each module has a single responsibility:

| Module | Responsibility boundary |
|--------|------------------------|
| `ui.sh` | Terminal output, user input, spinners — never calls Fly.io |
| `config.sh` | Local file I/O — no network, no UI beyond file reads/writes |
| `fly-helpers.sh` | Fly.io CLI wrapper — no business logic, no UI |
| `docker-helpers.sh` | Template I/O — no network, no UI |
| `messaging.sh` | Messaging platform configuration — UI prompts + validation |
| `prereqs.sh` | Platform detection, tool auto-install — no network except install commands |
| `openrouter.sh` | OpenRouter model discovery — provider-first UI, model fetching, caching; depends on ui.sh |
| `deploy.sh` | Orchestration — combines all other modules |
| `status.sh`, `logs.sh`, `doctor.sh`, `destroy.sh` | Single-command modules |

### 3.2 Dependency Direction

Dependencies flow one way: higher-level modules depend on lower-level ones. No circular dependencies.

```text
Level 0 (standalone):  config.sh, docker-helpers.sh
Level 1 (UI only):     ui.sh (defines constants used by all)
Level 2 (UI only):     fly-helpers.sh → ui.sh, openrouter.sh → ui.sh
Level 3 (commands):    status.sh, logs.sh, doctor.sh, destroy.sh → fly-helpers.sh + ui.sh
Level 4 (messaging):   messaging.sh → ui.sh
Level 5 (orchestrator): deploy.sh → everything (including openrouter.sh)
```

### 3.3 State Management

hermes-fly uses two state mechanisms:

1. **Global variables** (`DEPLOY_*`): ephemeral, exist only during a single deploy run
2. **Config file** (`~/.hermes-fly/config.yaml`): persistent across invocations

No global mutable state is shared between commands. Each command starts with a clean resolution of the app name and fetches all state from Fly.io APIs.

## 4. Extension Patterns

### 4.1 Adding a New Command

1. Create `lib/newcommand.sh`:

```bash
#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

cmd_newcommand() {
  local app_name="$1"
  # implementation
}
```

2. Add to entry point `hermes-fly`:

```bash
source "${SCRIPT_DIR}/lib/newcommand.sh"
# In main():
newcommand)
    local app
    app="$(config_resolve_app "$@" 2>/dev/null)" || { ... }
    cmd_newcommand "$app"
    ;;
```

3. Update `show_help()` text
4. Create `tests/newcommand.bats`

### 4.2 Adding a New Doctor Check

In `lib/doctor.sh`, add:

1. A check function: `doctor_check_new_thing()`
2. A call in `cmd_doctor()` with `doctor_report`
3. A test in `tests/doctor.bats`

### 4.3 Adding a New LLM Provider

In `lib/deploy.sh`:

1. Add a case in `deploy_collect_llm_config()` for the new provider
2. Add secret mapping in `deploy_provision_resources()`
3. Add API connectivity check in `doctor_check_api_connectivity()`
4. Update entrypoint.sh to bridge the new secret to `.env`

### 4.4 Adding a New Messaging Platform

1. Add validation function in `lib/messaging.sh`
2. Add setup wizard function
3. Add option to `messaging_setup_menu()`
4. Add secret handling in `deploy_provision_resources()`
5. Update entrypoint.sh secret bridging

## 5. Dependency Management

### 5.1 External Dependencies

hermes-fly has deliberately minimal external dependencies:

| Dependency | Version requirement | Status |
|------------|-------------------|--------|
| `bash` | 3.2+ | Ships with macOS |
| `flyctl` | >= 0.2.0 | Checked at runtime |
| `git` | Any | Checked at runtime |
| `curl` | Any | Checked at runtime |
| `sed`, `grep` | POSIX | System utilities |
| `jq` | Any | Optional (doctor.sh only) |

No package manager (npm, pip, brew) is needed. No build step.

### 5.2 Vendored Dependencies

BATS is vendored in `tests/bats/` — no test dependency installation needed.

### 5.3 Upstream Dependencies

The Dockerfile installs Hermes Agent from the upstream repository at deploy time:

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh | bash
```

This means Hermes Agent updates happen automatically on redeploy. The `HERMES_VERSION` defaults to `"main"` (latest).

## 6. Testing Expectations

### 6.1 New Code Should Have Tests

Every new module or function should have a corresponding `.bats` file. Test the public API of each module, not internals.

### 6.2 Test Isolation

Tests must not:
- Call real Fly.io APIs (use mocks)
- Modify the user's `~/.hermes-fly/` directory (use `HERMES_FLY_CONFIG_DIR`)
- Leave temp files behind (clean up in `teardown`)
- Depend on network connectivity

### 6.3 Test Naming

```bash
@test "function_name: what it does when given specific input" {
```

Prefix with function name for scannability.

## 7. Technical Debt and Known Issues

### 7.1 JSON Parsing

grep/sed-based JSON parsing is fragile. Works for Fly.io's current output format but could break on:
- Multi-line JSON formatting changes
- Deeply nested structures
- Special characters in values

Mitigation: `doctor.sh` already uses jq when available. Other modules could follow suit.

### 7.2 Global Variable State

The deploy wizard passes state via exported global variables (`DEPLOY_*`). This works but makes the data flow implicit. An alternative would be a single associative array or writing to a temp file.

### 7.3 Template Version Pinning

`HERMES_VERSION` defaults to `"main"`, meaning deploys always get the latest Hermes Agent. This could cause unexpected behavior if upstream introduces breaking changes. Consider pinning to a specific tag.

### 7.4 sed Portability

Some `sed` usage relies on GNU sed features (e.g., `sed -i.bak`). The `.bak` extension makes it work on both macOS (BSD sed) and Linux (GNU sed), but edge cases may exist.

## 8. Documentation

### 8.1 Edge Case Handling

The prerequisite auto-install module (`lib/prereqs.sh`) handles complex edge cases such as platform detection fallbacks, installation failures, and permission scenarios. Detailed documentation of how each edge case is handled is available in [docs/EDGE_CASE_HANDLING.md](../EDGE_CASE_HANDLING.md).

This includes:
- Platform detection edge cases (unsupported OS, unset/empty environment variables)
- Installation fallback chains for missing package managers
- Permission handling and sudo scenarios
- System state edge cases and their mitigations

## 9. Versioning

`HERMES_FLY_VERSION` is set in line 4 of `hermes-fly`:

```bash
HERMES_FLY_VERSION="0.1.14"
```

No automatic version bumping. Update manually when releasing.

## 10. Release Checklist

1. Update `HERMES_FLY_VERSION` in `hermes-fly`
2. Run full test suite: `./tests/bats/bin/bats tests/`
3. Test a real deploy on Fly.io (manual)
4. Update README if commands/options changed
5. Tag and push: `git tag v0.1.X && git push --tags`
