#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC1091
# lib/deploy.sh — Deploy wizard
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source dependencies (skip if already loaded) ---
_DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Guard: only source each dep if its key function/var is not yet defined.
# ui.sh defines EXIT_SUCCESS as readonly — re-sourcing it would be fatal.
if [[ -z "${EXIT_SUCCESS+x}" ]]; then
  # shellcheck source=./ui.sh
  source "${_DEPLOY_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi
if ! declare -f fly_check_installed >/dev/null 2>&1; then
  # shellcheck source=./fly-helpers.sh
  source "${_DEPLOY_SCRIPT_DIR}/fly-helpers.sh" 2>/dev/null || true
fi
if ! declare -f docker_get_build_dir >/dev/null 2>&1; then
  # shellcheck source=./docker-helpers.sh
  source "${_DEPLOY_SCRIPT_DIR}/docker-helpers.sh" 2>/dev/null || true
fi
if ! declare -f messaging_setup_menu >/dev/null 2>&1; then
  # shellcheck source=./messaging.sh
  source "${_DEPLOY_SCRIPT_DIR}/messaging.sh" 2>/dev/null || true
fi
if ! declare -f config_save_app >/dev/null 2>&1; then
  # shellcheck source=./config.sh
  source "${_DEPLOY_SCRIPT_DIR}/config.sh" 2>/dev/null || true
fi
if ! declare -f status_estimate_cost >/dev/null 2>&1; then
  # shellcheck source=./status.sh
  source "${_DEPLOY_SCRIPT_DIR}/status.sh" 2>/dev/null || true
fi
if ! declare -f openrouter_setup_with_models >/dev/null 2>&1; then
  # shellcheck source=./openrouter.sh
  source "${_DEPLOY_SCRIPT_DIR}/openrouter.sh" 2>/dev/null || true
fi
if ! declare -f reasoning_normalize_family >/dev/null 2>&1; then
  # shellcheck source=./reasoning.sh
  source "${_DEPLOY_SCRIPT_DIR}/reasoning.sh" 2>/dev/null || true
fi

# ==========================================================================
# Hermes Agent ref pinning
# ==========================================================================

# Pinned to upstream main at hermes-fly v0.1.14 release time.
# DUAL-UPDATE REQUIREMENT: bump this SHA when cutting a new hermes-fly release.
# I1: intentionally not readonly — consistent with all other module-level constants in this
#     project; integrity is enforced by the HERMES_AGENT_DEFAULT_REF test in tests/deploy.bats.
HERMES_AGENT_DEFAULT_REF="8eefbef91cd715cfe410bba8c13cfab4eb3040df"
# Preview ref: same as stable until a dedicated preview stream is established.
# Update independently of stable when a preview candidate is available.
HERMES_AGENT_PREVIEW_REF="${HERMES_AGENT_DEFAULT_REF}"
# Edge ref: tracks the upstream moving main branch (explicitly non-reproducible).
HERMES_AGENT_EDGE_REF="main"

# --------------------------------------------------------------------------
# deploy_resolve_hermes_ref — resolve Hermes Agent ref for Dockerfile build
# Returns pinned default ref, or HERMES_AGENT_REF override if set.
# Warns on stderr when override is active (non-reproducible build).
# Exit codes: 0 always
# --------------------------------------------------------------------------
deploy_resolve_hermes_ref() {
  # Explicit HERMES_AGENT_REF override always takes precedence (non-reproducible).
  if [[ -n "${HERMES_AGENT_REF:-}" ]]; then
    # M2: ui_warn already writes to stderr; no redundant >&2
    ui_warn "Using custom Hermes Agent ref: ${HERMES_AGENT_REF} (non-reproducible build)"
    printf '%s' "$HERMES_AGENT_REF"
    return 0
  fi
  # Select ref based on the active deploy channel (set by deploy_resolve_channel).
  case "${DEPLOY_CHANNEL:-stable}" in
    edge)
      printf '%s' "$HERMES_AGENT_EDGE_REF"
      ;;
    preview)
      printf '%s' "$HERMES_AGENT_PREVIEW_REF"
      ;;
    *)
      printf '%s' "$HERMES_AGENT_DEFAULT_REF"
      ;;
  esac
  # L1: explicit return 0 — contract: always succeeds
  return 0
}

# ==========================================================================
# Release channel resolution (PR-05)
# ==========================================================================

# --------------------------------------------------------------------------
# deploy_resolve_channel — resolve deployment release channel
# Reads HERMES_FLY_CHANNEL env var. Valid: stable, preview, edge.
# Unknown values → warn and fall back to stable.
# Edge channel → warn about non-reproducibility.
# Exit codes: 0 always
# --------------------------------------------------------------------------
deploy_resolve_channel() {
  local channel="${HERMES_FLY_CHANNEL:-stable}"
  # Treat empty string same as unset → default stable
  if [[ -z "$channel" ]]; then
    channel="stable"
  fi
  case "$channel" in
    stable)
      printf '%s' "stable"
      ;;
    preview)
      printf '%s' "preview"
      ;;
    edge)
      ui_warn "Using edge channel: build may track moving upstream refs (non-reproducible)"
      printf '%s' "edge"
      ;;
    *)
      ui_warn "Unknown channel '${channel}': falling back to 'stable'"
      printf '%s' "stable"
      ;;
  esac
  return 0
}

# ==========================================================================
# Step 4.1: Preflight Checks
# ==========================================================================

# --------------------------------------------------------------------------
# deploy_check_platform — check OS. Accept Darwin or Linux, reject others.
# Uses HERMES_FLY_PLATFORM env override for testing, falls back to uname -s.
# Returns: 0 on supported, 1 on unsupported
# --------------------------------------------------------------------------
deploy_check_platform() {
  local platform
  platform="${HERMES_FLY_PLATFORM:-$(uname -s)}"

  case "$platform" in
    Darwin | Linux)
      return 0
      ;;
    *)
      ui_error "Unsupported platform: ${platform}. Only macOS and Linux are supported."
      return 1
      ;;
  esac
}

# --------------------------------------------------------------------------
# deploy_check_prerequisites — verify fly, git, curl are on PATH
# Returns: 0 if all present, 1 with missing tool name if any absent
# --------------------------------------------------------------------------
deploy_check_prerequisites() {
  local tool
  for tool in fly git curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      ui_error "Required tool not found: ${tool}"
      return 1
    fi
  done
  return 0
}

# --------------------------------------------------------------------------
# deploy_check_connectivity — verify we can reach fly.io
# Returns: 0 on success, EXIT_NETWORK (3) on failure
# --------------------------------------------------------------------------
deploy_check_connectivity() {
  if curl -sf --max-time 5 https://fly.io >/dev/null 2>&1; then
    return 0
  else
    ui_error "Cannot reach fly.io. Check your internet connection."
    return "${EXIT_NETWORK}"
  fi
}

