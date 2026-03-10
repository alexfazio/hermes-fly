#!/usr/bin/env bash
# lib/ui.sh — Shared UI helpers (colors, prompts, spinners, logging)
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Exit code constants ---
readonly EXIT_SUCCESS=0 EXIT_ERROR=1 EXIT_AUTH=2 EXIT_NETWORK=3 EXIT_RESOURCE=4
export EXIT_SUCCESS EXIT_ERROR EXIT_AUTH EXIT_NETWORK EXIT_RESOURCE

# --- Color support ---

ui_color_enabled() {
  [[ "${NO_COLOR:-}" == "1" ]] && return 1
  [[ -t 1 ]] && return 0
  return 1
}

# --- Internal: wrap message with optional color ---
# Usage: _ui_colorize COLOR_CODE "message"
_ui_colorize() {
  local code="$1" msg="$2"
  if ui_color_enabled; then
    printf '\033[%sm%s\033[0m\n' "$code" "$msg"
  else
    printf '%s\n' "$msg"
  fi
}

# --- Output functions ---

ui_info() {
  local msg="$1"
  if ui_color_enabled; then
    printf '\033[34m[info] %s\033[0m\n' "$msg" >&2
  else
    printf '[info] %s\n' "$msg" >&2
  fi
}

ui_success() {
  local msg="$1"
  if ui_color_enabled; then
    printf '\033[32m✓ %s\033[0m\n' "$msg" >&2
  else
    printf '✓ %s\n' "$msg" >&2
  fi
}

ui_warn() {
  local msg="$1"
  if ui_color_enabled; then
    printf '\033[33m[warn] %s\033[0m\n' "$msg" >&2
  else
    printf '[warn] %s\n' "$msg" >&2
  fi
}

ui_error() {
  local msg="$1"
  if ui_color_enabled; then
    printf '\033[31m[error] %s\033[0m\n' "$msg" >&2
  else
    printf '[error] %s\n' "$msg" >&2
  fi
}

ui_step() {
  local n="$1" total="$2" msg="$3"
  if ui_color_enabled; then
    printf '\033[36m[%s/%s]\033[0m %s...\n' "$n" "$total" "$msg"
  else
    printf '[%s/%s] %s...\n' "$n" "$total" "$msg"
  fi
}

# --- Prompts ---

ui_ask() {
  local prompt="$1" varname="$2"
  printf '%s ' "$prompt" >&2
  IFS= read -r "${varname?}"
}

ui_ask_secret() {
  local prompt="$1" varname="$2"
  printf '%s ' "$prompt" >&2
  IFS= read -rs "${varname?}"
  printf '\n' >&2
}

ui_confirm() {
  local prompt="$1" answer
  printf '%s [y/N] ' "$prompt" >&2
  IFS= read -r answer
  answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
  case "$answer" in
    y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

ui_select() {
  local prompt="$1" varname="$2"
  shift 2
  local options=("$@")
  local i

  printf '%s\n' "$prompt" >&2
  for i in "${!options[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${options[$i]}" >&2
  done
  printf 'Choice: ' >&2

  local choice
  IFS= read -r choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
    eval "$varname=\"\${options[$((choice - 1))]}\""
  else
    eval "$varname=''"
    return 1
  fi
}

# --- Banner ---

ui_banner() {
  local title="$1"
  local width=$((${#title} + 4))
  local border
  border=$(printf '═%.0s' $(seq 1 "$width"))
  printf '╔%s╗\n' "$border"
  printf '║  %s  ║\n' "$title"
  printf '╚%s╝\n' "$border"
}

# --- Spinner ---
# Animated braille spinner for non-verbose progress display.
# Gracefully degrades to static text on non-interactive terminals.

_UI_SPINNER_PID=""
_UI_SPINNER_MSG_FILE=""

ui_spinner_start() {
  local msg="$1"
  _UI_SPINNER_MSG_FILE="$(mktemp "${TMPDIR:-/tmp}/hermes-spin.XXXXXX")"
  printf '%s' "$msg" >"$_UI_SPINNER_MSG_FILE"
  _UI_SPINNER_PID=""

  # Only animate on color-enabled interactive stderr
  if ui_color_enabled && [[ -t 2 ]]; then
    (
      trap 'exit 0' TERM HUP
      local _f=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
      local _i=0 _m
      while true; do
        _m="$(cat "$_UI_SPINNER_MSG_FILE" 2>/dev/null)" || break
        printf '\r\033[K  \033[36m%s\033[0m %s' "${_f[$_i]}" "$_m" >&2
        _i=$(((_i + 1) % 10))
        sleep 0.08
      done
    ) &
    _UI_SPINNER_PID=$!
    disown "$_UI_SPINNER_PID" 2>/dev/null || true
  fi
}

ui_spinner_update() {
  if [[ -n "${_UI_SPINNER_MSG_FILE:-}" ]]; then
    printf '%s' "$1" >"$_UI_SPINNER_MSG_FILE" 2>/dev/null || true
  fi
}

ui_spinner_stop() {
  local rc="$1" msg="$2"
  if [[ -n "${_UI_SPINNER_PID:-}" ]]; then
    kill "$_UI_SPINNER_PID" 2>/dev/null || true
    wait "$_UI_SPINNER_PID" 2>/dev/null || true
    _UI_SPINNER_PID=""
  fi
  rm -f "${_UI_SPINNER_MSG_FILE:-}" 2>/dev/null || true
  _UI_SPINNER_MSG_FILE=""

  if [[ "$rc" -eq 0 ]]; then
    if ui_color_enabled && [[ -t 2 ]]; then
      printf '\r\033[K  \033[32m✓\033[0m %s\n' "$msg" >&2
    else
      printf '✓ %s\n' "$msg" >&2
    fi
  else
    if ui_color_enabled && [[ -t 2 ]]; then
      printf '\r\033[K  \033[31m✗\033[0m %s\n' "$msg" >&2
    else
      printf '✗ %s\n' "$msg" >&2
    fi
  fi
}

# --- Logging ---

_log_file() {
  printf '%s/hermes-fly.log' "${HERMES_FLY_LOG_DIR:-.}"
}

log_init() {
  local log_dir="${HERMES_FLY_LOG_DIR:-.}"
  mkdir -p "$log_dir"
  touch "$log_dir/hermes-fly.log"
}

log_info() {
  local msg="$1"
  printf '%s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >>"$(_log_file)"
}

log_error() {
  local msg="$1"
  printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >>"$(_log_file)"
}
