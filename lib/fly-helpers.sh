#!/usr/bin/env bash
# lib/fly-helpers.sh — Fly.io CLI wrappers + retry logic
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# Source ui.sh for exit code constants (if not already loaded)
if [[ -z "${EXIT_AUTH:-}" ]]; then
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh" 2>/dev/null || true
fi

# Fallback exit code constants (in case ui.sh doesn't define them yet)
: "${EXIT_SUCCESS:=0}" "${EXIT_ERROR:=1}" "${EXIT_AUTH:=2}" "${EXIT_NETWORK:=3}" "${EXIT_RESOURCE:=4}"

# --------------------------------------------------------------------------
# fly_check_installed — verify the fly CLI is available
# Checks: callable "fly" command.
# Returns: 0 if found, 1 + error message if not
# Side effects: in fallback mode, temporarily prepends flyctl dir to PATH while probing.
# --------------------------------------------------------------------------
fly_check_installed() {
  # Delegate to prereqs helper if available (handles ~/.fly/bin, flyctl symlink, etc.)
  if declare -f _prereqs_check_tool_available >/dev/null 2>&1; then
    if _prereqs_check_tool_available "fly"; then
      return 0
    fi
    echo "Error: fly CLI not found. Install from https://fly.io/docs/flyctl/install/" >&2
    return 1
  fi

  # Fallback: direct command checks when prereqs.sh not sourced
  if command -v fly >/dev/null 2>&1 && fly version >/dev/null 2>&1; then
    return 0
  fi

  local original_path="${PATH}"
  local path_mutated=false

  # Check for 'flyctl' and expose sibling 'fly' symlink if present
  if command -v flyctl >/dev/null 2>&1; then
    local flyctl_dir
    flyctl_dir="$(dirname "$(command -v flyctl)")"
    if [[ ":${PATH}:" != *":${flyctl_dir}:"* ]]; then
      export PATH="${flyctl_dir}:${PATH}"
      path_mutated=true
    fi
    # Verify 'fly' is now callable
    if command -v fly >/dev/null 2>&1 && fly version >/dev/null 2>&1; then
      return 0
    fi
  fi

  if [[ "$path_mutated" == "true" ]]; then
    export PATH="${original_path}"
  fi

  echo "Error: fly CLI not found. Install from https://fly.io/docs/flyctl/install/" >&2
  return 1
}

# --------------------------------------------------------------------------
# fly_check_version — verify fly CLI version >= 0.2.0
# Returns: 0 if version is sufficient, 1 if too old
# --------------------------------------------------------------------------
fly_check_version() {
  local version_output
  version_output="$(fly version 2>&1)"

  # Parse version: "fly vX.Y.Z ..." -> X.Y.Z
  local version
  version="$(echo "$version_output" | sed -n 's/.*v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"

  if [[ -z "$version" ]]; then
    echo "Error: could not parse fly version from: $version_output" >&2
    return 1
  fi

  local major minor
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"

  # Require >= 0.2.0: major > 0, or (major == 0 and minor >= 2)
  if ((major > 0)) || ((major == 0 && minor >= 2)); then
    return 0
  else
    echo "Error: fly version $version is too old (need >= 0.2.0)" >&2
    return 1
  fi
}

# --------------------------------------------------------------------------
# fly_check_auth — verify the user is authenticated with fly
# Returns: 0 on success, EXIT_AUTH (2) on failure
# --------------------------------------------------------------------------
fly_check_auth() {
  if fly auth whoami >/dev/null 2>&1; then
    return 0
  else
    echo "Error: not authenticated with Fly.io. Run 'fly auth login' first." >&2
    return "$EXIT_AUTH"
  fi
}

# --------------------------------------------------------------------------
# fly_check_auth_interactive — check auth with one retry opportunity
# On first failure: prompts user to run 'fly auth login', waits for Enter,
# retries once. If still fails, returns EXIT_AUTH.
# --------------------------------------------------------------------------
fly_check_auth_interactive() {
  if fly_check_auth 2>/dev/null; then
    return 0
  fi

  echo "Not authenticated with Fly.io. Please run 'fly auth login' in another terminal." >&2
  printf "Press Enter when ready to retry... " >&2
  IFS= read -r -t 60 _ || true

  if fly_check_auth 2>/dev/null; then
    return 0
  fi

  echo "Error: still not authenticated with Fly.io." >&2
  return "$EXIT_AUTH"
}