# --------------------------------------------------------------------------
# deploy_preflight — orchestrate all preflight checks
# Stops at first failure with appropriate exit code.
# --------------------------------------------------------------------------
deploy_preflight() {
  # Verbose mode: show each step individually
  if [[ "${HERMES_FLY_VERBOSE:-0}" == "1" ]]; then
    local total=6

    ui_step 1 "$total" "Checking platform"
    deploy_check_platform || return 1

    ui_step 2 "$total" "Checking prerequisites"
    if ! deploy_check_prerequisites 2>/dev/null; then
      prereqs_check_and_install || return 1
      deploy_check_prerequisites || return 1
    fi

    ui_step 3 "$total" "Checking fly CLI"
    fly_check_installed || return 1

    ui_step 4 "$total" "Checking fly version"
    fly_check_version || return 1

    ui_step 5 "$total" "Checking authentication"
    fly_check_auth_interactive || return "$EXIT_AUTH"

    ui_step 6 "$total" "Checking connectivity"
    deploy_check_connectivity || return "$EXIT_NETWORK"

    ui_success "All preflight checks passed"
    return 0
  fi

  # Default: animated spinner
  ui_spinner_start "Checking platform..."

  if ! deploy_check_platform 2>/dev/null; then
    ui_spinner_stop 1 "Unsupported platform"
    return 1
  fi

  ui_spinner_update "Checking prerequisites..."
  if ! deploy_check_prerequisites 2>/dev/null; then
    ui_spinner_stop 1 "Missing prerequisites — attempting to help"
    if ! prereqs_check_and_install; then
      return 1
    fi
    if ! deploy_check_prerequisites 2>/dev/null; then
      ui_error "Still missing prerequisites after install attempts."
      return 1
    fi
    ui_spinner_start "Continuing preflight..."
  fi

  ui_spinner_update "Checking fly CLI..."
  if ! fly_check_installed 2>/dev/null; then
    ui_spinner_stop 1 "fly CLI not found"
    return 1
  fi

  ui_spinner_update "Checking fly version..."
  if ! fly_check_version 2>/dev/null; then
    ui_spinner_stop 1 "fly CLI outdated (need >= 0.2.0)"
    return 1
  fi

  ui_spinner_update "Checking authentication..."
  if ! fly_check_auth 2>/dev/null; then
    # Auth failed — stop spinner for interactive retry
    local login_cmd
    login_cmd="$(fly_auth_login_command)"
    ui_spinner_stop 1 "Not authenticated"
    printf 'Run "%s" in another terminal.\n' "$login_cmd" >&2
    printf 'Press Enter when ready to retry... ' >&2
    IFS= read -r -t 60 _ || true

    ui_spinner_start "Retrying authentication..."
    if ! fly_check_auth 2>/dev/null; then
      ui_spinner_stop 1 "Still not authenticated"
      return "$EXIT_AUTH"
    fi
  fi

  ui_spinner_update "Checking connectivity..."
  if ! deploy_check_connectivity 2>/dev/null; then
    ui_spinner_stop 1 "Cannot reach fly.io"
    return "$EXIT_NETWORK"
  fi

  ui_spinner_stop 0 "All preflight checks passed"
  return 0
}

# ==========================================================================
# Step 4.2: Configuration Collection
# ==========================================================================

# --------------------------------------------------------------------------
# deploy_generate_app_name — suggest "hermes-USER-RANDOM"
# Echoes the suggestion to stdout.
# --------------------------------------------------------------------------
deploy_generate_app_name() {
  local user random_digits
  user="$(whoami 2>/dev/null || echo "user")"
  random_digits="$(printf '%03d' $((RANDOM % 1000)))"
  echo "hermes-${user}-${random_digits}"
}

