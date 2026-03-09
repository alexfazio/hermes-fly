#!/usr/bin/env bash
# lib/status.sh — Status command
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source dependencies (with fallback) ---
_STATUS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${EXIT_AUTH:-}" ]]; then
  # shellcheck source=/dev/null
  source "${_STATUS_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi
if ! command -v fly_status &>/dev/null; then
  # shellcheck source=/dev/null
  source "${_STATUS_SCRIPT_DIR}/fly-helpers.sh" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# status_estimate_cost "vm_size" "volume_gb" — estimate monthly cost
# Echoes formatted string like "~$X.XX/mo"
# --------------------------------------------------------------------------
status_estimate_cost() {
  local vm_size="$1" volume_gb="$2"
  local base_cost=0

  case "$vm_size" in
    shared-cpu-1x) base_cost=202 ;;     # $2.02 in cents
    shared-cpu-2x) base_cost=404 ;;     # $4.04 in cents
    performance-1x) base_cost=3219 ;;   # $32.19 in cents
    performance-2x) base_cost=6439 ;;   # $64.39 in cents
    dedicated-cpu-1x) base_cost=2300 ;; # $23.00 in cents (legacy tier, not in current Fly.io pricing)
    *)
      echo "Unknown VM size: $vm_size" >&2
      return 1
      ;;
  esac

  # Volume cost: $0.15/GB/month = 15 cents/GB
  local volume_cost=$((volume_gb * 15))
  local total_cents=$((base_cost + volume_cost))

  # Format as dollars with two decimal places
  local dollars=$((total_cents / 100))
  local cents=$((total_cents % 100))
  printf '~$%d.%02d/mo\n' "$dollars" "$cents"
}

# --------------------------------------------------------------------------
# cmd_status "app_name" — display formatted app status
# --------------------------------------------------------------------------
cmd_status() {
  local app_name="$1"
  local status_json

  # Get status JSON from fly
  if ! status_json="$(fly_status "$app_name" 2>&1)"; then
    ui_error "Failed to get status for app '${app_name}': ${status_json}"
    return 1
  fi

  # Parse JSON fields with grep/sed (no jq dependency)
  local app_status hostname machine_state region

  # Extract app name from JSON: "name":"value"
  local parsed_name
  parsed_name="$(echo "$status_json" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  # Extract app status: "status":"value"
  app_status="$(echo "$status_json" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  # Extract hostname: "hostname":"value"
  hostname="$(echo "$status_json" | sed -n 's/.*"hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  # Extract machine state: "state":"value"
  machine_state="$(echo "$status_json" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  # Extract region from machines: "region":"value"
  region="$(echo "$status_json" | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  # Display formatted output
  ui_info "App:     ${parsed_name:-$app_name}"
  ui_info "Status:  ${app_status:-unknown}"
  ui_info "Machine: ${machine_state:-unknown}"
  ui_info "Region:  ${region:-unknown}"
  if [[ -n "$hostname" ]]; then
    ui_success "URL:     https://${hostname}"
  fi
}