# --------------------------------------------------------------------------
# fly_create_app "name" — create a new Fly app
# Echoes JSON output from fly apps create
# --------------------------------------------------------------------------
fly_create_app() {
  local name="$1"
  local org="${2:-}"
  if [[ -n "$org" ]]; then
    fly apps create "$name" --org "$org" --json
  else
    fly apps create "$name" --json
  fi
}

# --------------------------------------------------------------------------
# fly_destroy_app "name" — destroy a Fly app
# --------------------------------------------------------------------------
fly_destroy_app() {
  local name="$1"
  fly apps destroy "$name" --yes
}

# --------------------------------------------------------------------------
# fly_create_volume "app" "name" "size" "region"
# --------------------------------------------------------------------------
fly_create_volume() {
  local app="$1" name="$2" size="$3" region="$4"
  fly volumes create "$name" --app "$app" --size "$size" --region "$region" --json --yes
}

# --------------------------------------------------------------------------
# fly_list_volumes "app" — list volumes for an app as JSON
# --------------------------------------------------------------------------
fly_list_volumes() {
  local app="$1"
  fly volumes list --app "$app" --json
}

# --------------------------------------------------------------------------
# fly_delete_volume "id" — delete a volume by ID
# --------------------------------------------------------------------------
fly_delete_volume() {
  local id="$1"
  fly volumes delete "$id" --yes
}

# --------------------------------------------------------------------------
# fly_set_secrets "app" KEY=VAL... — set secrets on an app
# --------------------------------------------------------------------------
fly_set_secrets() {
  local app="$1"
  shift
  fly secrets set "$@" --app "$app"
}

# --------------------------------------------------------------------------
# fly_deploy "app" "dir" [timeout] — deploy an app from a directory
# Optional third argument sets --wait-timeout (default: 5m0s).
# --------------------------------------------------------------------------
fly_deploy() {
  local app="$1" dir="$2" timeout="${3:-5m0s}"
  (cd "$dir" && fly deploy --app "$app" --wait-timeout "$timeout")
}

# --------------------------------------------------------------------------
# fly_status "app" — get app status as JSON
# --------------------------------------------------------------------------
fly_status() {
  local app="$1"
  fly status --app "$app" --json
}

# --------------------------------------------------------------------------
# fly_logs "app" [extra_args...] — stream/fetch app logs
# --------------------------------------------------------------------------
fly_logs() {
  local app="$1"
  shift
  fly logs --app "$app" "$@"
}

# --------------------------------------------------------------------------
# fly_get_regions — list available Fly.io regions as JSON
# --------------------------------------------------------------------------
fly_get_regions() {
  fly platform regions --json
}

# --------------------------------------------------------------------------
# fly_get_vm_sizes — list available VM sizes as JSON
# --------------------------------------------------------------------------
fly_get_vm_sizes() {
  fly platform vm-sizes --json
}

# --------------------------------------------------------------------------
# fly_get_orgs — list Fly.io organizations as JSON
# --------------------------------------------------------------------------
fly_get_orgs() {
  fly orgs list --json
}

# --------------------------------------------------------------------------
# fly_get_machine_state "app" — get the machine state (started, stopped, etc.)
# --------------------------------------------------------------------------
fly_get_machine_state() {
  local app_name="$1"
  local json
  json="$(fly_status "$app_name" 2>/dev/null)" || {
    printf 'unknown'
    return 1
  }
  printf '%s' "$json" | tr -d '\n' \
    | grep -oE '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | sed 's/.*"state"[[:space:]]*:[[:space:]]*"//;s/"//'
}

# --------------------------------------------------------------------------
# fly_retry "max_attempts" CMD... — retry a command with exponential backoff
# Set HERMES_FLY_RETRY_SLEEP=0 to disable sleep (for tests)
# --------------------------------------------------------------------------
fly_retry() {
  local max_attempts="$1"
  shift
  local attempt=1
  local sleep_time=1

  while ((attempt <= max_attempts)); do
    if "$@"; then
      return 0
    fi

    if ((attempt == max_attempts)); then
      echo "Error: command failed after $max_attempts attempts: $*" >&2
      return 1
    fi

    if [[ "${HERMES_FLY_RETRY_SLEEP:-1}" != "0" ]]; then
      sleep "$sleep_time"
    fi

    ((sleep_time *= 2))
    ((attempt++))
  done
}
