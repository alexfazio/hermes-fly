# Prerequisite Auto-Install

Enhance the deploy wizard so that missing prerequisites (`fly`, `git`, `curl`)
are automatically resolved instead of producing a dead-end error.

**Status**: Plan
**Affects**: `lib/deploy.sh` (preflight), new `lib/prereqs.sh`

---

## Problem

Running `hermes-fly deploy` on a fresh machine immediately fails:

```
sprite@hermes-fly-test:~# hermes-fly deploy
  ✗ Missing prerequisites
```

The current `deploy_check_prerequisites()` (deploy.sh:69-78) checks whether
`fly`, `git`, and `curl` exist on PATH. If any tool is missing, it returns 1
and the spinner prints "Missing prerequisites" with no further guidance. The
user is left stranded — no install instructions, no links, no next steps.

This violates the project's core design principle of guiding beginners through
every step of deployment.

## Root Cause

`deploy_check_prerequisites()` was designed as a gate, not a guide. It answers
"are we ready?" but does nothing to *make* the system ready. On a fresh machine
(common for Fly.io Sprites, new VPS instances, clean containers), none of the
three required tools may be present.

The preflight flow (deploy.sh:97-173) stops at the first failure and has no
recovery path for missing tools — unlike the auth check, which already has an
interactive retry loop.

## Design Principles

1. **Confirm before acting** — always prompt the user before installing anything
2. **Auto-install first, guide as fallback** — attempt native package manager
   install; if it fails, show diagnostic info + manual instructions
3. **Never block silently** — every failure path must end with actionable output
4. **Keep it simple** — support the two dominant platforms (macOS + apt-based
   Linux); don't try to cover every distro

## Solution Overview

Replace the current binary pass/fail prerequisite check with a three-phase
flow: **detect → offer to install → verify**.

```
deploy_check_prerequisites()
  │
  ├─ For each tool (fly, git, curl):
  │   ├─ command -v tool → found? skip
  │   └─ missing?
  │       ├─ Prompt: "Missing: tool. Install now? [y/N]"
  │       ├─ User says yes:
  │       │   ├─ Detect OS (Darwin / apt-based Linux)
  │       │   ├─ Run install command with output visible
  │       │   ├─ Verify: command -v tool
  │       │   ├─ Success → continue
  │       │   └─ Failure → show diagnostic info + manual guide
  │       └─ User says no:
  │           └─ Show manual install guide, return 1
  │
  └─ All tools present → return 0
```

## Per-Tool Install Strategy

### flyctl

| Platform | Install method |
|----------|---------------|
| macOS (brew available) | `brew install flyctl` |
| macOS (no brew) | `curl -L https://fly.io/install.sh \| sh` |
| Linux (any) | `curl -L https://fly.io/install.sh \| sh` |

Fly's official install script is cross-platform and doesn't require sudo. It
installs to `~/.fly/bin/` and prints a PATH instruction. After install, add
`~/.fly/bin` to PATH for the current session.

**Fallback guide**: Link to https://fly.io/docs/flyctl/install/

### git

| Platform | Install method |
|----------|---------------|
| macOS | `xcode-select --install` (triggers Xcode CLT dialog) |
| Debian/Ubuntu | `sudo apt-get update && sudo apt-get install -y git` |

On macOS, `git` is bundled with Xcode Command Line Tools. The `xcode-select`
command triggers an OS-level install dialog — hermes-fly should wait for
completion before verifying.

On Linux, `apt-get` requires sudo. If sudo is unavailable or fails, fall back
to the manual guide.

**Fallback guide**: Link to https://git-scm.com/downloads

### curl

| Platform | Install method |
|----------|---------------|
| macOS | Pre-installed on all modern macOS (no action needed) |
| Debian/Ubuntu | `sudo apt-get update && sudo apt-get install -y curl` |

curl is essentially always present on macOS. On minimal Linux images (Docker,
Sprites), it may be absent.

**Fallback guide**: Link to https://curl.se/download.html

