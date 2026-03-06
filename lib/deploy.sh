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
  local total=6

  ui_step 1 "$total" "Checking platform"
  if ! deploy_check_platform; then
    return 1
  fi

  ui_step 2 "$total" "Checking prerequisites"
  if ! deploy_check_prerequisites; then
    return 1
  fi

  ui_step 3 "$total" "Checking fly CLI"
  if ! fly_check_installed; then
    return 1
  fi

  ui_step 4 "$total" "Checking fly version"
  if ! fly_check_version; then
    return 1
  fi

  ui_step 5 "$total" "Checking authentication"
  if ! fly_check_auth_interactive; then
    return "$EXIT_AUTH"
  fi

  ui_step 6 "$total" "Checking connectivity"
  if ! deploy_check_connectivity; then
    return "$EXIT_NETWORK"
  fi

  ui_success "All preflight checks passed"
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
# deploy_collect_region VARNAME — select a Fly.io region
# Parses JSON from fly_get_regions, presents numbered list.
# --------------------------------------------------------------------------
deploy_collect_region() {
  local varname="$1"

  # Curated list of popular regions (covers most use cases)
  local codes=("iad" "ord" "lax" "ams" "fra" "lhr" "nrt" "sin" "syd" "gru")
  local labels=(
    "Washington, D.C. (US East)"
    "Chicago (US Central)"
    "Los Angeles (US West)"
    "Amsterdam (Europe)"
    "Frankfurt (Europe)"
    "London (Europe)"
    "Tokyo (Asia)"
    "Singapore (Asia)"
    "Sydney (Oceania)"
    "São Paulo (South America)"
  )

  printf '\nSelect a region:\n' >&2
  printf '  ┌────┬────────────────────────────────────┬──────┐\n' >&2
  printf '  │ #  │ Location                           │ Code │\n' >&2
  printf '  ├────┼────────────────────────────────────┼──────┤\n' >&2
  local i
  for i in "${!codes[@]}"; do
    printf '  │ %2d │ %-34s │ %s  │\n' "$((i + 1))" "${labels[$i]}" "${codes[$i]}" >&2
  done
  printf '  └────┴────────────────────────────────────┴──────┘\n' >&2
  printf 'Choice [1]: ' >&2

  local choice
  IFS= read -r choice

  if [[ -z "$choice" ]]; then
    choice=1
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#codes[@]})); then
    eval "$varname=\"\${codes[$((choice - 1))]}\""
  else
    eval "$varname=\"\${codes[0]}\""
  fi
}

# --------------------------------------------------------------------------
# deploy_collect_vm_size SIZE_VAR MEMORY_VAR — select VM size
# --------------------------------------------------------------------------
deploy_collect_vm_size() {
  local size_var="$1" memory_var="$2"

  printf '\nSelect VM size:\n' >&2
  printf "  1) shared-cpu-1x / 256mb      (~\$1.94/mo)\n" >&2
  printf "  2) shared-cpu-2x / 512mb      (~\$3.88/mo)\n" >&2
  printf "  3) performance-1x / 1gb       (~\$12.00/mo)\n" >&2
  printf "  4) dedicated-cpu-1x / 1gb     (~\$23.00/mo)\n" >&2
  printf 'Choice [1]: ' >&2

  local choice
  IFS= read -r choice

  case "$choice" in
    2)
      eval "$size_var='shared-cpu-2x'"
      eval "$memory_var='512mb'"
      ;;
    3)
      eval "$size_var='performance-1x'"
      eval "$memory_var='1024mb'"
      ;;
    4)
      eval "$size_var='dedicated-cpu-1x'"
      eval "$memory_var='1024mb'"
      ;;
    *)
      eval "$size_var='shared-cpu-1x'"
      eval "$memory_var='256mb'"
      ;;
  esac
}

# --------------------------------------------------------------------------
# deploy_collect_volume_size VARNAME — select persistent volume size
# Stores numeric GB value (e.g., 1, 5, 10).
# --------------------------------------------------------------------------
deploy_collect_volume_size() {
  local varname="$1"

  printf '\nSelect volume size:\n' >&2
  printf '  1) 1 GB  (light usage)\n' >&2
  printf '  2) 5 GB  (recommended)\n' >&2
  printf '  3) 10 GB (heavy usage)\n' >&2
  printf 'Choice [2]: ' >&2

  local choice
  IFS= read -r choice

  case "$choice" in
    1)
      eval "$varname='1'"
      ;;
    3)
      eval "$varname='10'"
      ;;
    *)
      eval "$varname='5'"
      ;;
  esac
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
  printf '  1) OpenRouter (openrouter.ai)\n' >&2
  printf '  2) Nous Portal (portal.nousresearch.com)\n' >&2
  printf '  3) Custom endpoint\n' >&2
  printf 'Choice [1]: ' >&2

  local provider_choice
  IFS= read -r provider_choice

  case "$provider_choice" in
    2)
      DEPLOY_LLM_PROVIDER="nous"
      export DEPLOY_LLM_PROVIDER

      while [[ -z "$api_key" ]]; do
        printf 'Nous API key (from portal.nousresearch.com, required): ' >&2
        IFS= read -r api_key
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
        printf 'LLM API key (required): ' >&2
        IFS= read -r api_key
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

      local default_model="anthropic/claude-sonnet-4-20250514"

      while [[ -z "$api_key" ]]; do
        printf 'OpenRouter API key (required): ' >&2
        IFS= read -r api_key
        if [[ -z "$api_key" ]]; then
          printf 'API key cannot be empty.\n' >&2
        fi
      done

      printf 'LLM model [%s]: ' "$default_model" >&2
      IFS= read -r model

      if [[ -z "$model" ]]; then
        model="$default_model"
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

  deploy_collect_app_name DEPLOY_APP_NAME
  deploy_collect_region DEPLOY_REGION
  deploy_collect_vm_size DEPLOY_VM_SIZE DEPLOY_VM_MEMORY
  deploy_collect_volume_size DEPLOY_VOLUME_SIZE
  deploy_collect_llm_config DEPLOY_API_KEY DEPLOY_MODEL

  export DEPLOY_APP_NAME DEPLOY_REGION DEPLOY_VM_SIZE DEPLOY_VM_MEMORY
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
  if ! fly_retry 3 fly_create_app "$DEPLOY_APP_NAME" >/dev/null 2>&1; then
    ui_error "Failed to create app '${DEPLOY_APP_NAME}'"
    return 1
  fi

  ui_step 2 "$total" "Creating volume (${DEPLOY_VOLUME_SIZE} GB)"
  if ! fly_retry 3 fly_create_volume "$DEPLOY_APP_NAME" "hermes_data" "$DEPLOY_VOLUME_SIZE" "$DEPLOY_REGION" >/dev/null 2>&1; then
    ui_error "Failed to create volume"
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

  if ! fly_retry 3 fly_set_secrets "$DEPLOY_APP_NAME" "${secrets[@]}" >/dev/null 2>&1; then
    ui_error "Failed to set secrets"
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
