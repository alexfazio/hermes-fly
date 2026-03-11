#!/usr/bin/env bash
# lib/doctor.sh — Diagnostics
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source dependencies ---

_DOCTOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${EXIT_AUTH:-}" ]]; then
  # shellcheck disable=SC1091
  source "${_DOCTOR_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi
if ! command -v fly_status &>/dev/null; then
  # shellcheck disable=SC1091
  source "${_DOCTOR_SCRIPT_DIR}/fly-helpers.sh" 2>/dev/null || true
fi

# Canonical hermes agent refs for drift validation.
# MUST stay in sync with HERMES_AGENT_DEFAULT_REF / HERMES_AGENT_PREVIEW_REF in deploy.sh.
# I1: intentionally not readonly — consistent with other module-level constants in this project.
_DOCTOR_HERMES_AGENT_STABLE_REF="8eefbef91cd715cfe410bba8c13cfab4eb3040df"
_DOCTOR_HERMES_AGENT_PREVIEW_REF="${_DOCTOR_HERMES_AGENT_STABLE_REF}"

# Extract a scalar value from YAML "field: value" text.
# CONTRACT: always returns 0; emits empty string on no-match.
# Using || true ensures pipelines are safe under set -euo pipefail.
_doctor_extract_yaml_field() {
  local _field="$1" _text="$2"
  printf '%s' "$_text" \
    | grep -E "^${_field}:[[:space:]]*" \
    | sed "s/^${_field}:[[:space:]]*//" \
    | head -1 \
    || true
  return 0
}

# Extract a quoted string value from JSON {"field": "value"} text.
# CONTRACT: always returns 0; emits empty string on no-match.
# Using || true ensures pipelines are safe under set -euo pipefail.
_doctor_extract_json_field() {
  local _field="$1" _text="$2"
  printf '%s' "$_text" \
    | grep -oE "\"${_field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | sed "s/.*\"${_field}\"[[:space:]]*:[[:space:]]*\"//;s/\"//" \
    | head -1 \
    || true
  return 0
}

# Resolve supported compatibility policy versions from the bundled snapshot.
# Returns newline-separated list of supported versions (e.g. "1.0.0").
# Sources data/reasoning-snapshot.json relative to the lib/ directory.
# CONTRACT: always returns 0; emits empty output when unavailable/unparseable.
_doctor_supported_compat_versions() {
  local _snapshot="${_DOCTOR_SCRIPT_DIR}/../data/reasoning-snapshot.json"
  if [[ ! -f "$_snapshot" ]]; then
    return 0  # empty output — missing snapshot handled explicitly by caller
  fi
  # Each pipeline step uses || true so no step can cause a non-zero exit
  # under set -euo pipefail when there are no matches.
  grep -oE '"policy_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$_snapshot" 2>/dev/null \
    | sed 's/.*"policy_version"[[:space:]]*:[[:space:]]*"//;s/"//' 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' 2>/dev/null \
    || true
  return 0
}

# --------------------------------------------------------------------------
# doctor_report "check_name" "pass|fail" "message"
# Format and print a single check result.
# PASS -> stdout (green), FAIL -> stderr (red)
# --------------------------------------------------------------------------
doctor_report() {
  local check_name="$1" result="$2" message="$3"
  case "$result" in
    pass)
      printf '[PASS] %s: %s\n' "$check_name" "$message"
      ;;
    fail)
      printf '[FAIL] %s: %s\n' "$check_name" "$message" >&2
      ;;
  esac
}