# --------------------------------------------------------------------------
# deploy_validate_app_name NAME — validate a Fly.io app name
# Must be 2-63 chars, lowercase letters/digits/hyphens, start with letter,
# end with letter or digit.
# --------------------------------------------------------------------------
deploy_validate_app_name() {
  local name="$1"
  if [[ ${#name} -lt 2 || ${#name} -gt 63 ]]; then
    printf 'App name must be 2-63 characters.\n' >&2
    return 1
  fi
  if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
    printf 'App name must start with a letter, use only lowercase letters, digits, and hyphens, and end with a letter or digit.\n' >&2
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------
# deploy_collect_app_name VARNAME — prompt for app name
# If empty input, uses generated suggestion. Stores in VARNAME.
# --------------------------------------------------------------------------
deploy_collect_app_name() {
  local varname="$1"
  local suggestion
  suggestion="$(deploy_generate_app_name)"

  printf 'Each deployment needs a unique name on Fly.io.\n' >&2
  printf 'This won'\''t be visible to anyone chatting with your agent.\n\n' >&2
  printf 'Suggested: %s\n' "$suggestion" >&2
  printf 'Press Enter to use it, or type your own.\n\n' >&2

  local input
  while true; do
    printf 'Deployment name [%s]: ' "$suggestion" >&2
    IFS= read -r input
    if [[ -z "$input" ]]; then
      eval "$varname=\"\$suggestion\""
      return 0
    fi
    if ! deploy_validate_app_name "$input" 2>/dev/null; then
      printf 'Invalid app name. ' >&2
      continue
    fi
    # Check availability via Fly API (fail-open on network/auth errors)
    local create_output
    if create_output="$(fly_create_app "$input" "${DEPLOY_ORG:-}" 2>&1)"; then
      DEPLOY_APP_CREATED=1
      eval "$varname=\"\$input\""
      return 0
    fi
    if printf '%s' "$create_output" | grep -qiE 'already (exists|been taken)'; then
      printf 'App name "%s" is not available. Try another name.\n' "$input" >&2
      continue
    fi
    # Non-name-related error (network, auth) — accept and defer to provisioning
    eval "$varname=\"\$input\""
    return 0
  done
}

# --------------------------------------------------------------------------
# deploy_parse_orgs JSON — parse fly orgs list JSON
# Supports both formats:
#   Flat map:  {"slug":"name",...}
#   Array:     [{"name":"...","slug":"...","type":"..."},...]
# Sets global arrays: _ORG_SLUGS, _ORG_NAMES
# --------------------------------------------------------------------------
deploy_parse_orgs() {
  local json="$1"
  _ORG_SLUGS=()
  _ORG_NAMES=()

  [[ "$json" == "{}" || "$json" == "[]" || -z "$json" ]] && return 0

  # Detect format: array starts with [, flat map starts with {
  if [[ "$json" == "["* ]]; then
    # Array-of-objects format: [{"name":"...","slug":"...","type":"..."},...]
    # Extract each object's slug and name fields
    local slug name obj
    # Split on },{  (tolerant of whitespace around comma)
    local objects_raw
    objects_raw="$(printf '%s' "$json" | sed 's/^\[//;s/\]$//;s/}[[:space:]]*,[[:space:]]*{/}\
{/g')"
    while IFS= read -r obj; do
      [[ -z "$obj" ]] && continue
      slug="$(printf '%s' "$obj" | sed -n 's/.*"slug"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      name="$(printf '%s' "$obj" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      [[ -z "$slug" ]] && continue
      _ORG_SLUGS+=("$slug")
      _ORG_NAMES+=("${name:-$slug}")
    done <<<"$objects_raw"
  else
    # Flat map format: {"slug":"name",...}
    local pairs_raw
    pairs_raw="$(printf '%s' "$json" | grep -oE '"[^"]+"\s*:\s*"[^"]+"')"

    local line slug name
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      slug="$(printf '%s' "$line" | sed 's/"\([^"]*\)"[[:space:]]*:.*/\1/')"
      name="$(printf '%s' "$line" | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/')"
      _ORG_SLUGS+=("$slug")
      _ORG_NAMES+=("$name")
    done <<<"$pairs_raw"
  fi
}

# --------------------------------------------------------------------------
# deploy_collect_org VARNAME — select a Fly.io organization
# Auto-selects single org silently. Shows table for multiple orgs.
# --------------------------------------------------------------------------
deploy_collect_org() {
  local varname="$1"

  local orgs_json
  if ! orgs_json="$(fly_get_orgs 2>/dev/null)" || [[ -z "$orgs_json" ]]; then
    ui_error "Failed to fetch Fly.io organizations"
    return 1
  fi

  deploy_parse_orgs "$orgs_json"

  if [[ ${#_ORG_SLUGS[@]} -eq 0 ]]; then
    ui_error "No Fly.io organizations found"
    return 1
  fi

  # Auto-select single org silently
  if [[ ${#_ORG_SLUGS[@]} -eq 1 ]]; then
    eval "$varname=\"\${_ORG_SLUGS[0]}\""
    return 0
  fi

  # Multiple orgs: show selection table
  printf '\nYour Fly.io account has multiple workspaces. Choose where to deploy.\n' >&2
  printf 'See your workspaces at https://fly.io/dashboard\n\n' >&2
  printf '  ┌───┬──────────────────────┬──────────────────┐\n' >&2
  printf '  │ # │ Workspace            │ ID               │\n' >&2
  printf '  ├───┼──────────────────────┼──────────────────┤\n' >&2
  local i
  for i in "${!_ORG_SLUGS[@]}"; do
    printf '  │ %d │ %-20s │ %-16s │\n' "$((i + 1))" "${_ORG_NAMES[$i]}" "${_ORG_SLUGS[$i]}" >&2
  done
  printf '  └───┴──────────────────────┴──────────────────┘\n' >&2

  local choice
  while true; do
    printf 'Choose a workspace [1]: ' >&2
    IFS= read -r choice
    [[ -z "$choice" ]] && choice=1
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#_ORG_SLUGS[@]})); then
      eval "$varname=\"\${_ORG_SLUGS[$((choice - 1))]}\""
      return 0
    fi
    printf 'Invalid choice. Please enter a number between 1 and %d.\n' "${#_ORG_SLUGS[@]}" >&2
  done
}

# --------------------------------------------------------------------------
# deploy_parse_regions JSON — parse fly platform regions JSON
# Sets global arrays: _REGION_CODES, _REGION_NAMES
# --------------------------------------------------------------------------
deploy_parse_regions() {
  local json="$1"
  _REGION_CODES=()
  _REGION_NAMES=()

  [[ "$json" == "[]" || -z "$json" ]] && return 0

  local codes_raw names_raw
  codes_raw="$(printf '%s' "$json" | grep -oE '"code"\s*:\s*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"
  names_raw="$(printf '%s' "$json" | grep -oE '"name"\s*:\s*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && _REGION_CODES+=("$line")
  done <<<"$codes_raw"
  while IFS= read -r line; do
    [[ -n "$line" ]] && _REGION_NAMES+=("$line")
  done <<<"$names_raw"
}

# --------------------------------------------------------------------------
# deploy_get_region_continent CODE — map region code to continent
# Echoes continent name. Unknown codes return "Other".
# --------------------------------------------------------------------------
deploy_get_region_continent() {
  local code="$1"
  case "$code" in
    iad | ord | lax | sea | sjc | yyz | mia | atl | den | ewr | bos | dfw | phx) echo "Americas" ;;
    ams | fra | lhr | cdg | mad | waw | arn | otp) echo "Europe" ;;
    nrt | sin | hkg | bom | bkk | del) echo "Asia-Pacific" ;;
    syd) echo "Oceania" ;;
    gru | bog | eze | scl | qro | gdl) echo "South America" ;;
    jnb) echo "Africa" ;;
    *) echo "Other" ;;
  esac
}

# --------------------------------------------------------------------------
# deploy_collect_region VARNAME — select a Fly.io region (two-step picker)
# Step 1: continent selection. Step 2: city within continent.
# Fetches regions dynamically from fly API. Falls back to static list.
# --------------------------------------------------------------------------
deploy_collect_region() {
  local varname="$1"

  # Fallback static list
  local fallback_codes=("iad" "ord" "lax" "ams" "fra" "lhr" "nrt" "sin" "syd" "gru")
  local fallback_names=(
    "Ashburn, Virginia (US)"
    "Chicago, Illinois (US)"
    "Los Angeles, California (US)"
    "Amsterdam, Netherlands"
    "Frankfurt, Germany"
    "London, United Kingdom"
    "Tokyo, Japan"
    "Singapore, Singapore"
    "Sydney, Australia"
    "Sao Paulo, Brazil"
  )

  # Try dynamic fetch
  _REGION_CODES=()
  _REGION_NAMES=()
  local regions_json
  if regions_json="$(fly_get_regions 2>/dev/null)" && [[ -n "$regions_json" ]]; then
    deploy_parse_regions "$regions_json"
  fi

  # Use fallback if parsing yielded nothing
  if [[ ${#_REGION_CODES[@]} -eq 0 ]]; then
    _REGION_CODES=("${fallback_codes[@]}")
    _REGION_NAMES=("${fallback_names[@]}")
  fi

  # Build continent cache (one lookup per region, reused below)
  local -a _region_continents=()
  local code i
  for i in "${!_REGION_CODES[@]}"; do
    _region_continents+=("$(deploy_get_region_continent "${_REGION_CODES[$i]}")")
  done

  # Build continent buckets
  local continent_order=("Americas" "Europe" "Asia-Pacific" "Oceania" "South America" "Africa" "Other")
  local -a continent_list=()
  local -a continent_counts=()
  local continent

  for continent in "${continent_order[@]}"; do
    local count=0
    for i in "${!_REGION_CODES[@]}"; do
      if [[ "${_region_continents[$i]}" == "$continent" ]]; then
        ((count++))
      fi
    done
    if ((count > 0)); then
      continent_list+=("$continent")
      continent_counts+=("$count")
    fi
  done

  # Step 1: continent picker
  printf '\nWhere are you (or your users) located?\n\n' >&2
  printf '  ┌───┬──────────────────┬────────────┐\n' >&2
  printf '  │ # │ Region           │ Locations  │\n' >&2
  printf '  ├───┼──────────────────┼────────────┤\n' >&2
  for i in "${!continent_list[@]}"; do
    printf '  │ %d │ %-16s │ %2d locations│\n' "$((i + 1))" "${continent_list[$i]}" "${continent_counts[$i]}" >&2
  done
  printf '  └───┴──────────────────┴────────────┘\n' >&2

  local cont_choice
  while true; do
    printf 'Choose a region [1]: ' >&2
    IFS= read -r cont_choice
    [[ -z "$cont_choice" ]] && cont_choice=1
    if [[ "$cont_choice" =~ ^[0-9]+$ ]] && ((cont_choice >= 1 && cont_choice <= ${#continent_list[@]})); then
      break
    fi
    printf 'Invalid choice. Please enter a number between 1 and %d.\n' "${#continent_list[@]}" >&2
  done

  local selected_continent="${continent_list[$((cont_choice - 1))]}"

  # Step 2: city picker within selected continent
  local -a city_codes=() city_names=()
  for i in "${!_REGION_CODES[@]}"; do
    if [[ "${_region_continents[$i]}" == "$selected_continent" ]]; then
      city_codes+=("${_REGION_CODES[$i]}")
      city_names+=("${_REGION_NAMES[$i]}")
    fi
  done

  printf '\n%s locations:\n\n' "$selected_continent" >&2
  printf '  ┌───┬──────────────────────────────────┬──────┐\n' >&2
  printf '  │ # │ Location                         │ Code │\n' >&2
  printf '  ├───┼──────────────────────────────────┼──────┤\n' >&2
  for i in "${!city_codes[@]}"; do
    printf '  │ %d │ %-32s │ %-4s │\n' "$((i + 1))" "${city_names[$i]}" "${city_codes[$i]}" >&2
  done
  printf '  └───┴──────────────────────────────────┴──────┘\n' >&2

  local city_choice
  while true; do
    printf 'Choose a location [1]: ' >&2
    IFS= read -r city_choice
    [[ -z "$city_choice" ]] && city_choice=1
    if [[ "$city_choice" =~ ^[0-9]+$ ]] && ((city_choice >= 1 && city_choice <= ${#city_codes[@]})); then
      eval "$varname=\"\${city_codes[$((city_choice - 1))]}\""
      return 0
    fi
    printf 'Invalid choice. Please enter a number between 1 and %d.\n' "${#city_codes[@]}" >&2
  done
}

# --------------------------------------------------------------------------
# deploy_parse_vm_sizes JSON — parse fly platform vm-sizes JSON
# Sets global arrays: _VM_NAMES, _VM_MEMORY, _VM_PRICES
# --------------------------------------------------------------------------
deploy_parse_vm_sizes() {
  local json="$1"
  _VM_NAMES=()
  _VM_MEMORY=()
  _VM_PRICES=()

  [[ "$json" == "[]" || -z "$json" ]] && return 0

  # Parse per-object to avoid cross-record field skew when Fly payloads are incomplete.
  local obj name mem price objects_raw
  objects_raw="$(printf '%s' "$json" | tr '\n' ' ' | sed 's/^\[//;s/\]$//;s/}[[:space:]]*,[[:space:]]*{/}\
{/g')"
  while IFS= read -r obj; do
    [[ -z "$obj" ]] && continue
    name="$(printf '%s' "$obj" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [[ -z "$name" ]] && continue
    mem="$(printf '%s' "$obj" | sed -n 's/.*"memory_mb"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
    price="$(printf '%s' "$obj" | sed -n 's/.*"price_month"[[:space:]]*:[[:space:]]*\([0-9.][0-9.]*\).*/\1/p')"
    _VM_NAMES+=("$name")
    _VM_MEMORY+=("${mem:-0}")
    _VM_PRICES+=("${price:-0}")
  done <<<"$objects_raw"
}

# --------------------------------------------------------------------------
# deploy_get_vm_tier NAME — return tier label for VM size
# --------------------------------------------------------------------------
deploy_get_vm_tier() {
  case "$1" in
    shared-cpu-1x) echo "Starter" ;;
    shared-cpu-2x) echo "Standard" ;;
    performance-1x) echo "Pro" ;;
    performance-2x) echo "Power" ;;
    *) echo "" ;;
  esac
}

# --------------------------------------------------------------------------
# deploy_get_vm_recommendation NAME — return recommendation label
# --------------------------------------------------------------------------
deploy_get_vm_recommendation() {
  case "$1" in
    shared-cpu-1x) echo "Testing & light use" ;;
    shared-cpu-2x) echo "Recommended for most" ;;
    performance-1x) echo "Multi-tool agents" ;;
    performance-2x) echo "Heavy / multi-user" ;;
    *) echo "" ;;
  esac
}

# --------------------------------------------------------------------------
# deploy_collect_vm_size SIZE_VAR MEMORY_VAR — select VM size
# Fetches VM sizes dynamically from fly API. Falls back to static list.
# --------------------------------------------------------------------------
_deploy_fallback_mem() {
  case "$1" in
    shared-cpu-1x) echo 256 ;;
    shared-cpu-2x) echo 512 ;;
    performance-1x) echo 2048 ;;
    performance-2x) echo 4096 ;;
    *) echo 0 ;;
  esac
}

