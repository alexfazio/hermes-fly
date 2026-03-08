#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC1091
# lib/prereqs.sh — Prerequisite auto-install module
# Handles detection, installation, and fallback guidance for missing prerequisites.
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source dependencies (skip if already loaded) ---
_PREREQS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Guard: only source each dep if not yet defined
if [[ -z "${EXIT_SUCCESS+x}" ]]; then
  # shellcheck source=./ui.sh
  source "${_PREREQS_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi

# ==========================================================================
# Public API
# ==========================================================================

# prereqs_detect_os — detect platform and package manager availability
# Returns: platform string (Darwin:brew, Darwin:no-brew, Linux:apt, etc.)
prereqs_detect_os() {
  local platform="${HERMES_FLY_PLATFORM:-$(uname -s)}"
  case "$platform" in
    Darwin)
      command -v brew >/dev/null 2>&1 && echo "Darwin:brew" || echo "Darwin:no-brew"
      ;;
    Linux)
      command -v apt-get >/dev/null 2>&1 && echo "Linux:apt" || echo "Linux:unsupported"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

# prereqs_show_guide — display fallback manual installation guide
# Args: TOOL OS [ATTEMPTED] [LAST_ERROR]
# No return value; output to stderr
prereqs_show_guide() {
  local tool="$1" os="$2" attempted="${3:-}" last_error="${4:-}"
  local url
  case "$tool" in
    fly) url="https://fly.io/docs/flyctl/install/" ;;
    git) url="https://git-scm.com/downloads" ;;
    curl) url="https://curl.se/download.html" ;;
    *) url="" ;;
  esac

  local manual_cmd
  manual_cmd="$(_prereqs_manual_cmd "$tool" "$os")"

  printf '\n' >&2
  if [[ -n "$attempted" ]]; then
    printf '  \033[31m✗\033[0m Could not install: %s\n' "$tool" >&2
    printf '    OS detected:    %s\n' "$os" >&2
    printf '    Attempted:      %s\n' "$attempted" >&2
    [[ -n "$last_error" ]] && printf '    Error:          %s\n' "$last_error" >&2
    printf '\n' >&2
  fi
  printf '    To install %s manually:\n' "$tool" >&2
  printf '      %s\n' "$manual_cmd" >&2
  [[ -n "$url" ]] && printf '\n    Or visit: %s\n' "$url" >&2
  printf '\n    Re-run '"'"'hermes-fly deploy'"'"' after installing.\n' >&2
}

# ==========================================================================
# Private helpers
# ==========================================================================

# _prereqs_manual_cmd — return the manual install command for a tool/OS
# Returns: command string to stdout
_prereqs_manual_cmd() {
  local tool="$1" os="$2"
  case "$tool:$os" in
    fly:Darwin:brew) echo "brew install flyctl" ;;
    fly:Darwin:no-brew) echo "curl -L https://fly.io/install.sh | sh" ;;
    fly:Linux:apt) echo "curl -L https://fly.io/install.sh | sh" ;;
    git:Darwin:*) echo "xcode-select --install" ;;
    git:Linux:apt) echo "sudo apt-get install -y git" ;;
    curl:Darwin:*) echo "curl is pre-installed on macOS" ;;
    curl:Linux:apt) echo "sudo apt-get install -y curl" ;;
    *) echo "See manual installation guide for ${tool}" ;;
  esac
}

# _prereqs_build_install_cmd — build the install command for a tool/OS
# Returns: command string to stdout, exit 1 if unsupported
_prereqs_build_install_cmd() {
  local tool="$1" os="$2"
  case "$tool:$os" in
    fly:Darwin:brew) echo "brew install flyctl" ;;
    fly:Darwin:no-brew) echo "${HERMES_FLY_FLYCTL_INSTALL_CMD:-curl -L https://fly.io/install.sh | sh}" ;;
    fly:Linux:apt) echo "${HERMES_FLY_FLYCTL_INSTALL_CMD:-curl -L https://fly.io/install.sh | sh}" ;;
    git:Darwin:*) echo "xcode-select --install" ;;
    git:Linux:apt) echo "sudo apt-get update && sudo apt-get install -y git" ;;
    curl:Linux:apt) echo "sudo apt-get update && sudo apt-get install -y curl" ;;
    curl:Darwin:*) return 1 ;;
    *:unsupported) return 1 ;;
    *) return 1 ;;
  esac
}

# ==========================================================================
# Public API (continued)
# ==========================================================================

# prereqs_install_tool — install a single tool on the detected OS
# Args: TOOL OS
# Returns: 0 on success, 1 on failure
prereqs_install_tool() {
  local tool="$1" os="$2"

  # Build install command
  local cmd
  cmd="$(_prereqs_build_install_cmd "$tool" "$os")" || {
    prereqs_show_guide "$tool" "$os" "" "Unsupported platform"
    return 1
  }

  printf '  Installing %s...\n' "$tool" >&2

  if [[ "${HERMES_FLY_VERBOSE:-0}" == "1" ]]; then
    # Stream output directly
    if ! eval "$cmd"; then
      prereqs_show_guide "$tool" "$os" "$cmd" ""
      return 1
    fi
  else
    # Capture output; dump on failure
    local out_file
    out_file="$(mktemp)"
    if ! eval "$cmd" >"$out_file" 2>&1; then
      local last_error
      last_error="$(tail -1 "$out_file")"
      cat "$out_file" >&2
      prereqs_show_guide "$tool" "$os" "$cmd" "$last_error"
      rm -f "$out_file"
      return 1
    fi
    rm -f "$out_file"
  fi

  # flyctl: add ~/.fly/bin to PATH for current session
  if [[ "$tool" == "fly" ]] && [[ -d "${HOME}/.fly/bin" ]]; then
    export PATH="${HOME}/.fly/bin:${PATH}"
    printf '  \033[32m✓\033[0m flyctl installed (added ~/.fly/bin to PATH)\n' >&2
  else
    printf '  \033[32m✓\033[0m %s installed\n' "$tool" >&2
  fi
}

# prereqs_check_and_install — orchestrator: detect missing tools, offer install, verify
# Returns: 0 if all tools available (present or installed), 1 if any failed
prereqs_check_and_install() {
  # CI / non-interactive bypass
  if [[ "${CI:-}" == "true" || "${HERMES_FLY_NO_AUTO_INSTALL:-}" == "1" ]]; then
    local any_missing=false
    local tool
    for tool in fly git curl; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        ui_error "Missing prerequisite: ${tool} (auto-install disabled)"
        any_missing=true
      fi
    done
    [[ "$any_missing" == "false" ]] && return 0 || return 1
  fi

  local os any_failed=false
  os="$(prereqs_detect_os)"

  local tool
  for tool in fly git curl; do
    command -v "$tool" >/dev/null 2>&1 && continue

    printf '\n  Missing: %s\n' "$tool" >&2
    local install_desc
    install_desc="$(_prereqs_build_install_cmd "$tool" "$os" 2>/dev/null || echo "manual install required")"

    if ! ui_confirm "  Install now? (${install_desc})"; then
      prereqs_show_guide "$tool" "$os" "" ""
      any_failed=true
      continue
    fi

    if ! prereqs_install_tool "$tool" "$os"; then
      any_failed=true
    fi
  done

  [[ "$any_failed" == "false" ]] && return 0 || return 1
}
