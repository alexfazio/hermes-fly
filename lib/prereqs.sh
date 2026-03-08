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

# _prereqs_check_tool_available — check if a tool is available via multiple detection methods
# Args: TOOL (e.g., "fly", "git", "curl")
# Returns: 0 if found, 1 if not found
# For fly tool: checks command -v fly, command -v flyctl, ~/.fly/bin/fly, ~/.fly/bin/flyctl
# When file found and not in CI, exports PATH to make tool available in current process
# For other tools: standard command -v check
# Note: set HERMES_FLY_TEST_MODE=1 to skip file path checks (for tests with controlled PATH)
_prereqs_check_tool_available() {
  local tool="$1"

  # Special handling for fly tool: check multiple binary names and locations
  if [[ "$tool" == "fly" ]]; then
    local original_path="${PATH}"
    local path_mutated=false

    # Check for 'fly' binary on PATH
    if command -v fly >/dev/null 2>&1 && fly version >/dev/null 2>&1; then
      return 0
    fi

    # Check for 'flyctl' binary on PATH — add its directory to expose sibling 'fly'
    if command -v flyctl >/dev/null 2>&1; then
      local flyctl_dir
      flyctl_dir="$(dirname "$(command -v flyctl)")"
      if [[ ":${PATH}:" != *":${flyctl_dir}:"* ]]; then
        export PATH="${flyctl_dir}:${PATH}"
        path_mutated=true
      fi
      # Verify 'fly' is now accessible (flyctl alone is not enough)
      if command -v fly >/dev/null 2>&1 && fly version >/dev/null 2>&1; then
        return 0
      fi
    fi

    # Check for direct file paths in ~/.fly/bin (unless in test mode)
    if [[ "${HERMES_FLY_TEST_MODE:-}" != "1" ]]; then
      if [[ -x "${HOME}/.fly/bin/fly" ]]; then
        # In CI environments, skip PATH export
        if [[ "${CI:-}" != "true" ]] && [[ ":${PATH}:" != *":${HOME}/.fly/bin:"* ]]; then
          export PATH="${HOME}/.fly/bin:${PATH}"
          path_mutated=true
        fi
        # Verify fly is actually callable, not just discoverable
        if command -v fly >/dev/null 2>&1 && fly version >/dev/null 2>&1; then
          return 0
        fi
      fi
    fi

    # On failure, restore PATH to avoid side effects in later prerequisite checks.
    if [[ "$path_mutated" == "true" ]]; then
      export PATH="${original_path}"
    fi

    # Not found
    return 1
  fi

  # Standard check for other tools (git, curl, etc.)
  command -v "$tool" >/dev/null 2>&1
}

# _prereqs_detect_shell — detect current shell type
# No arguments
# Returns: shell name to stdout (zsh, bash, fish, sh)
_prereqs_detect_shell() {
  # SHELL env var reflects user's login shell, not the script interpreter
  if [[ -n "${SHELL:-}" ]]; then
    basename "$SHELL"
    return 0
  fi

  # Fallback: check version variables (only when SHELL is unset)
  if [[ -n "${ZSH_VERSION:-}" ]]; then echo "zsh"; return 0; fi
  if [[ -n "${BASH_VERSION:-}" ]]; then echo "bash"; return 0; fi

  echo "sh"
}

# _prereqs_get_shell_config — map shell type to config file path
# Args: SHELL_NAME (e.g., "zsh", "bash", "fish")
# Returns: config file path to stdout or exit 1 if unknown shell
_prereqs_get_shell_config() {
  local shell="$1"

  case "$shell" in
    zsh)  echo "${HOME}/.zshrc"; return 0 ;;
    bash) echo "${HOME}/.bashrc"; return 0 ;;
    fish) echo "${HOME}/.config/fish/config.fish"; return 0 ;;
    *)    return 1 ;;
  esac
}

# _prereqs_reload_shell_config — utility: source PATH exports from shell config
# No arguments
# Returns: 0 on success, 1 on failure (config not found, unknown shell, etc.)
# Effect: Makes PATH updates from external installers active in current process
#
# NOTE: This utility is not called by the active install flow. The
# _prereqs_check_tool_available() fallback handles PATH updates in-process.
# This function is available for future use if a caller needs explicit config reload.
_prereqs_reload_shell_config() {
  local shell config_file

  # Detect current shell
  shell="$(_prereqs_detect_shell)" || return 1

  # Get shell config file path
  config_file="$(_prereqs_get_shell_config "$shell")" || return 1

  # Check if config file exists
  [[ -f "$config_file" ]] || return 1
  [[ -r "$config_file" ]] || return 1

  # Safely apply only explicit PATH exports — avoids side effects from full config sourcing.
  # grep -E anchors to '^export PATH=' so only PATH-setting lines are eval'd, preventing
  # arbitrary code execution. The user's own config file is the trust boundary.
  local path_lines grep_rc=0
  path_lines="$(grep -E '^export PATH=' "$config_file" 2>/dev/null)" || grep_rc=$?
  if [[ "$grep_rc" -ne 0 ]] && [[ "$grep_rc" -ne 1 ]]; then
    return 1
  fi

  local path_line
  if [[ "$grep_rc" -eq 0 ]]; then
    while IFS= read -r path_line; do
      eval "$path_line" 2>/dev/null || true
    done <<< "$path_lines"
  fi

  return 0
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

  # Post-install verification: verify tool is actually accessible
  if [[ "$tool" == "fly" ]]; then
    if ! _prereqs_check_tool_available "fly" >/dev/null 2>&1; then
      local shell_config_hint="restart your terminal"
      local _fail_shell _fail_config
      _fail_shell="$(_prereqs_detect_shell 2>/dev/null)"
      if _fail_config="$(_prereqs_get_shell_config "$_fail_shell" 2>/dev/null)"; then
        shell_config_hint="source ${_fail_config}"
      fi
      printf '  \033[31m✗\033[0m Installation completed but binary not accessible. Restart terminal or run: %s\n' \
        "${shell_config_hint}" >&2
      return 1
    fi
  fi

  # flyctl: add ~/.fly/bin to PATH for current session (with dedup guard)
  if [[ "$tool" == "fly" ]] && [[ -d "${HOME}/.fly/bin" ]]; then
    if [[ ":${PATH}:" != *":${HOME}/.fly/bin:"* ]]; then
      export PATH="${HOME}/.fly/bin:${PATH}"
    fi
    printf '  \033[32m✓\033[0m flyctl installed and ready\n' >&2
  else
    printf '  \033[32m✓\033[0m %s installed\n' "$tool" >&2
  fi

  return 0
}

# prereqs_check_and_install — orchestrator: detect missing tools, offer install, verify
# Returns: 0 if all tools available (present or installed), 1 if any failed
prereqs_check_and_install() {
  # CI / non-interactive bypass
  if [[ "${CI:-}" == "true" || "${HERMES_FLY_NO_AUTO_INSTALL:-}" == "1" ]]; then
    local any_missing=false
    local tool
    for tool in fly git curl; do
      if ! _prereqs_check_tool_available "$tool" >/dev/null 2>&1; then
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
    _prereqs_check_tool_available "$tool" >/dev/null 2>&1 && continue

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