_deploy_fallback_price() {
  case "$1" in
    shared-cpu-1x) echo "2.02" ;;
    shared-cpu-2x) echo "4.04" ;;
    performance-1x) echo "32.19" ;;
    performance-2x) echo "64.39" ;;
    *) echo "0" ;;
  esac
}

# _deploy_lookup_vm NAME FIELD — look up a VM field from parsed _VM_* arrays
# FIELD: mem or price. Returns empty string if not found.
_deploy_lookup_vm() {
  local name="$1" field="$2" i
  for i in "${!_VM_NAMES[@]}"; do
    if [[ "${_VM_NAMES[$i]}" == "$name" ]]; then
      case "$field" in
        mem) echo "${_VM_MEMORY[$i]}" ;;
        price) echo "${_VM_PRICES[$i]}" ;;
      esac
      return
    fi
  done
}

deploy_collect_vm_size() {
  local size_var="$1" memory_var="$2"

  # All possible tiers in display order
  local all_tiers=("shared-cpu-1x" "shared-cpu-2x" "performance-1x" "performance-2x")
  local default_vm="shared-cpu-2x"

  # Try dynamic fetch
  _VM_NAMES=()
  _VM_MEMORY=()
  _VM_PRICES=()
  local vm_json
  if vm_json="$(fly_get_vm_sizes 2>/dev/null)" && [[ -n "$vm_json" ]]; then
    deploy_parse_vm_sizes "$vm_json"
  fi

  # Filter to available tiers (those found in API or all if API failed)
  local available=() name
  if [[ ${#_VM_NAMES[@]} -gt 0 ]]; then
    for name in "${all_tiers[@]}"; do
      if _deploy_lookup_vm "$name" mem >/dev/null 2>&1 && [[ -n "$(_deploy_lookup_vm "$name" mem)" ]]; then
        available+=("$name")
      fi
    done
  fi
  # Fallback: show all tiers with static data
  [[ ${#available[@]} -eq 0 ]] && available=("${all_tiers[@]}")

  # Find default index
  local default_idx=1 i
  for i in "${!available[@]}"; do
    [[ "${available[$i]}" == "$default_vm" ]] && default_idx=$((i + 1))
  done

  # Build table rows
  local idx=0 mem price rec mem_label tier
  local rows=()
  for name in "${available[@]}"; do
    idx=$((idx + 1))
    mem="$(_deploy_lookup_vm "$name" mem)"
    price="$(_deploy_lookup_vm "$name" price)"
    [[ -z "$mem" ]] && mem="$(_deploy_fallback_mem "$name")"
    [[ -z "$price" ]] && price="$(_deploy_fallback_price "$name")"
    tier="$(deploy_get_vm_tier "$name")"
    rec="$(deploy_get_vm_recommendation "$name")"

    if ((mem >= 1024)); then
      mem_label="$((mem / 1024)) GB"
    else
      mem_label="${mem} MB"
    fi

    rows+=("$(printf '%d│%-10s│%-6s│$%-8s│%s' "$idx" "$tier" "$mem_label" "$price/mo" "$rec")")
  done

  printf '\nHow powerful should your agent'\''s server be?\n\n' >&2
  printf '  ┌───┬────────────┬────────┬───────────┬──────────────────────────┐\n' >&2
  printf '  │ # │ Tier       │ RAM    │ Cost      │ Best for                 │\n' >&2
  printf '  ├───┼────────────┼────────┼───────────┼──────────────────────────┤\n' >&2
  local row
  for row in "${rows[@]}"; do
    local n ti rm co bf
    IFS='│' read -r n ti rm co bf <<<"$row"
    printf '  │ %s │ %-10s │ %-6s │ %-9s │ %-24s │\n' "$n" "$ti" "$rm" "$co" "$bf" >&2
  done
  printf '  └───┴────────────┴────────┴───────────┴──────────────────────────┘\n' >&2
  printf '  Prices are estimates. Current rates: https://fly.io/calculator\n' >&2

  local choice
  while true; do
    printf 'Choose a tier [%d]: ' "$default_idx" >&2
    IFS= read -r choice
    [[ -z "$choice" ]] && choice=$default_idx
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#available[@]})); then
      local selected="${available[$((choice - 1))]}"
      local sel_mem
      sel_mem="$(_deploy_lookup_vm "$selected" mem)"
      [[ -z "$sel_mem" ]] && sel_mem="$(_deploy_fallback_mem "$selected")"

      if ((sel_mem >= 1024)); then
        eval "$memory_var=\"$((sel_mem / 1024))gb\""
      else
        eval "$memory_var=\"${sel_mem}mb\""
      fi
      eval "$size_var=\"\$selected\""
      return 0
    fi
    printf 'Invalid choice. Please enter a number between 1 and %d.\n' "${#available[@]}" >&2
  done
}

# --------------------------------------------------------------------------
# deploy_collect_volume_size VARNAME — select persistent volume size
# Stores numeric GB value (e.g., 1, 5, 10).
# --------------------------------------------------------------------------
deploy_collect_volume_size() {
  local varname="$1"

  local sizes=(1 5 10)
  local labels=("Testing & light use" "Recommended for most" "Media & heavy usage")
  local costs=("0.15" "0.75" "1.50")
  local default_idx=2

  printf '\nHow much storage should your agent have?\n\n' >&2
  printf '  ┌───┬──────┬───────────────────────┬───────────┐\n' >&2
  printf '  │ # │ Size │ Best for              │ Cost      │\n' >&2
  printf '  ├───┼──────┼───────────────────────┼───────────┤\n' >&2
  local i
  for i in "${!sizes[@]}"; do
    printf '  │ %d │ %2d GB │ %-21s │ $%s/mo  │\n' "$((i + 1))" "${sizes[$i]}" "${labels[$i]}" "${costs[$i]}" >&2
  done
  printf '  └───┴──────┴───────────────────────┴───────────┘\n' >&2
  printf '  Prices are estimates. Current rates: https://fly.io/calculator\n' >&2

  local choice
  while true; do
    printf 'Choice [%d]: ' "$default_idx" >&2
    IFS= read -r choice
    [[ -z "$choice" ]] && choice=$default_idx
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#sizes[@]})); then
      eval "$varname=\"\${sizes[$((choice - 1))]}\""
      return 0
    fi
    printf 'Invalid choice. Please enter a number between 1 and %d.\n' "${#sizes[@]}" >&2
  done
}

# --------------------------------------------------------------------------
# deploy_collect_llm_config API_KEY_VAR MODEL_VAR — ask for LLM settings
# Presents 3-option provider menu. Sets DEPLOY_LLM_PROVIDER global.
# API key is required (re-prompts). Model has a default for OpenRouter.
# --------------------------------------------------------------------------
deploy_collect_llm_config() {
  local api_key_var="$1" model_var="$2"
  local api_key=""
  # shellcheck disable=SC2034 # model is set indirectly via deploy_collect_model eval
  local model=""

  # Expert override: if all custom env vars are pre-set, skip the menu
  if [[ "${DEPLOY_LLM_PROVIDER:-}" == "custom" ]] \
     && [[ -n "${DEPLOY_LLM_BASE_URL:-}" ]] \
     && [[ -n "${DEPLOY_API_KEY:-}" ]]; then
    eval "$api_key_var=\"\$DEPLOY_API_KEY\""
    eval "$model_var=''"
    return 0
  fi

  printf '\nWhich AI provider should power your agent?\n' >&2
  printf '  ┌───┬────────────────┬──────────────────────────────┐\n' >&2
  printf '  │ # │ Provider       │ URL                          │\n' >&2
  printf '  ├───┼────────────────┼──────────────────────────────┤\n' >&2
  printf '  │ 1 │ OpenRouter     │ openrouter.ai                │\n' >&2
  printf '  │ 2 │ Nous Portal    │ portal.nousresearch.com      │\n' >&2
  printf '  └───┴────────────────┴──────────────────────────────┘\n' >&2

  local provider_choice
  while true; do
    printf 'Choice [1]: ' >&2
    IFS= read -r provider_choice
    [[ -z "$provider_choice" ]] && provider_choice=1
    case "$provider_choice" in
      1 | 2) break ;;
      *) printf 'Invalid choice. Please enter 1 or 2.\n' >&2 ;;
    esac
  done

  case "$provider_choice" in
    2)
      DEPLOY_LLM_PROVIDER="nous"
      export DEPLOY_LLM_PROVIDER

      printf '\nGet your API key at: https://portal.nousresearch.com\n\n' >&2
      while [[ -z "$api_key" ]]; do
        ui_ask_secret 'Nous API key (required):' api_key
        if [[ -z "$api_key" ]]; then
          printf 'API key cannot be empty.\n' >&2
        fi
      done

      # Validate key via Nous API
      printf 'Verifying Nous API key...\n' >&2
      while ! deploy_validate_nous_key "$api_key"; do
        printf 'Error: Nous Portal rejected this key. Check it and try again.\n' >&2
        ui_ask_secret 'Nous API key (required):' api_key
      done

      eval "$api_key_var=\"\$api_key\""
      eval "$model_var=''"
      ;;
    1)
      DEPLOY_LLM_PROVIDER="openrouter"
      export DEPLOY_LLM_PROVIDER

      printf '\nGet your API key at: https://openrouter.ai/settings/keys\n\n' >&2
      while [[ -z "$api_key" ]]; do
        ui_ask_secret 'OpenRouter API key (required):' api_key
        if [[ -z "$api_key" ]]; then
          printf 'API key cannot be empty.\n' >&2
        fi
      done

      # Validate key via OpenRouter API
      printf 'Verifying OpenRouter API key...\n' >&2
      while ! deploy_validate_openrouter_key "$api_key"; do
        printf 'Error: OpenRouter rejected this key. Check it and try again.\n' >&2
        ui_ask_secret 'OpenRouter API key (required):' api_key
      done

      # Assign API key before model selection (model selection needs it)
      eval "$api_key_var=\"\$api_key\""

      # Model selection (dynamic or static fallback)
      # Check return code to propagate failures (e.g., EOF in fallback)
      if ! deploy_collect_model "$api_key" model; then
        return 1
      fi

      eval "$model_var=\"\$model\""

      # Reasoning effort selection (only for reasoning-capable models)
      # Exit codes from reasoning_prompt_effort:
      #   0 = valid selection, 1 = EOF/cancel, 2 = retry exhaustion
      if reasoning_model_supports_reasoning "$model"; then
        local effort
        local prompt_rc=0
        effort="$(reasoning_prompt_effort "$model")" || prompt_rc=$?
        if [[ "$prompt_rc" -eq 0 ]]; then
          DEPLOY_REASONING_EFFORT="$effort"
          export DEPLOY_REASONING_EFFORT
        elif [[ "$prompt_rc" -eq 1 ]]; then
          # EOF/cancel: fall back to default (user dismissed prompt)
          local family
          family="$(reasoning_normalize_family "$model")"
          DEPLOY_REASONING_EFFORT="$(reasoning_get_default "$family")"
          export DEPLOY_REASONING_EFFORT
          ui_warn "Using default reasoning effort: ${DEPLOY_REASONING_EFFORT}"
        else
          # Retry exhaustion (exit code 2): abort config collection
          ui_warn "Reasoning effort selection failed after too many invalid attempts."
          return 1
        fi
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------
# deploy_collect_model API_KEY RESULT_VAR — pick an OpenRouter model
# Uses provider-first dynamic selection via openrouter_setup_with_models.
# Falls back to manual entry if fetch fails.
# --------------------------------------------------------------------------
deploy_collect_model() {
  local api_key="${1:?Usage: deploy_collect_model API_KEY RESULT_VAR}"
  local result_var="${2:?Usage: deploy_collect_model API_KEY RESULT_VAR}"

  # Use the new openrouter module for provider-first dynamic selection
  local selected_model
  selected_model="$(openrouter_setup_with_models "$api_key")" || return $?

  eval "$result_var=\"\$selected_model\""
}

# --------------------------------------------------------------------------
# deploy_validate_openrouter_key KEY — validate via /api/v1/key endpoint
# Warns if free tier with no usage. Returns 1 on invalid key.
# --------------------------------------------------------------------------
deploy_validate_openrouter_key() {
  local api_key="$1"
  local response
  response="$(curl -sf --max-time 10 "https://openrouter.ai/api/v1/key" \
    -H "Authorization: Bearer ${api_key}" 2>/dev/null)" || return 1
  printf '%s' "$response" | grep -q '"error"' && return 1

  local is_free_tier="false" usage=""
  if printf '%s' "$response" | grep -q '"is_free_tier"[[:space:]]*:[[:space:]]*true'; then
    is_free_tier="true"
  fi
  usage="$(printf '%s' "$response" | grep -oE '"usage"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' | head -1)"

  if [[ "$is_free_tier" == "true" ]] && [[ "${usage:-1}" == "0" ]]; then
    printf 'Warning: OpenRouter account appears to be on free tier with no usage. Add credits at https://openrouter.ai/credits\n' >&2
  fi
  return 0
}

# --------------------------------------------------------------------------
# deploy_validate_nous_key KEY — validate Nous API key via portal
# Returns 0 on valid, 1 on auth failure. Warns on timeout/error.
# --------------------------------------------------------------------------
deploy_validate_nous_key() {
  local api_key="$1"
  local http_code exit_code=0
  http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://api.nousresearch.com/v1/models" \
    -H "Authorization: Bearer ${api_key}" 2>/dev/null)" || exit_code=$?

  # Network/timeout error (curl failed before getting HTTP response)
  if [[ $exit_code -ne 0 ]]; then
    printf 'Warning: Could not verify Nous API key (connection issue).\n' >&2
    if ui_confirm "Continue with this key anyway?"; then
      return 0
    fi
    return 1
  fi

  # Auth failure: hard reject, no bypass
  if [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
    return 1
  fi

  # Server error: transient, offer bypass
  if [[ "$http_code" -ge 500 ]]; then
    printf 'Warning: Nous server error (HTTP %s). This may be temporary.\n' "$http_code" >&2
    if ui_confirm "Continue with this key anyway?"; then
      return 0
    fi
    return 1
  fi

  # Any other non-2xx: reject (e.g., 429 rate limit, 404)
  if [[ "$http_code" -lt 200 ]] || [[ "$http_code" -ge 300 ]]; then
    return 1
  fi

  return 0
}

# --------------------------------------------------------------------------
# deploy_collect_config — orchestrate all configuration collection
# Stores results in exported DEPLOY_* global variables.
# --------------------------------------------------------------------------
deploy_collect_config() {
  ui_banner "Hermes Agent Deploy Configuration"

  deploy_collect_org DEPLOY_ORG
  deploy_collect_app_name DEPLOY_APP_NAME
  deploy_collect_region DEPLOY_REGION
  deploy_collect_vm_size DEPLOY_VM_SIZE DEPLOY_VM_MEMORY
  deploy_collect_volume_size DEPLOY_VOLUME_SIZE
  deploy_collect_llm_config DEPLOY_API_KEY DEPLOY_MODEL

  export DEPLOY_ORG DEPLOY_APP_NAME DEPLOY_REGION DEPLOY_VM_SIZE DEPLOY_VM_MEMORY
  export DEPLOY_VOLUME_SIZE DEPLOY_API_KEY DEPLOY_MODEL
  # DEPLOY_REASONING_EFFORT is set inside deploy_collect_llm_config if applicable

  # Messaging setup
  local msg_choice
  msg_choice="$(messaging_setup_menu)"

  case "$msg_choice" in
    telegram)
      messaging_setup_telegram
      ;;
    *)
      : # skip messaging
      ;;
  esac

  # Confirmation summary
  printf '\n--- Deployment Summary ---\n' >&2
  printf '  App name:    %s\n' "$DEPLOY_APP_NAME" >&2
  printf '  Region:      %s\n' "$DEPLOY_REGION" >&2
  printf '  VM size:     %s / %s\n' "$DEPLOY_VM_SIZE" "$DEPLOY_VM_MEMORY" >&2
  printf '  Volume:      %s GB\n' "$DEPLOY_VOLUME_SIZE" >&2
  printf '  Model:       %s\n' "$DEPLOY_MODEL" >&2
  if [[ -n "${DEPLOY_REASONING_EFFORT:-}" ]]; then
    printf '  Reasoning:   %s\n' "$DEPLOY_REASONING_EFFORT" >&2
  fi
  if [[ -n "${DEPLOY_TELEGRAM_BOT_TOKEN:-}" ]]; then
    printf '  Messaging:   Telegram (configured)\n' >&2
  else
    printf '  Messaging:   none (configure later)\n' >&2
  fi
  printf '\n' >&2

  if ! ui_confirm "Proceed with deployment?"; then
    ui_info "Deployment cancelled."
    return 1
  fi

  return 0
}