## Fallback Guide Format

When auto-install fails (or user declines), show diagnostic context before
the manual instructions:

```
  ✗ Could not install: flyctl
    OS detected:    Linux (Debian 12)
    Attempted:      curl -L https://fly.io/install.sh | sh
    Error:          [last line of stderr]

    To install manually:
      curl -L https://fly.io/install.sh | sh

    Or visit: https://fly.io/docs/flyctl/install/

    Re-run 'hermes-fly deploy' after installing.
```

This gives the user:
- What went wrong (diagnostic)
- What to do about it (command)
- Where to learn more (link)
- What to do next (re-run)

## OS Detection

Detect the platform to choose the right install method:

```
OS detection logic:
  uname -s == "Darwin"  → macOS
  uname -s == "Linux"   → check for apt-get
    command -v apt-get   → Debian/Ubuntu (supported)
    no apt-get           → unsupported distro (guide only)
```

This reuses the existing `deploy_check_platform()` output and extends it with
package manager detection. No attempt to support dnf, pacman, zypper, or apk
in the initial implementation — these fall through to the manual guide.

## Integration Points

### Where the new code lives

Create `lib/prereqs.sh` as a new module containing:

- `prereqs_check_and_install()` — main orchestrator (replaces the
  `deploy_check_prerequisites` call in preflight)
- `prereqs_detect_os()` — returns platform + package manager
- `prereqs_install_tool()` — per-tool install dispatch
- `prereqs_show_guide()` — fallback manual instructions

### How it integrates with preflight

The existing preflight flow in `deploy_preflight()` (deploy.sh:124-136)
currently does:

```bash
ui_spinner_update "Checking prerequisites..."
if ! deploy_check_prerequisites 2>/dev/null; then
  ui_spinner_stop 1 "Missing prerequisites"
  return 1
fi
```

This changes to stop the spinner before entering the interactive install flow,
then restart it after:

```
ui_spinner_update "Checking prerequisites..."
if ! deploy_check_prerequisites 2>/dev/null; then
  ui_spinner_stop 1 "Missing prerequisites — attempting to help"
  prereqs_check_and_install || return 1
  # Re-verify after install attempts
  if ! deploy_check_prerequisites 2>/dev/null; then
    ui_error "Still missing prerequisites after install attempts."
    return 1
  fi
  ui_spinner_start "Continuing preflight..."
fi
```

The spinner must stop because auto-install is interactive (prompts, visible
output). The verbose mode path (deploy.sh:105-106) needs the same treatment.

### Entry point changes

Add `source "${SCRIPT_DIR}/lib/prereqs.sh"` to the `hermes-fly` entry point,
after `ui.sh` (prereqs needs UI functions) and before `deploy.sh`.

### Testing

Add `tests/prereqs.bats` with:

- OS detection returns correct platform for Darwin/Linux
- Package manager detection finds apt-get when present
- Install functions are called with correct commands (mocked)
- Fallback guide is shown when install fails
- User declining install triggers guide + exit
- Full prerequisite check passes after successful install (mocked)

Mock strategy: override `apt-get`, `brew`, `curl`, `xcode-select` via PATH
prepend, same pattern as existing `tests/mocks/fly`.

## UX Flow Example

### Happy path (fresh Ubuntu, all missing)

```
hermes-fly deploy

  ✗ Missing prerequisites — attempting to help

  Missing: curl
  Install now? (sudo apt-get install -y curl) [y/N] y
  Installing curl...
  ✓ curl installed

  Missing: git
  Install now? (sudo apt-get install -y git) [y/N] y
  Installing git...
  ✓ git installed

  Missing: flyctl
  Install now? (curl -L https://fly.io/install.sh | sh) [y/N] y
  Installing flyctl...
  ✓ flyctl installed (added ~/.fly/bin to PATH)

  ✓ All prerequisites installed

  [continues to fly CLI check, auth, connectivity...]
```

### Partial failure (no sudo)

