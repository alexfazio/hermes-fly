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
    deploy_check_prerequisites || return 1

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
    ui_spinner_stop 1 "Missing prerequisites"
    return 1
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
    ui_spinner_stop 1 "Not authenticated"
    printf 'Run "fly auth login" in another terminal.\n' >&2
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

  local input
  while true; do
    printf 'App name [%s]: ' "$suggestion" >&2
    IFS= read -r input
    if [[ -z "$input" ]]; then
      eval "$varname=\"\$suggestion\""
      return 0
    fi
    if deploy_validate_app_name "$input" 2>/dev/null; then
      eval "$varname=\"\$input\""
      return 0
    fi
    printf 'Invalid app name. ' >&2
  done
}

# --------------------------------------------------------------------------
# deploy_parse_orgs JSON — parse fly orgs list JSON map {"slug":"name",...}
# Sets global arrays: _ORG_SLUGS, _ORG_NAMES
# --------------------------------------------------------------------------
deploy_parse_orgs() {
  local json="$1"
  _ORG_SLUGS=()
  _ORG_NAMES=()

  [[ "$json" == "{}" || -z "$json" ]] && return 0

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
  printf '\nSelect organization:\n' >&2
  printf '  ┌───┬──────────────────────┬──────────────────┐\n' >&2
  printf '  │ # │ Organization         │ Slug             │\n' >&2
  printf '  ├───┼──────────────────────┼──────────────────┤\n' >&2
  local i
  for i in "${!_ORG_SLUGS[@]}"; do
    printf '  │ %d │ %-20s │ %-16s │\n' "$((i + 1))" "${_ORG_NAMES[$i]}" "${_ORG_SLUGS[$i]}" >&2
  done
  printf '  └───┴──────────────────────┴──────────────────┘\n' >&2
  printf 'Choice [1]: ' >&2

  local choice
  IFS= read -r choice
  [[ -z "$choice" ]] && choice=1

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#_ORG_SLUGS[@]})); then
    eval "$varname=\"\${_ORG_SLUGS[$((choice - 1))]}\""
  else
    eval "$varname=\"\${_ORG_SLUGS[0]}\""
  fi
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
# deploy_collect_region VARNAME — select a Fly.io region
# Fetches regions dynamically from fly API, groups by continent.
# Falls back to static list on API failure.
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
  local regions_json
  if regions_json="$(fly_get_regions 2>/dev/null)" && [[ -n "$regions_json" ]]; then
    deploy_parse_regions "$regions_json"
  fi

  # Use fallback if parsing yielded nothing
  if [[ ${#_REGION_CODES[@]} -eq 0 ]]; then
    _REGION_CODES=("${fallback_codes[@]}")
    _REGION_NAMES=("${fallback_names[@]}")
  fi

  # Sort into continent groups maintaining order within each group
  local continent_order=("Americas" "Europe" "Asia-Pacific" "Oceania" "South America" "Africa" "Other")
  local sorted_codes=() sorted_names=() sorted_groups=()
  local continent code i

  for continent in "${continent_order[@]}"; do
    local found=false
    for i in "${!_REGION_CODES[@]}"; do
      code="${_REGION_CODES[$i]}"
      if [[ "$(deploy_get_region_continent "$code")" == "$continent" ]]; then
        if [[ "$found" == "false" ]]; then
          sorted_groups+=("$continent")
          found=true
        else
          sorted_groups+=("")
        fi
        sorted_codes+=("$code")
        sorted_names+=("${_REGION_NAMES[$i]}")
      fi
    done
  done

  printf '\nSelect a region:\n' >&2
  printf '  ┌────┬──────────────────────────────────┬──────┐\n' >&2
  printf '  │ #  │ Location                         │ Code │\n' >&2
  for i in "${!sorted_codes[@]}"; do
    if [[ -n "${sorted_groups[$i]}" ]]; then
      printf '  ├────┼──────────────────────────────────┼──────┤\n' >&2
      printf '  │    │ \033[1m%-32s\033[0m │      │\n' "${sorted_groups[$i]}" >&2
    fi
    printf '  │ %2d │  %-31s │ %s  │\n' "$((i + 1))" "${sorted_names[$i]}" "${sorted_codes[$i]}" >&2
  done
  printf '  └────┴──────────────────────────────────┴──────┘\n' >&2
  printf 'Choice [1]: ' >&2

  local choice
  IFS= read -r choice

  if [[ -z "$choice" ]]; then
    choice=1
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#sorted_codes[@]})); then
    eval "$varname=\"\${sorted_codes[$((choice - 1))]}\""
  else
    eval "$varname=\"\${sorted_codes[0]}\""
  fi
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

  local names_raw mem_raw prices_raw
  names_raw="$(printf '%s' "$json" | grep -oE '"name"\s*:\s*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"
  mem_raw="$(printf '%s' "$json" | grep -oE '"memory_mb"\s*:\s*[0-9]+' | grep -oE '[0-9]+$')"
  prices_raw="$(printf '%s' "$json" | grep -oE '"price_month"\s*:\s*[0-9.]+' | grep -oE '[0-9.]+$')"

  local n_arr=() m_arr=() p_arr=() line
  while IFS= read -r line; do
    [[ -n "$line" ]] && n_arr+=("$line")
  done <<<"$names_raw"
  while IFS= read -r line; do
    [[ -n "$line" ]] && m_arr+=("$line")
  done <<<"$mem_raw"
  while IFS= read -r line; do
    [[ -n "$line" ]] && p_arr+=("$line")
  done <<<"$prices_raw"

  local i
  for i in "${!n_arr[@]}"; do
    _VM_NAMES+=("${n_arr[$i]}")
    _VM_MEMORY+=("${m_arr[$i]:-0}")
    _VM_PRICES+=("${p_arr[$i]:-0}")
  done
}

# --------------------------------------------------------------------------
# deploy_get_vm_recommendation NAME — return recommendation label
# --------------------------------------------------------------------------
deploy_get_vm_recommendation() {
  case "$1" in
    shared-cpu-1x) echo "lightweight testing" ;;
    shared-cpu-2x) echo "recommended for most use" ;;
    performance-1x) echo "multi-tool agents" ;;
    dedicated-cpu-1x) echo "sustained workloads" ;;
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
    performance-1x) echo 1024 ;;
    dedicated-cpu-1x) echo 1024 ;;
    *) echo 0 ;;
  esac
}