# ==========================================================================
# Step 4.3: Execution Pipeline
# ==========================================================================

# --------------------------------------------------------------------------
# deploy_create_build_context — generate Dockerfile and fly.toml
# Sets DEPLOY_BUILD_DIR global variable.
# --------------------------------------------------------------------------
deploy_create_build_context() {
  local build_dir hermes_ref
  build_dir="$(docker_get_build_dir)"
  hermes_ref="$(deploy_resolve_hermes_ref)"

  # M3: export ref before first failure point for diagnostics
  DEPLOY_HERMES_AGENT_REF="$hermes_ref"
  export DEPLOY_HERMES_AGENT_REF

  if ! docker_generate_dockerfile \
    "$build_dir" \
    "$hermes_ref" \
    "${DEPLOY_CHANNEL:-stable}" \
    "${REASONING_SNAPSHOT_VERSION:-unknown}"; then
    ui_error "Failed to generate Dockerfile"
    return 1
  fi

  if ! docker_generate_fly_toml "$build_dir" \
    "$DEPLOY_APP_NAME" "$DEPLOY_REGION" \
    "$DEPLOY_VM_SIZE" "$DEPLOY_VM_MEMORY" \
    "hermes_data" "${DEPLOY_VOLUME_SIZE}gb"; then
    ui_error "Failed to generate fly.toml"
    return 1
  fi

  if ! docker_generate_entrypoint "$build_dir"; then
    ui_error "Failed to generate entrypoint.sh"
    return 1
  fi

  DEPLOY_BUILD_DIR="$build_dir"
  export DEPLOY_BUILD_DIR
  return 0
}