# --------------------------------------------------------------------------
# doctor_check_app_exists "app_name"
# Run fly_status; return 0 if succeeds, 1 if not.
# --------------------------------------------------------------------------
doctor_check_app_exists() {
  local app_name="$1"
  if fly_status "$app_name" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# --------------------------------------------------------------------------
# doctor_check_machine_running "status_json"
# Parse JSON for machine state. Return 0 if "started" or "running", 1 otherwise.
# --------------------------------------------------------------------------
doctor_check_machine_running() {
  local status_json="$1"
  local state
  # Extract machine state from the JSON
  # Handles: .machines[0].state
  if command -v jq &>/dev/null; then
    state="$(printf '%s' "$status_json" | jq -r '.machines[0].state // empty' 2>/dev/null)"
  else
    # Fallback: grep-based extraction (collapse newlines, tolerate spaces around colon)
    state="$(printf '%s' "$status_json" | tr -d '\n' | grep -oE '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"state"[[:space:]]*:[[:space:]]*"//;s/"//')"
  fi
  case "$state" in
    started | running) return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------
# doctor_check_hermes_process "status_json"
# Check if fly_status JSON has a machine with "process":"hermes".
# --------------------------------------------------------------------------
doctor_check_hermes_process() {
  local status_json="$1"
  if printf '%s' "$status_json" | grep -qE '"process"[^}]*"hermes"'; then
    return 0
  fi
  return 1
}

# --------------------------------------------------------------------------
# doctor_check_volume_mounted "app_name"
# Run fly_list_volumes; return 0 if non-empty array, 1 if empty.
# --------------------------------------------------------------------------
doctor_check_volume_mounted() {
  local app_name="$1"
  local volumes_json
  volumes_json="$(fly_list_volumes "$app_name" 2>/dev/null)" || return 1
  # Check if it's an empty JSON array
  if [[ "$volumes_json" == "[]" ]]; then
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------
# doctor_check_secrets_set "secrets_json"
# Check if secrets JSON contains a recognized LLM API key.
# Supports OPENROUTER_API_KEY, NOUS_API_KEY, and LLM_API_KEY.
# --------------------------------------------------------------------------
doctor_check_secrets_set() {
  local secrets_json="$1"
  if [[ -z "$secrets_json" ]]; then
    return 1
  fi
  if printf '%s' "$secrets_json" | grep -qE \
    'OPENROUTER_API_KEY|NOUS_API_KEY|LLM_API_KEY'; then
    return 0
  fi
  return 1
}

# --------------------------------------------------------------------------
# doctor_check_gateway_health "app_name"
# For Telegram polling bots: validates via getMe (HTTP probe gives false negatives).
# For other apps: falls back to HTTP probe of the public URL.
# --------------------------------------------------------------------------
doctor_check_gateway_health() {
  local app_name="$1"
  # Detect Telegram deployment: check secrets list for TELEGRAM_BOT_TOKEN
  local secrets_list
  secrets_list="$(fly secrets list --app "$app_name" 2>/dev/null || printf '')"
  if printf '%s' "$secrets_list" | grep -q "TELEGRAM_BOT_TOKEN"; then
    # For Telegram polling bots: use getMe via fly ssh console (token in machine env)
    # shellcheck disable=SC2016
    local _getme_cmd='curl -sf --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" >/dev/null 2>&1'
    if fly ssh console --app "$app_name" -C "$_getme_cmd" 2>/dev/null; then
      return 0
    fi
    return 1
  fi
  # Fallback: HTTP probe for webhook or other deploys
  local url="https://${app_name}.fly.dev"
  if curl -sf --max-time 10 "$url" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# --------------------------------------------------------------------------
# doctor_check_api_connectivity [secrets_json]
# Check connectivity to LLM API endpoint. Detects provider from secrets.
# --------------------------------------------------------------------------
doctor_check_api_connectivity() {
  local secrets_json="${1:-}"
  if [[ -n "$secrets_json" ]] \
    && printf '%s' "$secrets_json" | grep -q 'NOUS_API_KEY'; then
    curl -sf --max-time 5 "https://portal.nousresearch.com" \
      >/dev/null 2>&1
  elif [[ -n "$secrets_json" ]] \
    && printf '%s' "$secrets_json" | grep -q 'LLM_API_KEY'; then
    return 0
  else
    curl -sf --max-time 5 "https://openrouter.ai/api/v1/models" \
      >/dev/null 2>&1
  fi
}

# --------------------------------------------------------------------------
# doctor_load_deploy_summary "app_name"
# Read the local deploy summary YAML for app_name from the deploys directory.
# Returns: file content to stdout, empty string if not found.
# --------------------------------------------------------------------------
doctor_load_deploy_summary() {
  local app_name="$1"
  local deploys_dir="${HERMES_FLY_CONFIG_DIR:-$HOME/.hermes-fly}/deploys"
  local summary_file="${deploys_dir}/${app_name}.yaml"
  if [[ -f "$summary_file" ]]; then
    cat "$summary_file"
  else
    printf ''
  fi
  return 0
}

# --------------------------------------------------------------------------
# doctor_read_runtime_manifest "app_name"
# Read /root/.hermes/deploy-manifest.json from the running container via SSH.
# Returns JSON to stdout; empty string if unavailable (SSH down, etc.).
# --------------------------------------------------------------------------
doctor_read_runtime_manifest() {
  local app_name="$1"
  fly ssh console --app "$app_name" \
    -C "cat /root/.hermes/deploy-manifest.json 2>/dev/null" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# doctor_check_drift "app_name" "secrets_json"
# Detect deployment provenance drift:
#   1. Verifies HERMES_AGENT_REF and HERMES_DEPLOY_CHANNEL are present in
#      Fly secrets (provenance tracking enabled).
#   2. Local deploy summary must exist — absence is a provenance gap.
#   3. Validates deploy_channel shape in local summary.
#   4. If runtime manifest is readable via SSH, compares deploy_channel and
#      hermes_agent_ref values against the local summary.
# Returns: 0 if no drift detected, 1 if provenance missing or drift found.
# --------------------------------------------------------------------------
doctor_check_drift() {
  local app_name="$1"
  local secrets_json="${2:-}"
  # Reset tri-state side-channel. Set to 1 when provenance is unverified
  # (preview/edge with unavailable runtime). Checked by cmd_doctor for
  # the appropriate pass-message ("unverified" vs "consistent").
  DOCTOR_DRIFT_UNVERIFIED=0

  # Check 1: provenance secrets must be present in fly secrets list.
  # Use quote-anchored patterns to prevent substring false-positives (e.g.
  # NOT_HERMES_AGENT_REF must not satisfy the HERMES_AGENT_REF check).
  local has_agent_ref=false has_deploy_channel=false
  if printf '%s' "$secrets_json" | grep -q '"HERMES_AGENT_REF"'; then
    has_agent_ref=true
  fi
  if printf '%s' "$secrets_json" | grep -q '"HERMES_DEPLOY_CHANNEL"'; then
    has_deploy_channel=true
  fi

  if [[ "$has_agent_ref" == "false" ]] || [[ "$has_deploy_channel" == "false" ]]; then
    printf 'Provenance secrets not found (deploy may predate provenance tracking)\n' >&2
    return 1
  fi

  # Check 2: local deploy summary must exist — absence is a provenance gap.
  local summary
  summary="$(doctor_load_deploy_summary "$app_name")"

  if [[ -z "$summary" ]]; then
    printf 'No local deploy summary found: run hermes-fly deploy to establish provenance baseline\n' >&2
    return 1
  fi

  # Check 3: validate deploy_channel shape in local summary.
  local local_channel
  local_channel="$(_doctor_extract_yaml_field 'deploy_channel' "$summary")"

  if [[ -z "$local_channel" ]]; then
    printf 'Missing deploy_channel in local summary: cannot verify provenance\n' >&2
    return 1
  fi

  case "$local_channel" in
    stable | preview | edge)
      # Recognized channel — shape is valid
      ;;
    *)
      printf 'Unexpected deploy channel in local summary: %s\n' "$local_channel" >&2
      return 1
      ;;
  esac

  # Check 4a: for stable/preview channels, verify local summary ref matches the canonical
  # intended ref. This catches coordinated drift where both local summary and runtime
  # manifest agree on a non-canonical ref (bypassing the local-vs-runtime comparison).
  local local_ref
  local_ref="$(_doctor_extract_yaml_field 'hermes_agent_ref' "$summary")"

  case "$local_channel" in
    stable | preview)
      # Prefer deploy.sh constants when available (hermes-fly sources both modules).
      # Falls back to local doctor constants so doctor.sh can still be sourced alone
      # (e.g. in unit tests). This means a release that bumps only deploy.sh is caught
      # immediately in production; the regression test (REVIEW_8) catches a stale
      # doctor constant before it reaches users.
      local _intended_ref="${HERMES_AGENT_DEFAULT_REF:-$_DOCTOR_HERMES_AGENT_STABLE_REF}"
      if [[ "$local_channel" == "preview" ]]; then
        _intended_ref="${HERMES_AGENT_PREVIEW_REF:-$_DOCTOR_HERMES_AGENT_PREVIEW_REF}"
      fi
      if [[ -z "$local_ref" ]]; then
        printf 'local summary missing hermes_agent_ref — cannot verify ref for %s channel\n' \
          "$local_channel" >&2
        return 1
      fi
      if [[ "$local_ref" != "$_intended_ref" ]]; then
        printf 'Unexpected ref: local summary=%s expected=%s for %s channel\n' \
          "$local_ref" "$_intended_ref" "$local_channel" >&2
        return 1
      fi
      ;;
    edge)
      # Edge tracks moving upstream — any ref value is expected; skip canonical check.
      # Still require field presence: an edge summary without hermes_agent_ref is incomplete.
      if [[ -z "$local_ref" ]]; then
        printf 'local summary missing hermes_agent_ref — cannot verify ref for edge channel\n' >&2
        return 1
      fi
      ;;
  esac

  # Check 4b: compare local summary values against runtime manifest.
  # Availability policy: fail-closed for stable (runtime verification required);
  # warn-only for preview/edge (machine may be stopped during review cycles).
  local runtime_manifest
  runtime_manifest="$(doctor_read_runtime_manifest "$app_name")"

  if [[ -z "$runtime_manifest" ]]; then
    if [[ "$local_channel" == "stable" ]]; then
      printf 'runtime manifest unavailable — stable channel requires runtime verification\n' >&2
      return 1
    else
      printf 'Warning: runtime manifest unavailable for %s channel — provenance unverified\n' \
        "$local_channel" >&2
      DOCTOR_DRIFT_UNVERIFIED=1
      return 0
    fi
  fi

  # Runtime manifest is readable — proceed with field comparisons.

  # Extract deploy_channel from runtime manifest JSON
  local runtime_channel
  runtime_channel="$(_doctor_extract_json_field 'deploy_channel' "$runtime_manifest")"

  # Fail-closed: readable manifest must contain deploy_channel
  if [[ -z "$runtime_channel" ]]; then
    printf 'runtime manifest missing deploy_channel — deploy may predate provenance tracking\n' >&2
    return 1
  fi

  # Extract hermes_agent_ref from runtime manifest JSON
  local runtime_ref
  runtime_ref="$(_doctor_extract_json_field 'hermes_agent_ref' "$runtime_manifest")"

  # Fail-closed: readable manifest must contain hermes_agent_ref
  if [[ -z "$runtime_ref" ]]; then
    printf 'runtime manifest missing hermes_agent_ref — deploy may predate provenance tracking\n' >&2
    return 1
  fi

  # Fail-closed: local summary must contain hermes_agent_ref when runtime is readable
  if [[ -z "$local_ref" ]]; then
    printf 'local summary missing hermes_agent_ref — cannot verify ref provenance\n' >&2
    return 1
  fi

  # Compare channel values
  if [[ "$runtime_channel" != "$local_channel" ]]; then
    printf 'Channel drift: local summary=%s runtime=%s\n' \
      "$local_channel" "$runtime_channel" >&2
    return 1
  fi

  # Compare ref values
  if [[ "$runtime_ref" != "$local_ref" ]]; then
    printf 'Ref drift: local summary=%s runtime=%s\n' \
      "$local_ref" "$runtime_ref" >&2
    return 1
  fi

  # Extract compatibility_policy_version from runtime manifest JSON
  local runtime_compat
  runtime_compat="$(_doctor_extract_json_field 'compatibility_policy_version' "$runtime_manifest")"

  # Extract compatibility_policy_version from local summary YAML
  local local_compat
  local_compat="$(_doctor_extract_yaml_field 'compatibility_policy_version' "$summary")"

  # Compare compat policy versions (skip when both absent; fail when one or both set and differ)
  if [[ -n "$local_compat" || -n "$runtime_compat" ]]; then
    if [[ "$local_compat" != "$runtime_compat" ]]; then
      printf 'Compat policy drift: local summary=%s runtime=%s\n' \
        "${local_compat:-<none>}" "${runtime_compat:-<none>}" >&2
      return 1
    fi
    # Validate compat policy version against supported versions from snapshot.
    if [[ -n "$local_compat" ]]; then
      local _supported
      _supported="$(_doctor_supported_compat_versions)" || true
      if [[ -z "$_supported" ]]; then
        printf 'Cannot validate compat policy version: supported versions unavailable (snapshot missing or unreadable)\n' >&2
        return 1
      fi
      if ! printf '%s\n' "$_supported" | grep -qxF "$local_compat" 2>/dev/null; then
        local _supported_list
        _supported_list="$(printf '%s\n' "$_supported" | tr '\n' ',' | sed 's/,$//')"
        printf 'Unknown compat policy version: %s (supported: %s)\n' \
          "$local_compat" "${_supported_list:-<none>}" >&2
        return 1
      fi
    fi
  fi

  return 0
}

