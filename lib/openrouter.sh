#!/usr/bin/env bash
# lib/openrouter.sh — OpenRouter dynamic model fetching and provider-first picker
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source dependencies ---
_OPENROUTER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${EXIT_SUCCESS+x}" ]]; then
  source "${_OPENROUTER_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi

# ==========================================================================
# openrouter_extract_provider — extract provider prefix from model ID
# Args: model_id (e.g., "openai/gpt-5-mini" or "openrouter/aurora-alpha")
# Returns: provider string (e.g., "openai", "openrouter", or "other")
# ==========================================================================
openrouter_extract_provider() {
  local model_id="$1"

  # If model_id contains a slash, extract everything before first slash
  if [[ "$model_id" == */* ]]; then
    printf '%s' "${model_id%%/*}"
  else
    # No slash: group as "other"
    printf '%s' "other"
  fi
}

# ==========================================================================
# openrouter_curated_providers — return list of curated common providers
# Returns: newline-separated provider names in order
# ==========================================================================
openrouter_curated_providers() {
  cat <<'EOF'
openai
anthropic
google
meta-llama
deepseek
mistralai
z-ai
minimax
qwen
EOF
}

# ==========================================================================
# openrouter_fetch_models — fetch /models from OpenRouter with timeout
# Args: api_key, cache_file_path
# Returns: 0 on success, 1+ on failure
# Sets: cache_file with full JSON response
# ==========================================================================
openrouter_fetch_models() {
  local api_key="$1"
  local cache_file="$2"

  [[ -z "$api_key" ]] && return 1
  [[ -z "$cache_file" ]] && return 1

  ui_spinner_start "Fetching available models from OpenRouter..."

  local response
  local status
  response=$(curl -sf \
    -H "Authorization: Bearer ${api_key}" \
    -H "HTTP-Referer: https://github.com/alexfazio/hermes-fly" \
    --max-time 30 \
    "https://openrouter.ai/api/v1/models" 2>/dev/null)
  status=$?

  # Check for curl errors
  if [[ $status -ne 0 ]]; then
    ui_spinner_stop "$status" "Model fetch failed (curl exit $status)"
    return "$status"
  fi

  # Check if response is valid JSON with data array
  if ! echo "$response" | grep -q '"data"'; then
    ui_spinner_stop 1 "Model fetch returned invalid response"
    return 1
  fi

  # Cache the response
  echo "$response" > "$cache_file"

  ui_spinner_stop 0 "Models loaded"
  return 0
}

# ==========================================================================
# openrouter_extract_models_for_provider — extract models for a provider
# Args: cache_file, provider_prefix
# Returns: JSON-like model records (id, name, created)
# Filters: only models matching provider prefix, non-empty ids, deduplicates
# ==========================================================================
openrouter_extract_models_for_provider() {
  local cache_file="$1"
  local provider="$2"

  [[ -z "$cache_file" ]] && return
  [[ ! -f "$cache_file" ]] && return
  [[ -z "$provider" ]] && return

  # Build sed pattern to match models with this provider prefix
  # Handle both "provider/..." and standalone models (provider="other")
  if [[ "$provider" == "other" ]]; then
    # Match IDs without a slash
    grep -o '"id"[[:space:]]*:[[:space:]]*"[^/]*"' "$cache_file" | \
      grep -v '/' | \
      sed 's/"id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/' | sort -u
  else
    # Match IDs starting with "provider/"
    # Use extended grep to match the provider prefix followed by /
    grep -E '"id"[[:space:]]*:[[:space:]]*"'"${provider}"'\/' "$cache_file" | \
      sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u
  fi
}

# ==========================================================================
# _openrouter_get_model_created_timestamp — extract created timestamp
# Args: cache_file, model_id
# Returns: unix timestamp or 0 if not found
# ==========================================================================
_openrouter_get_model_created_timestamp() {
  local cache_file="$1"
  local model_id="$2"

  [[ -z "$cache_file" ]] && return
  [[ ! -f "$cache_file" ]] && return

  # Escape special regex characters in model_id
  local escaped_id
  escaped_id="$(printf '%s' "$model_id" | sed 's/[[\.*^$/]/\\&/g')"

  # Find the model entry and extract created timestamp
  grep -A 3 '"id"[[:space:]]*:[[:space:]]*"'"${escaped_id}"'"' "$cache_file" | \
    grep -o '"created"[[:space:]]*:[[:space:]]*[0-9]*' | \
    head -1 | \
    sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/'
}

# ==========================================================================
# openrouter_sort_models_by_recency — sort model IDs by created timestamp
# Args: model_ids (newline-separated), cache_file (path)
# Returns: sorted model IDs (most recent first)
# Behavior: extracts timestamps from cache, sorts numerically descending
# Bash 3.2 compatible (no associative arrays)
# ==========================================================================
openrouter_sort_models_by_recency() {
  local model_ids="$1"
  local cache_file="${2:-}"

  [[ -z "$model_ids" ]] && return
  [[ -z "$cache_file" ]] && {
    echo "$model_ids"
    return
  }

  # Build "timestamp id" pairs and sort
  local ts_id_pairs=""
  while IFS= read -r model_id; do
    [[ -z "$model_id" ]] && continue
    local ts
    ts="$(_openrouter_get_model_created_timestamp "$cache_file" "$model_id")"
    [[ -z "$ts" ]] && ts="0"
    ts_id_pairs="${ts_id_pairs}${ts} ${model_id}
"
  done <<< "$model_ids"

  # Sort by timestamp descending and extract model ID
  echo "$ts_id_pairs" | sort -rn | awk '{print $2}' | grep -v '^$'
}

# ==========================================================================
# openrouter_build_provider_menu — build interactive provider selection menu
# Args: cache_file
# Returns: selected provider name on stdout
# Behavior: curated providers first, then "Other", then "Manual entry"
# ==========================================================================
openrouter_build_provider_menu() {
  local cache_file="$1"

  [[ -z "$cache_file" ]] && return 1
  [[ ! -f "$cache_file" ]] && return 1

  # Extract all unique providers from cache
  local all_providers
  all_providers=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$cache_file" | \
    sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^/]*\)\/.*/\1/p' | \
    sort -u)

  # Get curated list
  local curated
  curated="$(openrouter_curated_providers)"

  # Build provider menu: curated first, then others
  local menu_items=()

  # Add curated providers (if they exist in the response)
  while IFS= read -r provider; do
    [[ -z "$provider" ]] && continue
    if echo "$all_providers" | grep -q "^${provider}$"; then
      menu_items+=("$provider")
    fi
  done <<< "$curated"

  # Add "Other providers" if there are non-curated providers
  local other_providers
  other_providers=$(echo "$all_providers" | grep -v -f <(echo "$curated") | sort)
  if [[ -n "$other_providers" ]]; then
    # Show a UI message about other providers rather than making the separator selectable
    ui_info "Additional providers available:"
    while IFS= read -r provider; do
      [[ -z "$provider" ]] && continue
      menu_items+=("$provider")
    done <<< "$other_providers"
  fi

  # Add manual entry option
  menu_items+=("Enter model ID manually")

  # Present menu
  ui_select "Select LLM Provider:" SELECTED_PROVIDER "${menu_items[@]}"

  echo "$SELECTED_PROVIDER"
}

# ==========================================================================
# openrouter_build_model_menu — build interactive model selection menu
# Args: cache_file, provider
# Returns: selected model ID on stdout
# Behavior: top 15 most recent, with "Show all" option if more exist
# ==========================================================================
openrouter_build_model_menu() {
  local cache_file="$1"
  local provider="$2"

  [[ -z "$cache_file" ]] && return 1
  [[ -z "$provider" ]] && return 1

  # Extract models for this provider
  local model_ids
  model_ids=$(openrouter_extract_models_for_provider "$cache_file" "$provider")

  if [[ -z "$model_ids" ]]; then
    ui_error "No models found for provider: $provider"
    return 1
  fi

  # Sort by recency (pass cache_file as explicit parameter)
  local sorted_models
  sorted_models=$(openrouter_sort_models_by_recency "$model_ids" "$cache_file")

  # Count total models
  local total_count
  total_count=$(echo "$sorted_models" | wc -l)

  # Take top 15
  local top_models
  top_models=$(echo "$sorted_models" | head -15)

  # Build menu items with display names
  local menu_items=()
  while IFS= read -r model_id; do
    [[ -z "$model_id" ]] && continue
    # Extract display name from cache
    local display_name
    display_name=$(grep -A 1 '"id"[[:space:]]*:[[:space:]]*"'"$(printf '%s' "$model_id" | sed 's/[[\.*^$/]/\\&/g')"'"' "$cache_file" | \
      grep '"name"' | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [[ -z "$display_name" ]] && display_name="$model_id"
    menu_items+=("$display_name [$model_id]")
  done <<< "$top_models"

  # Add "Show all" option if there are more than 15
  if [[ $total_count -gt 15 ]]; then
    menu_items+=("Show all $total_count models")
  fi

  # Present menu
  ui_select "Select Model:" SELECTED_MODEL "${menu_items[@]}"

  # Handle "Show all" selection by presenting full list
  if [[ "$SELECTED_MODEL" == "Show all"* ]]; then
    # Re-present with all models (no limit)
    menu_items=()
    while IFS= read -r model_id; do
      [[ -z "$model_id" ]] && continue
      # Extract display name from cache
      local display_name
      display_name=$(grep -A 1 '"id"[[:space:]]*:[[:space:]]*"'"$(printf '%s' "$model_id" | sed 's/[[\.*^$/]/\\&/g')"'"' "$cache_file" | \
        grep '"name"' | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      [[ -z "$display_name" ]] && display_name="$model_id"
      menu_items+=("$display_name [$model_id]")
    done <<< "$sorted_models"

    # Re-present menu with all models
    ui_select "Select Model (showing all $total_count):" SELECTED_MODEL "${menu_items[@]}"
  fi

  # Extract model ID from selection
  if [[ "$SELECTED_MODEL" == *"["*"]" ]]; then
    # Format: "display name [model-id]"
    echo "$SELECTED_MODEL" | sed -n 's/.*\[\([^]]*\)\].*/\1/p'
  else
    # Fallback: if nothing matched, return empty to trigger manual fallback
    return 1
  fi
}

# ==========================================================================
# openrouter_manual_fallback — prompt user for manual model ID entry
# Args: none
# Returns: model ID on stdout
# Behavior: explains fallback, directs to openrouter.ai/models, validates input
# ==========================================================================
openrouter_manual_fallback() {
  ui_warn "Could not load the model list from OpenRouter."
  ui_info ""
  ui_info "To find a model ID:"
  ui_info "  1. Visit: https://openrouter.ai/models"
  ui_info "  2. Find a model you want to use"
  ui_info "  3. Copy its full model ID (e.g., 'openai/gpt-5-mini')"
  ui_info ""

  local model_id=""
  while [[ -z "$model_id" ]]; do
    ui_ask "Enter model ID:" model_id
    if [[ -z "$model_id" ]]; then
      ui_error "Model ID cannot be empty."
    elif [[ "$model_id" != *"/"* ]]; then
      ui_warn "Model ID should contain a provider prefix (e.g., 'openai/gpt-5')."
    fi
  done

  echo "$model_id"
}

# ==========================================================================
# openrouter_setup_with_models — complete OpenRouter setup flow
# Args: api_key
# Returns: selected model ID on stdout
# Behavior: fetch -> provider selection -> model selection -> return ID
# ==========================================================================
openrouter_setup_with_models() {
  local api_key="$1"

  [[ -z "$api_key" ]] && return 1

  # Create cache file in temp directory
  local cache_file
  cache_file="$(mktemp)" || return 1

  # Note: Using explicit cleanup instead of trap to avoid overwriting caller's trap.
  # Since this function is called via command substitution (subshell), the temp file
  # is isolated and will be cleaned up when the subshell exits.

  # Fetch models
  if ! openrouter_fetch_models "$api_key" "$cache_file"; then
    # Explicit cleanup before fallback
    rm -f "$cache_file"
    # Fallback to manual entry
    openrouter_manual_fallback
    return 0
  fi

  # Check if we got any valid models
  if ! grep -q '"id"' "$cache_file"; then
    rm -f "$cache_file"
    openrouter_manual_fallback
    return 0
  fi

  # Build provider menu
  local selected_provider
  selected_provider=$(openrouter_build_provider_menu "$cache_file")

  if [[ "$selected_provider" == "Enter model ID manually" ]]; then
    rm -f "$cache_file"
    openrouter_manual_fallback
    return 0
  fi

  # Build model menu for selected provider
  local selected_model
  if ! selected_model=$(openrouter_build_model_menu "$cache_file" "$selected_provider"); then
    # Model menu selection failed, fall back to manual entry
    rm -f "$cache_file"
    openrouter_manual_fallback
    return 0
  fi

  # Verify we got a non-empty model ID
  if [[ -z "$selected_model" ]]; then
    rm -f "$cache_file"
    openrouter_manual_fallback
    return 0
  fi

  # Explicit cleanup before returning
  rm -f "$cache_file"

  echo "$selected_model"
}