# --------------------------------------------------------------------------
# deploy_provision_resources — create app, volume, set secrets
# --------------------------------------------------------------------------
deploy_provision_resources() {
  local total=3

  ui_step 1 "$total" "Creating Fly app '${DEPLOY_APP_NAME}'"
  if [[ "${DEPLOY_APP_CREATED:-}" != "1" ]]; then
    local create_output
    if ! create_output="$(fly_retry 3 fly_create_app "$DEPLOY_APP_NAME" "${DEPLOY_ORG:-}" 2>&1)"; then
      ui_error "Failed to create app '${DEPLOY_APP_NAME}'"
      if printf '%s' "$create_output" | grep -qiE 'already (exists|been taken)'; then
        printf '  Hint: app name may already be taken. Try a more unique name.\n' >&2
        printf '  Tip: use the default generated name (hermes-<user>-XXX) for uniqueness.\n' >&2
      else
        printf '  Details: %s\n' "$(printf '%s' "$create_output" | head -1)" >&2
      fi
      return 1
    fi
  fi

  ui_step 2 "$total" "Creating volume (${DEPLOY_VOLUME_SIZE} GB)"
  local volume_output
  if ! volume_output="$(fly_retry 3 fly_create_volume "$DEPLOY_APP_NAME" "hermes_data" "$DEPLOY_VOLUME_SIZE" "$DEPLOY_REGION" 2>&1)"; then
    ui_error "Failed to create volume"
    printf '  Details: %s\n' "$(printf '%s' "$volume_output" | head -1)" >&2
    return 1
  fi

  ui_step 3 "$total" "Setting secrets"
  local secrets=()

  case "${DEPLOY_LLM_PROVIDER:-openrouter}" in
    nous)
      secrets+=("NOUS_API_KEY=${DEPLOY_API_KEY}")
      ;;
    custom)
      secrets+=("LLM_BASE_URL=${DEPLOY_LLM_BASE_URL}" "LLM_API_KEY=${DEPLOY_API_KEY}")
      ;;
    *)
      secrets+=("OPENROUTER_API_KEY=${DEPLOY_API_KEY}" "LLM_MODEL=${DEPLOY_MODEL}")
      ;;
  esac

  # Add reasoning effort if set (AC-05)
  if [[ -n "${DEPLOY_REASONING_EFFORT:-}" ]]; then
    secrets+=("HERMES_REASONING_EFFORT=${DEPLOY_REASONING_EFFORT}")
  fi

  # Add app identity
  secrets+=("HERMES_APP_NAME=${DEPLOY_APP_NAME}")

  # Add gateway config if set
  if [[ -n "${DEPLOY_GATEWAY_ALLOW_ALL_USERS:-}" ]]; then
    secrets+=("GATEWAY_ALLOW_ALL_USERS=${DEPLOY_GATEWAY_ALLOW_ALL_USERS}")
  fi
  if [[ -n "${DEPLOY_TELEGRAM_HOME_CHANNEL:-}" ]]; then
    secrets+=("TELEGRAM_HOME_CHANNEL=${DEPLOY_TELEGRAM_HOME_CHANNEL}")
  fi

  # Add messaging secrets if configured
  if [[ -n "${DEPLOY_TELEGRAM_BOT_TOKEN:-}" ]]; then
    secrets+=("TELEGRAM_BOT_TOKEN=${DEPLOY_TELEGRAM_BOT_TOKEN}")
    if [[ -n "${DEPLOY_TELEGRAM_ALLOWED_USERS:-}" ]]; then
      secrets+=("TELEGRAM_ALLOWED_USERS=${DEPLOY_TELEGRAM_ALLOWED_USERS}")
    fi
  fi

  # Add provenance metadata so runtime manifest can be written on boot (PR-04)
  secrets+=("HERMES_FLY_VERSION=${HERMES_FLY_VERSION:-}")
  secrets+=("HERMES_AGENT_REF=${DEPLOY_HERMES_AGENT_REF:-}")
  secrets+=("HERMES_DEPLOY_CHANNEL=${DEPLOY_CHANNEL:-stable}")
  secrets+=("HERMES_LLM_PROVIDER=${DEPLOY_LLM_PROVIDER:-}")
  if [[ -n "${REASONING_SNAPSHOT_VERSION:-}" ]]; then
    secrets+=("HERMES_COMPAT_POLICY=${REASONING_SNAPSHOT_VERSION}")
  fi

  local secrets_output
  if ! secrets_output="$(fly_retry 3 fly_set_secrets "$DEPLOY_APP_NAME" "${secrets[@]}" 2>&1)"; then
    ui_error "Failed to set secrets"
    printf '  Details: %s\n' "$(printf '%s' "$secrets_output" | head -1)" >&2
    return 1
  fi

  ui_success "Resources provisioned"
  return 0
}

