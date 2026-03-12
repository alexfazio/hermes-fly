#!/usr/bin/env bash
# lib/config.sh — App tracking (~/.hermes-fly/config.yaml)
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Config path ---

_normalize_dir_path() {
  local input="$1"
  local is_absolute=0
  local normalized=""
  local part
  local old_ifs="${IFS}"
  local -a parts=()
  local -a stack=()

  if [[ "${input}" == /* ]]; then
    is_absolute=1
  fi

  IFS='/'
  read -r -a parts <<<"${input}"
  IFS="${old_ifs}"

  for part in "${parts[@]}"; do
    case "${part}" in
      ""|".")
        ;;
      "..")
        if [[ "${#stack[@]}" -gt 0 && "${stack[$((${#stack[@]} - 1))]}" != ".." ]]; then
          local last_index
          last_index=$((${#stack[@]} - 1))
          unset "stack[${last_index}]"
        elif [[ "${is_absolute}" -eq 0 ]]; then
          stack+=("..")
        fi
        ;;
      *)
        stack+=("${part}")
        ;;
    esac
  done

  if [[ "${#stack[@]}" -gt 0 ]]; then
    IFS='/'
    normalized="${stack[*]}"
    IFS="${old_ifs}"
  fi

  if [[ "${is_absolute}" -eq 1 ]]; then
    if [[ -n "${normalized}" ]]; then
      printf '/%s' "${normalized}"
    else
      printf '/'
    fi
  elif [[ -n "${normalized}" ]]; then
    printf '%s' "${normalized}"
  else
    printf '.'
  fi
}

_config_file() {
  if [[ -n "${HERMES_FLY_CONFIG_DIR:-}" ]]; then
    local config_dir="${HERMES_FLY_CONFIG_DIR}"
    config_dir="$(_normalize_dir_path "${config_dir}")"
    if [[ -z "${config_dir}" || "${config_dir}" == "." ]]; then
      echo "config.yaml"
    elif [[ "${config_dir}" == "/" ]]; then
      echo "/config.yaml"
    else
      echo "${config_dir}/config.yaml"
    fi
    return
  fi

  local home="${HOME:-}"
  if [[ -z "${home}" || "${home}" == "/" ]]; then
    echo "/.hermes-fly/config.yaml"
    return
  fi

  echo "${home%/}/.hermes-fly/config.yaml"
}

# --- config_init ---
# Create config dir and empty config file if they don't exist.

config_init() {
  local config_file
  config_file="$(_config_file)"
  local config_dir
  config_dir="$(dirname "$config_file")"

  mkdir -p "$config_dir"
  [[ -f "$config_file" ]] || touch "$config_file"
}

# --- config_save_app ---
# Add or update an app entry in config. Set it as current_app.
# Usage: config_save_app "name" "region"

config_save_app() {
  local name="$1"
  local region="$2"
  local deployed_at
  deployed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  config_init

  local config_file
  config_file="$(_config_file)"

  # Update current_app line
  if grep -q "^current_app:" "$config_file" 2>/dev/null; then
    sed -i.bak "s/^current_app:.*$/current_app: ${name}/" "$config_file"
    rm -f "${config_file}.bak"
  else
    # Insert current_app at top of file
    local tmp
    tmp="$(mktemp)"
    echo "current_app: ${name}" >"$tmp"
    cat "$config_file" >>"$tmp"
    mv "$tmp" "$config_file"
  fi

  # Check if app already exists — remove the old entry first
  if grep -q "^  - name: ${name}$" "$config_file" 2>/dev/null; then
    _remove_app_entry "$name" "$config_file"
  fi

  # Ensure apps: header exists
  if ! grep -q "^apps:$" "$config_file" 2>/dev/null; then
    echo "apps:" >>"$config_file"
  fi

  # Append the new app entry
  cat >>"$config_file" <<EOF
  - name: ${name}
    region: ${region}
    deployed_at: ${deployed_at}
EOF
}

# --- config_get_current_app ---
# Echo the current_app value. Empty string if not set or no config.

config_get_current_app() {
  local config_file
  config_file="$(_config_file)"

  if [[ ! -f "$config_file" ]]; then
    echo ""
    return 0
  fi

  local value
  value="$(grep "^current_app:" "$config_file" 2>/dev/null | head -1 | sed 's/^current_app:[[:space:]]*//')" || true

  # Validate: must contain only safe printable chars (alphanumeric, dot, hyphen, underscore)
  if [[ -n "$value" ]] && [[ "$value" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "$value"
  else
    echo ""
  fi
}

# --- config_list_apps ---
# List all app names, one per line.

config_list_apps() {
  local config_file
  config_file="$(_config_file)"

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  local raw
  raw="$(grep "^  - name:" "$config_file" 2>/dev/null | sed 's/^  - name:[[:space:]]*//')" || true

  # Filter: only output lines with safe characters
  local line
  while IFS= read -r line; do
    if [[ -n "$line" ]] && [[ "$line" =~ ^[a-zA-Z0-9._-]+$ ]]; then
      echo "$line"
    fi
  done <<<"$raw"
}

# --- _remove_app_entry (internal) ---
# Remove a 3-line app block (name, region, deployed_at) from config.

_remove_app_entry() {
  local name="$1"
  local config_file="$2"

  # Use sed to delete the 3-line block: "  - name: X" + next 2 lines
  sed -i.bak "/^  - name: ${name}$/,+2d" "$config_file"
  rm -f "${config_file}.bak"
}

# --- config_remove_app ---
# Remove an app entry. If it was current_app, clear current_app.

config_remove_app() {
  local name="$1"
  local config_file
  config_file="$(_config_file)"

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  # Remove the app entry block
  _remove_app_entry "$name" "$config_file"

  # If this was the current app, clear current_app
  local current
  current="$(config_get_current_app)"
  if [[ "$current" == "$name" ]]; then
    sed -i.bak "s/^current_app:.*$/current_app:/" "$config_file"
    rm -f "${config_file}.bak"
  fi
}

# --- config_resolve_app ---
# Parse args for -a APP_NAME flag. If found, echo that.
# Otherwise, echo current_app. If neither, echo empty + return 1.

config_resolve_app() {
  local app_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a)
        app_name="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -n "$app_name" ]]; then
    echo "$app_name"
    return 0
  fi

  local current
  current="$(config_get_current_app)"
  if [[ -n "$current" ]]; then
    echo "$current"
    return 0
  fi

  echo ""
  return 1
}