_deploy_fallback_price() {
  case "$1" in
    shared-cpu-1x) echo "1.94" ;;
    shared-cpu-2x) echo "3.88" ;;
    performance-1x) echo "12.00" ;;
    dedicated-cpu-1x) echo "23.00" ;;
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

  # Sizes we offer (in display order)
  local wanted=("shared-cpu-1x" "shared-cpu-2x" "performance-1x" "dedicated-cpu-1x")
  local default_idx=2 # 1-based: option 2 = shared-cpu-2x

  # Try dynamic fetch
  _VM_NAMES=()
  _VM_MEMORY=()
  _VM_PRICES=()
  local vm_json
  if vm_json="$(fly_get_vm_sizes 2>/dev/null)" && [[ -n "$vm_json" ]]; then
    deploy_parse_vm_sizes "$vm_json"
  fi

  # Build table rows
  local idx=0 name mem price rec mem_label
  local rows=()
  for name in "${wanted[@]}"; do
    idx=$((idx + 1))
    mem="$(_deploy_lookup_vm "$name" mem)"
    price="$(_deploy_lookup_vm "$name" price)"
    [[ -z "$mem" ]] && mem="$(_deploy_fallback_mem "$name")"
    [[ -z "$price" ]] && price="$(_deploy_fallback_price "$name")"
    rec="$(deploy_get_vm_recommendation "$name")"

    if ((mem >= 1024)); then
      mem_label="$((mem / 1024))gb"
    else
      mem_label="${mem}mb"
    fi

    rows+=("$(printf '%d│%-19s│%-5s│$%-8s│%s' "$idx" "$name" "$mem_label" "$price/mo" "$rec")")
  done

  printf '\nSelect VM size:\n' >&2
  printf '  ┌───┬─────────────────────┬───────┬───────────┬──────────────────────────┐\n' >&2
  printf '  │ # │ VM Size             │ RAM   │ Cost      │ Use Case                 │\n' >&2
  printf '  ├───┼─────────────────────┼───────┼───────────┼──────────────────────────┤\n' >&2
  local row
  for row in "${rows[@]}"; do
    local n vm rm co uc
    IFS='│' read -r n vm rm co uc <<<"$row"
    printf '  │ %s │ %-19s │ %-5s │ %-9s │ %-24s │\n' "$n" "$vm" "$rm" "$co" "$uc" >&2
  done
  printf '  └───┴─────────────────────┴───────┴───────────┴──────────────────────────┘\n' >&2
  printf 'Choice [%d]: ' "$default_idx" >&2

  local choice
  IFS= read -r choice

  if [[ -z "$choice" ]]; then
    choice=$default_idx
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#wanted[@]})); then
    local selected="${wanted[$((choice - 1))]}"
    local sel_mem
    sel_mem="$(_deploy_lookup_vm "$selected" mem)"
    [[ -z "$sel_mem" ]] && sel_mem="$(_deploy_fallback_mem "$selected")"

    if ((sel_mem >= 1024)); then
      eval "$memory_var=\"$((sel_mem / 1024))gb\""
    else
      eval "$memory_var=\"${sel_mem}mb\""
    fi
    eval "$size_var=\"\$selected\""
  else
    eval "$size_var='shared-cpu-2x'"
    eval "$memory_var='512mb'"
  fi
}

