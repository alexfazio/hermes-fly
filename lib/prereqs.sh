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
    # Check for 'fly' binary on PATH
    if command -v fly >/dev/null 2>&1; then
      return 0
    fi

    # Check for 'flyctl' binary on PATH (alternative name)
    if command -v flyctl >/dev/null 2>&1; then
      return 0
    fi

    # Check for direct file paths in ~/.fly/bin (unless in test mode)
    if [[ "${HERMES_FLY_TEST_MODE:-}" != "1" ]]; then
      if [[ -f "${HOME}/.fly/bin/fly" ]] || [[ -f "${HOME}/.fly/bin/flyctl" ]]; then
        # In CI environments, skip PATH export
        if [[ "${CI:-}" != "true" ]]; then
          export PATH="${HOME}/.fly/bin:${PATH}"
        fi
        return 0
      fi
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
  # Check ZSH_VERSION first
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    echo "zsh"
    return 0
  fi

  # Check BASH_VERSION
  if [[ -n "${BASH_VERSION:-}" ]]; then
    echo "bash"
    return 0
  fi

  # Use SHELL environment variable
  if [[ -n "${SHELL:-}" ]]; then
    basename "$SHELL"
    return 0
  fi

  # Fallback to sh
  echo "sh"
}

# _prereqs_get_shell_config — map shell type to config file path
# Args: SHELL_NAME (e.g., "zsh", "bash", "fish")
# Returns: config file path to stdout or exit 1 if unknown shell
_prereqs_get_shell_config() {
  local shell="$1"

  case "$shell" in
    zsh)
      # shellcheck disable=SC2088
      echo "~/.zshrc"
      return 0
      ;;
    bash)
      # shellcheck disable=SC2088
      echo "~/.bashrc"
      return 0
      ;;
    fish)
      # shellcheck disable=SC2088
      echo "~/.config/fish/config.fish"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# _prereqs_reload_shell_config — source shell config file in current session
# No arguments
# Returns: 0 on success, 1 on failure (config not found, unknown shell, etc.)
# Effect: Makes PATH updates from external installers active in current process
_prereqs_reload_shell_config() {
  local shell config_file

  # Detect current shell
  shell="$(_prereqs_detect_shell)" || return 1

  # Get shell config file path
  config_file="$(_prereqs_get_shell_config "$shell")" || return 1

  # Expand ~ to $HOME
  config_file="${config_file/#\~/$HOME}"

  # Check if config file exists
  [[ -f "$config_file" ]] || return 1

  # Source the config file; suppress errors from malformed configs
  # shellcheck source=/dev/null
  source "$config_file" 2>/dev/null
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
      printf '  \033[31m✗\033[0m Installation completed but binary not accessible. Restart terminal or run: source ~/.zshrc\n' >&2
      return 1
    fi
  fi

  # flyctl: add ~/.fly/bin to PATH for current session
  if [[ "$tool" == "fly" ]] && [[ -d "${HOME}/.fly/bin" ]]; then
    export PATH="${HOME}/.fly/bin:${PATH}"
    printf '  \033[32m✓\033[0m flyctl installed and ready\n' >&2

    # Attempt to reload shell config to make PATH updates active
    # Don't fail the install if reload fails (PATH export already active)
    _prereqs_reload_shell_config >/dev/null 2>&1 || true
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