# --------------------------------------------------------------------------
# cmd_doctor "app_name"
# Run all checks in order. Track pass/fail count. Print summary.
# Return 0 if all pass, 1 if any fail.
# --------------------------------------------------------------------------
cmd_doctor() {
  local app_name="$1"
  local pass_count=0 fail_count=0
  local status_json=""

  # Check 1: App exists
  if doctor_check_app_exists "$app_name"; then
    doctor_report "app" "pass" "App '${app_name}' found"
    ((pass_count++))
    # Fetch status JSON for subsequent checks
    status_json="$(fly_status "$app_name" 2>/dev/null)" || true
  else
    doctor_report "app" "fail" "App '${app_name}' not found. Create with: hermes-fly deploy"
    ((fail_count++))
    # If app doesn't exist, remaining checks will also fail -- but still run them
    # Actually, skip remaining checks since they depend on the app existing
    doctor_report "summary" "fail" "${pass_count} passed, ${fail_count} failed"
    return 1
  fi

  # Check 2: Machine running
  if doctor_check_machine_running "$status_json"; then
    doctor_report "machine" "pass" "Machine is running"
    ((pass_count++))
  else
    doctor_report "machine" "fail" "Machine not running. Start with: fly machine start -a ${app_name}"
    ((fail_count++))
  fi

  # Check 3: Volumes mounted
  if doctor_check_volume_mounted "$app_name"; then
    doctor_report "volumes" "pass" "Volumes attached"
    ((pass_count++))
  else
    doctor_report "volumes" "fail" "No volumes found. Create with: fly volumes create -a ${app_name}"
    ((fail_count++))
  fi

  # Fetch secrets JSON for checks 4 and 7
  local secrets_json=""
  secrets_json="$(fly secrets list --app "$app_name" --json 2>/dev/null)" || true

  # Check 4: Secrets set
  if doctor_check_secrets_set "$secrets_json"; then
    doctor_report "secrets" "pass" "Required secrets are set"
    ((pass_count++))
  else
    doctor_report "secrets" "fail" "Secrets missing. Set with: fly secrets set OPENROUTER_API_KEY=xxx -a ${app_name}"
    ((fail_count++))
  fi

  # Check 5: Hermes process
  if doctor_check_hermes_process "$status_json"; then
    doctor_report "hermes" "pass" "Hermes process detected"
    ((pass_count++))
  else
    doctor_report "hermes" "fail" "Hermes process not found in status"
    ((fail_count++))
  fi

  # Check 6: Gateway health
  if doctor_check_gateway_health "$app_name"; then
    doctor_report "gateway" "pass" "Gateway is responding"
    ((pass_count++))
  else
    doctor_report "gateway" "fail" "Gateway not responding at https://${app_name}.fly.dev"
    ((fail_count++))
  fi

  # Check 7: API connectivity
  if doctor_check_api_connectivity "$secrets_json"; then
    doctor_report "api" "pass" "LLM API is reachable"
    ((pass_count++))
  else
    doctor_report "api" "fail" "LLM API unreachable at https://openrouter.ai"
    ((fail_count++))
  fi

  # Check 8: Drift detection (PR-05)
  # DOCTOR_DRIFT_UNVERIFIED is reset inside doctor_check_drift; check it after.
  if doctor_check_drift "$app_name" "$secrets_json"; then
    if [[ "${DOCTOR_DRIFT_UNVERIFIED:-0}" == "1" ]]; then
      doctor_report "drift" "pass" "Deploy provenance unverified (runtime manifest unavailable)"
    else
      doctor_report "drift" "pass" "Deploy provenance consistent"
    fi
    ((pass_count++))
  else
    doctor_report "drift" "fail" "Deploy drift detected — run 'hermes-fly deploy' to refresh"
    ((fail_count++))
  fi

  # Summary
  if ((fail_count > 0)); then
    doctor_report "summary" "fail" "${pass_count} passed, ${fail_count} failed"
    return 1
  else
    doctor_report "summary" "pass" "${pass_count} passed, ${fail_count} failed"
    return 0
  fi
}