# --------------------------------------------------------------------------
# deploy_run_deploy — run fly deploy with optional timeout
# Uses DEPLOY_TIMEOUT if set (default: 5m0s).
# --------------------------------------------------------------------------
deploy_is_transient_transport_error() {
  local text="$1"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  [[ "$lower" == *"connection closed"* ]] && return 0
  [[ "$lower" == *"unexpected eof"* ]] && return 0
  [[ "$lower" == *"context canceled"* ]] && return 0
  [[ "$lower" == *"connection reset by peer"* ]] && return 0
  [[ "$lower" == *"broken pipe"* ]] && return 0

  return 1
}

_deploy_extract_region_from_status() {
  local status_json="$1"
  printf '%s' "$status_json" | tr -d '\n' | \
    sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

deploy_remote_appears_running() {
  local app_name="$1"
  local status_json

  status_json="$(fly_status "$app_name" 2>/dev/null)" || return 1

  local app_status
  app_status="$(printf '%s' "$status_json" | tr -d '\n' | \
    sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  local machine_state
  machine_state="$(printf '%s' "$status_json" | tr -d '\n' | \
    grep -oE '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | \
    sed 's/.*"state"[[:space:]]*:[[:space:]]*"//;s/"//')"

  case "${app_status:-}" in
    running | deployed | started) return 0 ;;
  esac

  case "${machine_state:-}" in
    running | started) return 0 ;;
  esac

  return 1
}

deploy_run_deploy() {
  ui_info "Deploying ${DEPLOY_APP_NAME}..."

  local deploy_output
  if deploy_output="$(fly_retry 3 fly_deploy "$DEPLOY_APP_NAME" "$DEPLOY_BUILD_DIR" "${DEPLOY_TIMEOUT:-5m0s}" 2>&1)"; then
    ui_success "Deployment complete"
    return 0
  fi

  # A dropped CLI stream can still result in a healthy remote deployment.
  if deploy_is_transient_transport_error "$deploy_output"; then
    ui_warn "Deploy connection dropped before completion was confirmed."

    if deploy_remote_appears_running "$DEPLOY_APP_NAME"; then
      ui_warn "Remote status indicates the app is running; resuming deploy flow."
      ui_success "Deployment complete (recovered)"
      return 0
    fi

    ui_warn "Remote status is not healthy yet."
    if ui_confirm "Retry deployment now?"; then
      if deploy_output="$(fly_retry 2 fly_deploy "$DEPLOY_APP_NAME" "$DEPLOY_BUILD_DIR" "${DEPLOY_TIMEOUT:-5m0s}" 2>&1)"; then
        ui_success "Deployment complete"
        return 0
      fi
    fi

    printf '  Resume when your connection is stable:\n' >&2
    printf '    hermes-fly resume -a %s\n' "$DEPLOY_APP_NAME" >&2
  fi

  ui_error "Deployment failed"

  # Show error excerpt
  if [[ -n "$deploy_output" ]]; then
    printf '  Error output:\n' >&2
    printf '%s\n' "$deploy_output" | tail -5 | sed 's/^/    /' >&2
  fi

  # Check machine state for additional context
  local status_json
  if status_json="$(fly_status "$DEPLOY_APP_NAME" 2>/dev/null)"; then
    local machine_state
    machine_state="$(printf '%s' "$status_json" | tr -d '\n' | grep -oE '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"state"[[:space:]]*:[[:space:]]*"//;s/"//')"
    if [[ -n "$machine_state" ]] && [[ "$machine_state" != "started" ]] && [[ "$machine_state" != "running" ]]; then
      printf '  Machine state: %s\n' "$machine_state" >&2
    fi
  fi

  # Suggest diagnostics
  printf '\n  Troubleshooting:\n' >&2
  printf '    hermes-fly logs    — view recent app logs\n' >&2
  printf '    hermes-fly doctor  — run full diagnostics\n' >&2

  return 1
}

# --------------------------------------------------------------------------
# deploy_post_deploy_check — verify app is running after deploy
# Returns: 0 if running, 1 if not
# --------------------------------------------------------------------------
deploy_post_deploy_check() {
  local max_checks=3
  local check_num=1
  local wait_time=3

  while ((check_num <= max_checks)); do
    ui_info "Check ${check_num}/${max_checks}: Checking deployment status..."
    local status_json

    if ! status_json="$(fly_status "$DEPLOY_APP_NAME" 2>&1)"; then
      ui_error "Failed to get status for '${DEPLOY_APP_NAME}'"
      return 1
    fi

    local app_status
    app_status="$(echo "$status_json" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

    if [[ "$app_status" == "running" ]] || [[ "$app_status" == "deployed" ]] || [[ "$app_status" == "started" ]]; then
      ui_success "App is running"
      # Soft HTTP probe — informational only, never fails the deploy
      local hostname
      hostname="$(echo "$status_json" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4)"
      if [[ -n "$hostname" ]]; then
        if curl -fsS --max-time 5 "https://${hostname}/" &>/dev/null; then
          ui_success "HTTP health check passed: https://${hostname}/"
        else
          ui_warn "HTTP health check did not respond yet (app may still be starting)"
        fi
      fi
      return 0
    fi

    ui_warn "App status: ${app_status:-unknown}"

    if ((check_num == max_checks)); then
      break
    fi

    printf '\n  The app is not running yet. This can happen when the machine\n' >&2
    printf '  needs a few seconds to start, or if there is a configuration issue.\n' >&2
    if ui_confirm "  Retry status check? (will wait ${wait_time}s before checking)"; then
      if [[ "${HERMES_FLY_RETRY_SLEEP:-1}" != "0" ]]; then
        sleep "$wait_time"
      fi
      ((wait_time *= 2))
      ((check_num++))
    else
      break
    fi
  done

  # Failed after all checks — show diagnostics, do NOT destroy app
  printf '\n  The deployment completed but the app is not running.\n' >&2
  printf '  Your app and resources have been preserved.\n' >&2
  printf '\n  Troubleshooting:\n' >&2
  printf '    hermes-fly logs    — view recent app logs\n' >&2
  printf '    hermes-fly doctor  — run full diagnostics\n' >&2
  printf '    hermes-fly destroy — remove the app if needed\n' >&2
  return 1
}

# --------------------------------------------------------------------------
# deploy_show_success — display formatted success message
# --------------------------------------------------------------------------
deploy_show_success() {
  local cost
  cost="$(status_estimate_cost "$DEPLOY_VM_SIZE" "$DEPLOY_VOLUME_SIZE" 2>/dev/null || echo "unknown")"

  printf '\n'
  ui_banner "Deployment Successful!"
  printf '\n'
  printf '  App URL:     https://%s.fly.dev\n' "$DEPLOY_APP_NAME"
  printf '  Region:      %s\n' "$DEPLOY_REGION"
  printf '  VM size:     %s\n' "$DEPLOY_VM_SIZE"
  printf '  Volume:      %s GB\n' "$DEPLOY_VOLUME_SIZE"
  printf '  Est. cost:   %s\n' "$cost"
  if [[ -n "${DEPLOY_HERMES_AGENT_REF:-}" ]]; then
    printf '  Hermes ref:  %.8s\n' "$DEPLOY_HERMES_AGENT_REF"
  fi
  if [[ -n "${DEPLOY_TELEGRAM_BOT_USERNAME:-}" ]]; then
    printf '  Telegram:    @%s\n' "$DEPLOY_TELEGRAM_BOT_USERNAME"
    printf '  Chat link:   https://t.me/%s?start=%s\n' "$DEPLOY_TELEGRAM_BOT_USERNAME" "$DEPLOY_APP_NAME"
  fi
  printf '\n'
  printf '  Next steps:\n'
  printf '    - Check app status:  hermes-fly status\n'
  printf '    - View logs:         hermes-fly logs\n'
  printf '    - Run diagnostics:   hermes-fly doctor\n'
  if [[ -z "${DEPLOY_TELEGRAM_BOT_TOKEN:-}" ]]; then
    printf '    - Set up messaging:  hermes-fly messaging\n'
  fi
  printf '\n'
}