# --------------------------------------------------------------------------
# deploy_collect_volume_size VARNAME — select persistent volume size
# Stores numeric GB value (e.g., 1, 5, 10).
# --------------------------------------------------------------------------
deploy_collect_volume_size() {
  local varname="$1"

  local sizes=(1 5 10)
  local labels=("light usage" "recommended" "heavy usage")
  local costs=("0.15" "0.75" "1.50")
  local default_idx=2

  printf '\nSelect volume size:\n' >&2
  printf '  ┌───┬──────┬──────────────┬───────────┐\n' >&2
  printf '  │ # │ Size │ Use Case     │ Cost      │\n' >&2
  printf '  ├───┼──────┼──────────────┼───────────┤\n' >&2
  local i
  for i in "${!sizes[@]}"; do
    printf '  │ %d │ %2d GB │ %-12s │ $%s/mo  │\n' "$((i + 1))" "${sizes[$i]}" "${labels[$i]}" "${costs[$i]}" >&2
  done
  printf '  └───┴──────┴──────────────┴───────────┘\n' >&2
  printf 'Choice [%d]: ' "$default_idx" >&2

  local choice
  IFS= read -r choice

  if [[ -z "$choice" ]]; then
    choice=$default_idx
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#sizes[@]})); then
    eval "$varname=\"\${sizes[$((choice - 1))]}\""
  else
    eval "$varname='5'"
  fi
}