```
  Missing: git
  Install now? (sudo apt-get install -y git) [y/N] y
  Installing git...
  ✗ Could not install: git
    OS detected:    Linux (Ubuntu 22.04)
    Attempted:      sudo apt-get install -y git
    Error:          sudo: command not found

    To install manually:
      apt-get install -y git  (as root)

    Or visit: https://git-scm.com/downloads

    Re-run 'hermes-fly deploy' after installing.
```

### User declines

```
  Missing: flyctl
  Install now? (curl -L https://fly.io/install.sh | sh) [y/N] n

    To install flyctl manually:
      curl -L https://fly.io/install.sh | sh

    Or visit: https://fly.io/docs/flyctl/install/

    Re-run 'hermes-fly deploy' after installing.
```

## Scope Boundaries

**In scope:**
- Auto-install for fly, git, curl on macOS and apt-based Linux
- User confirmation before every install
- Diagnostic fallback with manual instructions
- New `lib/prereqs.sh` module + `tests/prereqs.bats`
- Integration with existing preflight flow

**Out of scope:**
- Non-apt Linux distros (Fedora, Arch, Alpine) — fall through to guide
- Upgrading already-installed but outdated tools (handled by existing
  `fly_check_version`)
- Installing Homebrew itself on macOS
- Offline/air-gapped environments
- CI/CD automation (non-interactive mode)

## Open Questions

- Should `prereqs_install_tool` show the full install output (verbose) or
  capture it and only show on failure?
  - **Finding** [HIGH]: CLI best practices recommend minimal output by default with verbose opt-in. The codebase already uses `HERMES_FLY_VERBOSE` to toggle between spinner and step-by-step modes. Standard practice (Homebrew, apt) is to show real-time output for system-modifying installs, but wrapper tools typically capture output and show it only on failure ([CLI Best Practices](https://hackmd.io/@arturtamborski/cli-best-practices)). **Recommendation**: Capture output by default, showing a one-line progress indicator; dump full output on failure. When `HERMES_FLY_VERBOSE=1`, stream output in real-time, consistent with the existing deploy_preflight() pattern.
- After installing flyctl via the install script, should we automatically
  run `fly auth login` as part of the same flow, or let the existing auth
  check in preflight handle it?
  - **Finding** [HIGH]: The codebase already has `fly_check_auth_interactive()` (fly-helpers.sh:81) which runs as a dedicated preflight step (deploy.sh:114-115, 150-163) with an interactive retry loop. CLI auth best practices recommend keeping auth as a distinct step with its own error handling ([WorkOS CLI Auth Guide](https://workos.com/blog/best-practices-for-cli-authentication-a-technical-guide)). **Recommendation**: Let the existing preflight auth check handle it. Do not chain `fly auth login` into the install flow -- separation of concerns keeps each step independently testable and avoids duplicating the retry logic.
- Should there be a `--no-auto-install` flag to skip the install offers and
  fail fast (for scripting/CI use cases)?
  - **Finding** [HIGH]: Industry standard is to provide non-interactive bypass. GitHub CLI uses `GH_PROMPT_DISABLED` env var ([cli/cli#1739](https://github.com/cli/cli/issues/1739)). Vercel CLI supports `--yes`. Best practice is dual: a CLI flag (`--no-auto-install`) plus environment variable detection (`CI=true`). While the plan marks full CI/CD automation as out of scope (line 298), a fail-fast guard is low cost and prevents pipeline hangs. **Recommendation**: Add `--no-auto-install` flag and detect `CI=true` env var. When either is set, skip install prompts and exit with a clear error listing missing tools.

---

## References

- [CLI Best Practices (HackMD)](https://hackmd.io/@arturtamborski/cli-best-practices)
- [WorkOS CLI Authentication Best Practices](https://workos.com/blog/best-practices-for-cli-authentication-a-technical-guide)
- [GitHub CLI non-interactive mode discussion](https://github.com/cli/cli/issues/1739)
- [Vercel CLI non-interactive issue](https://github.com/vercel/vercel/issues/14786)