# --------------------------------------------------------------------------
# deploy_write_summary — write YAML + Markdown deploy summary files
# --------------------------------------------------------------------------
deploy_write_summary() {
  local deploys_dir="${HERMES_FLY_CONFIG_DIR:-$HOME/.hermes-fly}/deploys"
  mkdir -p "$deploys_dir"
  local app="${DEPLOY_APP_NAME:-}"
  [[ -z "$app" ]] && return 0
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  # Write YAML
  {
    cat <<EOF
app_name: ${app}
region: ${DEPLOY_REGION:-}
url: https://${app}.fly.dev
vm_size: ${DEPLOY_VM_SIZE:-}
volume_size_gb: ${DEPLOY_VOLUME_SIZE:-}
messaging:
  platform: ${DEPLOY_MESSAGING_PLATFORM:-none}
  bot_username: ${DEPLOY_TELEGRAM_BOT_USERNAME:-}
llm:
  model: ${DEPLOY_MODEL:-}
  provider: ${DEPLOY_LLM_PROVIDER:-}
EOF
    if [[ -n "${DEPLOY_REASONING_EFFORT:-}" ]]; then
      printf '  reasoning_effort: %s\n' "${DEPLOY_REASONING_EFFORT}"
    fi
    cat <<EOF
hermes_agent_ref: ${DEPLOY_HERMES_AGENT_REF:-unknown}
deploy_channel: ${DEPLOY_CHANNEL:-stable}
compatibility_policy_version: ${REASONING_SNAPSHOT_VERSION:-}
deployed_at: ${ts}
hermes_fly_version: ${HERMES_FLY_VERSION:-}
management:
  status: "hermes-fly status -a ${app}"
  logs: "hermes-fly logs -a ${app}"
  doctor: "hermes-fly doctor -a ${app}"
  destroy: "hermes-fly destroy -a ${app}"
EOF
  } >"${deploys_dir}/${app}.yaml"
  # Write Markdown
  {
    cat <<EOF
# Hermes Agent: ${app}

Deployed: ${ts}

## Coordinates
- **App URL:** https://${app}.fly.dev
- **Region:** ${DEPLOY_REGION:-}
- **VM size:** ${DEPLOY_VM_SIZE:-}
- **Volume:** ${DEPLOY_VOLUME_SIZE:-} GB
- **Model:** ${DEPLOY_MODEL:-}
- **Hermes ref:** ${DEPLOY_HERMES_AGENT_REF:-unknown}
- **Channel:** ${DEPLOY_CHANNEL:-stable}
EOF
    if [[ -n "${DEPLOY_REASONING_EFFORT:-}" ]]; then
      printf -- '- **Reasoning effort:** %s\n' "${DEPLOY_REASONING_EFFORT}"
    fi
    cat <<EOF
- **Messaging:** ${DEPLOY_MESSAGING_PLATFORM:-none}${DEPLOY_TELEGRAM_BOT_USERNAME:+ (@${DEPLOY_TELEGRAM_BOT_USERNAME})}

## Management
\`\`\`bash
hermes-fly status -a ${app}
hermes-fly logs -a ${app}
hermes-fly doctor -a ${app}
hermes-fly destroy -a ${app}
\`\`\`

## Troubleshooting
- **Bot not responding:** \`hermes-fly doctor -a ${app}\`
- **OpenRouter 401:** rotate key, then \`fly secrets set OPENROUTER_API_KEY=... -a ${app}\`
- **Pairing prompt:** check \`fly ssh console -a ${app}\` pairing directory
- **Telegram logOut 10-min window:** after destroy, wait 10 min before reusing same bot token
EOF
  } >"${deploys_dir}/${app}.md"
}

# --------------------------------------------------------------------------
# deploy_cleanup_on_failure "app_name" — destroy app on partial failure
# Trap-safe: ignores errors from destroy.
# --------------------------------------------------------------------------
deploy_cleanup_on_failure() {
  local app_name="$1"
  if [[ -z "$app_name" ]]; then
    return 0
  fi
  ui_warn "Cleaning up failed deployment..."
  fly_destroy_app "$app_name" >/dev/null 2>&1 || true
  return 0
}

# --------------------------------------------------------------------------
# cmd_deploy_resume [app] — resume verification for an interrupted deploy
# Uses saved app (-a via entrypoint) or current app from config when omitted.
# --------------------------------------------------------------------------
cmd_deploy_resume() {
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    app_name="$(config_get_current_app)"
  fi
  if [[ -z "$app_name" ]]; then
    ui_error "No app specified. Use -a APP or run 'hermes-fly deploy' first."
    return 1
  fi

  DEPLOY_APP_NAME="$app_name"
  ui_info "Resuming deployment checks for ${DEPLOY_APP_NAME}..."

  local status_json
  if ! status_json="$(fly_status "$DEPLOY_APP_NAME" 2>/dev/null)"; then
    ui_error "Could not fetch status for '${DEPLOY_APP_NAME}'"
    return 1
  fi

  local detected_region
  detected_region="$(_deploy_extract_region_from_status "$status_json")"
  if [[ -n "$detected_region" ]]; then
    DEPLOY_REGION="$detected_region"
  fi

  if ! deploy_post_deploy_check; then
    [[ -n "${DEPLOY_REGION:-}" ]] && config_save_app "$DEPLOY_APP_NAME" "$DEPLOY_REGION"
    return 1
  fi

  [[ -n "${DEPLOY_REGION:-}" ]] && config_save_app "$DEPLOY_APP_NAME" "$DEPLOY_REGION"
  ui_success "Resume complete"
  return 0
}

# ==========================================================================
# Step 4.4: Main entry point
# ==========================================================================

# --------------------------------------------------------------------------
# cmd_deploy — full deploy wizard
# Orchestrates preflight, config, build, provision, deploy, verify.
# --------------------------------------------------------------------------
cmd_deploy() {
  # Resolve and export deploy channel early (PR-05)
  # HERMES_FLY_CHANNEL env var or --channel flag (set by entry point) controls this.
  DEPLOY_CHANNEL="$(deploy_resolve_channel)"
  export DEPLOY_CHANNEL

  local app_created=false

  # Preflight
  if ! deploy_preflight; then
    return $?
  fi

  # Collect configuration
  if ! deploy_collect_config; then
    return $?
  fi

  # Create build context
  if ! deploy_create_build_context; then
    return 1
  fi

  # Provision resources (app creation happens here)
  if ! deploy_provision_resources; then
    if [[ "$app_created" == "true" ]]; then
      deploy_cleanup_on_failure "$DEPLOY_APP_NAME"
    fi
    return 1
  fi
  app_created=true

  # Deploy
  if ! deploy_run_deploy; then
    # Keep resources so users can inspect/retry/resume after transient failures.
    config_save_app "$DEPLOY_APP_NAME" "$DEPLOY_REGION"
    ui_warn "Deployment did not complete; resources were preserved for recovery."
    printf '  Resume with: hermes-fly resume -a %s\n' "$DEPLOY_APP_NAME" >&2
    return 1
  fi

  # Post-deploy check (do NOT destroy app on failure — deployment succeeded)
  if ! deploy_post_deploy_check; then
    # Save config so user can run doctor/logs/destroy
    config_save_app "$DEPLOY_APP_NAME" "$DEPLOY_REGION"
    return 1
  fi

  # Success
  deploy_show_success

  # Persist config + deploy summary
  config_save_app "$DEPLOY_APP_NAME" "$DEPLOY_REGION"
  deploy_write_summary

  return 0
}