# --------------------------------------------------------------------------
# deploy_collect_llm_config API_KEY_VAR MODEL_VAR — ask for LLM settings
# Presents 3-option provider menu. Sets DEPLOY_LLM_PROVIDER global.
# API key is required (re-prompts). Model has a default for OpenRouter.
# --------------------------------------------------------------------------
deploy_collect_llm_config() {
  local api_key_var="$1" model_var="$2"
  local api_key="" model=""

  printf '\nSelect LLM provider:\n' >&2
  printf '  ┌───┬────────────────┬──────────────────────────────┐\n' >&2
  printf '  │ # │ Provider       │ URL                          │\n' >&2
  printf '  ├───┼────────────────┼──────────────────────────────┤\n' >&2
  printf '  │ 1 │ OpenRouter     │ openrouter.ai                │\n' >&2
  printf '  │ 2 │ Nous Portal    │ portal.nousresearch.com      │\n' >&2
  printf '  │ 3 │ Custom         │ your own endpoint            │\n' >&2
  printf '  └───┴────────────────┴──────────────────────────────┘\n' >&2
  printf 'Choice [1]: ' >&2

  local provider_choice
  IFS= read -r provider_choice

  case "$provider_choice" in
    2)
      DEPLOY_LLM_PROVIDER="nous"
      export DEPLOY_LLM_PROVIDER

      while [[ -z "$api_key" ]]; do
        ui_ask_secret 'Nous API key (from portal.nousresearch.com, required):' api_key
        if [[ -z "$api_key" ]]; then
          printf 'API key cannot be empty.\n' >&2
        fi
      done

      eval "$api_key_var=\"\$api_key\""
      eval "$model_var=''"
      ;;
    3)
      DEPLOY_LLM_PROVIDER="custom"
      export DEPLOY_LLM_PROVIDER

      local base_url=""
      while [[ -z "$base_url" ]]; do
        printf 'LLM base URL (required): ' >&2
        IFS= read -r base_url
        if [[ -z "$base_url" ]]; then
          printf 'Base URL cannot be empty.\n' >&2
        fi
      done

      while [[ -z "$api_key" ]]; do
        ui_ask_secret 'LLM API key (required):' api_key
        if [[ -z "$api_key" ]]; then
          printf 'API key cannot be empty.\n' >&2
        fi
      done

      DEPLOY_LLM_BASE_URL="$base_url"
      export DEPLOY_LLM_BASE_URL
      eval "$api_key_var=\"\$api_key\""
      eval "$model_var=''"
      ;;
    *)
      DEPLOY_LLM_PROVIDER="openrouter"
      export DEPLOY_LLM_PROVIDER

      while [[ -z "$api_key" ]]; do
        ui_ask_secret 'OpenRouter API key (required):' api_key
        if [[ -z "$api_key" ]]; then
          printf 'API key cannot be empty.\n' >&2
        fi
      done

      # Model selection table
      local model_ids=(
        "anthropic/claude-sonnet-4-20250514"
        "anthropic/claude-haiku-4-20250506"
        "google/gemini-2.5-flash"
        "meta-llama/llama-4-maverick"
      )
      local model_labels=(
        "Claude Sonnet 4"
        "Claude Haiku 4"
        "Gemini 2.5 Flash"
        "Llama 4 Maverick"
      )
      local model_notes=(
        "balanced, recommended"
        "fast & affordable"
        "fast alternative"
        "open source"
      )

      printf '\nSelect model:\n' >&2
      printf '  ┌───┬────────────────────┬─────────────────────┐\n' >&2
      printf '  │ # │ Model              │ Notes               │\n' >&2
      printf '  ├───┼────────────────────┼─────────────────────┤\n' >&2
      local mi
      for mi in "${!model_labels[@]}"; do
        printf '  │ %d │ %-18s │ %-19s │\n' "$((mi + 1))" "${model_labels[$mi]}" "${model_notes[$mi]}" >&2
      done
      printf '  │ 5 │ Custom model ID    │ enter manually      │\n' >&2
      printf '  └───┴────────────────────┴─────────────────────┘\n' >&2
      printf 'Choice [1]: ' >&2

      local model_choice
      IFS= read -r model_choice

      if [[ -z "$model_choice" ]]; then
        model_choice=1
      fi

      if [[ "$model_choice" =~ ^[0-9]+$ ]] && ((model_choice >= 1 && model_choice <= ${#model_ids[@]})); then
        model="${model_ids[$((model_choice - 1))]}"
      elif [[ "$model_choice" == "5" ]]; then
        printf 'Model ID (e.g. anthropic/claude-sonnet-4-20250514): ' >&2
        IFS= read -r model
        if [[ -z "$model" ]]; then
          model="${model_ids[0]}"
        fi
      else
        model="${model_ids[0]}"
      fi

      eval "$api_key_var=\"\$api_key\""
      eval "$model_var=\"\$model\""
      ;;
  esac
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

  # Messaging setup
  local msg_choice
  msg_choice="$(messaging_setup_menu)"

  case "$msg_choice" in
    telegram)
      messaging_setup_telegram
      ;;
    discord)
      messaging_setup_discord
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
  if [[ -n "${DEPLOY_TELEGRAM_BOT_TOKEN:-}" ]]; then
    printf '  Messaging:   Telegram (configured)\n' >&2
  elif [[ -n "${DEPLOY_DISCORD_BOT_TOKEN:-}" ]]; then
    printf '  Messaging:   Discord (configured)\n' >&2
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
  local build_dir
  build_dir="$(docker_get_build_dir)"

  if ! docker_generate_dockerfile "$build_dir" "main"; then
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

  # Add messaging secrets if configured
  if [[ -n "${DEPLOY_TELEGRAM_BOT_TOKEN:-}" ]]; then
    secrets+=("TELEGRAM_BOT_TOKEN=${DEPLOY_TELEGRAM_BOT_TOKEN}")
    if [[ -n "${DEPLOY_TELEGRAM_ALLOWED_USERS:-}" ]]; then
      secrets+=("TELEGRAM_ALLOWED_USERS=${DEPLOY_TELEGRAM_ALLOWED_USERS}")
    fi
  fi

  if [[ -n "${DEPLOY_DISCORD_BOT_TOKEN:-}" ]]; then
    secrets+=("DISCORD_BOT_TOKEN=${DEPLOY_DISCORD_BOT_TOKEN}")
    if [[ -n "${DEPLOY_DISCORD_ALLOWED_USERS:-}" ]]; then
      secrets+=("DISCORD_ALLOWED_USERS=${DEPLOY_DISCORD_ALLOWED_USERS}")
    fi
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
deploy_run_deploy() {
  ui_info "Deploying ${DEPLOY_APP_NAME}..."

  if ! fly_retry 3 fly_deploy "$DEPLOY_APP_NAME" "$DEPLOY_BUILD_DIR" "${DEPLOY_TIMEOUT:-5m0s}"; then
    ui_error "Deployment failed"
    return 1
  fi

  ui_success "Deployment complete"
  return 0
}

# --------------------------------------------------------------------------
# deploy_post_deploy_check — verify app is running after deploy
# Returns: 0 if running, 1 if not
# --------------------------------------------------------------------------
deploy_post_deploy_check() {
  ui_info "Checking deployment status..."
  local status_json

  if ! status_json="$(fly_status "$DEPLOY_APP_NAME" 2>&1)"; then
    ui_error "Failed to get status for '${DEPLOY_APP_NAME}'"
    return 1
  fi

  local app_status
  app_status="$(echo "$status_json" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  if [[ "$app_status" == "running" ]] || [[ "$app_status" == "deployed" ]]; then
    ui_success "App is running"
    return 0
  else
    ui_warn "App status: ${app_status:-unknown}"
    return 1
  fi
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
  printf '\n'
  printf '  Next steps:\n'
  printf '    - Check app status:  hermes-fly status\n'
  printf '    - View logs:         hermes-fly logs\n'
  printf '    - Run diagnostics:   hermes-fly doctor\n'
  if [[ -z "${DEPLOY_TELEGRAM_BOT_TOKEN:-}" ]] && [[ -z "${DEPLOY_DISCORD_BOT_TOKEN:-}" ]]; then
    printf '    - Set up messaging:  hermes-fly messaging\n'
  fi
  printf '\n'
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

# ==========================================================================
# Step 4.4: Main entry point
# ==========================================================================

# --------------------------------------------------------------------------
# cmd_deploy — full deploy wizard
# Orchestrates preflight, config, build, provision, deploy, verify.
# --------------------------------------------------------------------------
cmd_deploy() {
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
    deploy_cleanup_on_failure "$DEPLOY_APP_NAME"
    return 1
  fi

  # Post-deploy check
  if ! deploy_post_deploy_check; then
    deploy_cleanup_on_failure "$DEPLOY_APP_NAME"
    return 1
  fi

  # Success
  deploy_show_success

  # Persist config
  config_save_app "$DEPLOY_APP_NAME" "$DEPLOY_REGION"

  return 0
}
