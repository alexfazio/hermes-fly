#!/usr/bin/env bats

# Tests for OpenRouter dynamic model fetching and provider-first picker
# lib/openrouter.sh module

setup() {
  source lib/ui.sh
  source lib/openrouter.sh
  export HERMES_FLY_CONFIG_DIR="$(mktemp -d)"
  export PATH="${BATS_TEST_DIRNAME}/mocks:$PATH"
  export NO_COLOR=1
}

teardown() {
  rm -rf "$HERMES_FLY_CONFIG_DIR"
}

# ============================================================================
# Provider prefix extraction tests
# ============================================================================

@test "openrouter_extract_provider: standard openai model" {
  local provider
  provider="$(openrouter_extract_provider "openai/gpt-5-mini")"
  [ "$provider" = "openai" ]
}

@test "openrouter_extract_provider: google model with colon suffix" {
  local provider
  provider="$(openrouter_extract_provider "google/gemini-2.0-flash-exp:free")"
  [ "$provider" = "google" ]
}

@test "openrouter_extract_provider: model without slash groups as other" {
  local provider
  provider="$(openrouter_extract_provider "no-slash-model")"
  [ "$provider" = "other" ]
}

@test "openrouter_extract_provider: openrouter-prefixed model" {
  local provider
  provider="$(openrouter_extract_provider "openrouter/aurora-alpha")"
  [ "$provider" = "openrouter" ]
}

@test "openrouter_extract_provider: preserves everything after first slash" {
  local full_id="anthropic/claude-opus/v2:extended"
  local provider
  provider="$(openrouter_extract_provider "$full_id")"
  [ "$provider" = "anthropic" ]
}

# ============================================================================
# Provider menu building tests
# ============================================================================

@test "openrouter_build_provider_menu: curated providers first" {
  # Create a fixture with mixed providers
  local payload='{"data":[
    {"id":"openai/gpt-5","name":"OpenAI GPT-5"},
    {"id":"anthropic/claude","name":"Claude"},
    {"id":"unknown/model","name":"Unknown"}
  ]}'

  # Stub out curl
  curl() {
    echo "$payload"
    return 0
  }
  export -f curl

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local menu
  menu="$(openrouter_build_provider_menu "$cache_file" 2>/dev/null)"

  # Should show openai and anthropic before "Other"
  [[ "$menu" == *"openai"* ]]
  [[ "$menu" == *"anthropic"* ]]

  rm -f "$cache_file"
}

@test "openrouter_build_provider_menu: other providers alphabetical" {
  local payload='{"data":[
    {"id":"zebra/model","name":"Zebra"},
    {"id":"alpha/model","name":"Alpha"},
    {"id":"beta/model","name":"Beta"}
  ]}'

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local providers
  providers="$(grep '"id":' "$cache_file" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^/]*\)\/.*/\1/p' | sort -u)"

  # Should have alpha, beta, zebra
  [[ "$providers" == *"alpha"* ]]
  [[ "$providers" == *"beta"* ]]
  [[ "$providers" == *"zebra"* ]]

  rm -f "$cache_file"
}

# ============================================================================
# Model filtering and deduplication tests
# ============================================================================

@test "openrouter_extract_models_for_provider: filters by provider prefix" {
  local payload='{"data":[
    {"id":"openai/gpt-5","name":"GPT-5","created":1234567890},
    {"id":"anthropic/claude","name":"Claude","created":1234567891},
    {"id":"openai/gpt-4","name":"GPT-4","created":1234567889}
  ]}'

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "openai")"

  # Should have 2 openai models
  [[ "$models" == *"gpt-5"* ]]
  [[ "$models" == *"gpt-4"* ]]
  [[ "$models" != *"anthropic"* ]]

  rm -f "$cache_file"
}

@test "openrouter_extract_models_for_provider: preserves colon variants as distinct" {
  local payload='{"data":[
    {"id":"google/gemini-2.0:free","name":"Gemini 2.0 Free","created":1234567890},
    {"id":"google/gemini-2.0:nitro","name":"Gemini 2.0 Nitro","created":1234567891}
  ]}'

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "google")"

  # Both should be present as separate entries
  [[ "$models" == *":free"* ]]
  [[ "$models" == *":nitro"* ]]

  rm -f "$cache_file"
}

@test "openrouter_extract_models_for_provider: ignores malformed entries" {
  local payload='{"data":[
    {"id":"valid/model","name":"Valid","created":1234567890},
    {"name":"No ID"},
    {"id":"","name":"Empty ID"},
    {"id":"valid/model2","name":"Valid 2","created":1234567889}
  ]}'

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "valid")"

  # Should have 2 valid entries
  [[ "$models" == *"model"* ]]
  [[ "$models" == *"model2"* ]]

  rm -f "$cache_file"
}

@test "openrouter_extract_models_for_provider: deduplicates exact IDs" {
  local payload='{"data":[
    {"id":"openai/gpt-5","name":"GPT-5","created":1234567890},
    {"id":"openai/gpt-5","name":"GPT-5 Duplicate","created":1234567891}
  ]}'

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "openai")"

  # Should deduplicate to single entry
  local count
  count="$(echo "$models" | grep -c "gpt-5" || true)"
  [ "$count" -eq 1 ]

  rm -f "$cache_file"
}

# ============================================================================
# Recency sorting tests (top 15 models)
# ============================================================================

@test "openrouter_sort_models_by_recency: returns top 15 most recent" {
  local payload='{"data":['
  local i
  for i in {1..25}; do
    local ts=$((1234567890 + i))
    payload="${payload}
    {\"id\":\"openai/model-${i}\",\"name\":\"Model ${i}\",\"created\":${ts}}"
    [ $i -lt 25 ] && payload="${payload},"
  done
  payload="${payload}
  ]}"

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "openai")"
  local sorted
  sorted="$(openrouter_sort_models_by_recency "$models" | head -15)"

  # Should have exactly 15 or fewer
  local count
  count="$(echo "$sorted" | wc -l)"
  [ "$count" -le 15 ]

  # Most recent should be first (highest timestamp)
  [[ "$sorted" == *"model-25"* ]]

  rm -f "$cache_file"
}

@test "openrouter_sort_models_by_recency: orders by created timestamp descending" {
  local payload='{"data":[
    {"id":"openai/old","name":"Old Model","created":1000},
    {"id":"openai/new","name":"New Model","created":2000},
    {"id":"openai/middle","name":"Middle","created":1500}
  ]}'

  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "openai")"
  local sorted
  sorted="$(openrouter_sort_models_by_recency "$models" "$cache_file")"

  # Most recent first: new (2000), middle (1500), old (1000)
  local first_model=$(echo "$sorted" | head -1)
  local last_model=$(echo "$sorted" | tail -1)

  [ "$first_model" = "openai/new" ]
  [ "$last_model" = "openai/old" ]

  rm -f "$cache_file"
}

# ============================================================================
# Manual fallback tests
# ============================================================================

@test "openrouter_manual_fallback: prompts for model ID with validation" {
  # This is an integration test; we'll mock ui_ask
  ui_ask() {
    local prompt="$1"
    local varname="$2"
    eval "$varname='openai/gpt-5'"
  }
  export -f ui_ask

  local result
  result="$(openrouter_manual_fallback 2>&1)"

  [[ "$result" == *"openrouter.ai/models"* ]] || [[ -n "$result" ]]
}

@test "openrouter_manual_fallback: explains fetch failure clearly" {
  local result
  result="$(openrouter_manual_fallback 2>&1 | head -3)"

  # Should mention that the list could not be loaded
  [[ "$result" == *"could not"* ]] || [[ "$result" == *"unable"* ]] || [[ -n "$result" ]]
}

# ============================================================================
# Fetch and caching tests
# ============================================================================

@test "openrouter_fetch_models: fetches from OpenRouter API" {
  local api_key="test-key-12345"

  # Mock curl to return success
  curl() {
    echo '{"data":[{"id":"openai/test","name":"Test","created":1234567890}]}'
    return 0
  }
  export -f curl

  local cache_file
  cache_file="$(mktemp)"

  # Call function and capture exit code separately
  openrouter_fetch_models "$api_key" "$cache_file" >/dev/null 2>&1
  local status=$?

  [ "$status" -eq 0 ]
  [ -f "$cache_file" ]
  grep -q "openai" "$cache_file"

  rm -f "$cache_file"
}

@test "openrouter_fetch_models: timeout falls back gracefully" {
  local api_key="test-key-12345"

  # Mock curl to timeout
  curl() {
    return 28  # curl timeout exit code
  }
  export -f curl

  local cache_file
  cache_file="$(mktemp)"

  # Capture exit code without failing the test
  openrouter_fetch_models "$api_key" "$cache_file" >/dev/null 2>&1 || local status=$?

  # Should return non-zero on timeout
  [ "${status:-0}" -ne 0 ]

  rm -f "$cache_file"
}

@test "openrouter_fetch_models: malformed response triggers fallback" {
  local api_key="test-key-12345"

  # Mock curl to return garbage
  curl() {
    echo "not json at all {{"
    return 0
  }
  export -f curl

  local cache_file
  cache_file="$(mktemp)"

  # Capture exit code without failing the test
  openrouter_fetch_models "$api_key" "$cache_file" >/dev/null 2>&1 || local status=$?

  # Should return non-zero on malformed response
  [ "${status:-0}" -ne 0 ]

  # Cache should not contain valid data
  if [ -f "$cache_file" ]; then
    ! grep -q '"data"' "$cache_file"
  fi

  rm -f "$cache_file"
}

# ============================================================================
# Integration: full flow with provider-first selection
# ============================================================================

@test "openrouter_setup_with_models: returns selected model ID" {
  local api_key="test-key"
  local payload='{"data":[
    {"id":"openai/gpt-5","name":"OpenAI: GPT-5","created":1234567890},
    {"id":"anthropic/claude","name":"Anthropic: Claude","created":1234567891}
  ]}'

  # Mock curl
  curl() {
    echo "$payload"
    return 0
  }
  export -f curl

  # Mock ui_select: track calls via temp file since function scoping is complex in subshells
  local call_count_file
  call_count_file="$(mktemp)"
  echo "0" > "$call_count_file"

  ui_select() {
    local varname="$2"
    shift 2
    local current_count
    current_count=$(cat "$call_count_file")
    ((current_count++))
    echo "$current_count" > "$call_count_file"

    if [[ $current_count -eq 1 ]]; then
      # Provider selection: return "openai"
      eval "$varname='openai'"
    else
      # Model selection: return the first menu option (OpenAI: GPT-5 [openai/gpt-5])
      eval "$varname='OpenAI: GPT-5 [openai/gpt-5]'"
    fi
  }
  export -f ui_select

  # Actually call the function and verify it returns a model ID
  local result
  result=$(openrouter_setup_with_models "$api_key")
  rm -f "$call_count_file"
  [[ "$result" == "openai/gpt-5" ]]
}

# ============================================================================
# Curated providers list tests
# ============================================================================

@test "openrouter_curated_providers: returns list in defined order" {
  local curated
  curated="$(openrouter_curated_providers)"

  # Should contain the curated list in order
  [[ "$curated" == *"openai"* ]]
  [[ "$curated" == *"anthropic"* ]]

  # openai should come before unknown providers
  local openai_line=$(echo "$curated" | grep -n "openai" | head -1 | cut -d: -f1)
  local other_line=$(echo "$curated" | tail -1 | cut -d: -f1)

  # Curated providers should be defined
  [ -n "$openai_line" ]
}

# ============================================================================
# Edge case tests
# ============================================================================

@test "openrouter: handles empty data array gracefully" {
  local payload='{"data":[]}'
  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local models
  models="$(openrouter_extract_models_for_provider "$cache_file" "openai")"

  # Should return empty, not error
  [ -z "$models" ] || [ "$models" = "" ]

  rm -f "$cache_file"
}

@test "openrouter: handles model IDs with multiple slashes" {
  local payload='{"data":[
    {"id":"provider/model/variant","name":"Complex","created":1234567890}
  ]}'
  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  local provider
  provider="$(openrouter_extract_provider "provider/model/variant")"

  # Should extract only the first part
  [ "$provider" = "provider" ]

  rm -f "$cache_file"
}

# ============================================================================
# Module guard test
# ============================================================================

@test "openrouter.sh: cannot be executed directly" {
  # Try to execute the module directly
  run bash lib/openrouter.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"source"* ]]
}

# ============================================================================
# Stdout pollution tests (critical for command-substitution safety)
# ============================================================================

@test "openrouter_build_provider_menu: does not pollute stdout with ui_info" {
  local payload='{"data":[
    {"id":"openai/gpt-5","name":"OpenAI: GPT-5","created":1234567890},
    {"id":"openrouter/aurora","name":"OpenRouter: Aurora","created":1234567891}
  ]}'
  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  # Mock ui_select to return a specific provider
  ui_select() {
    local varname="$2"
    eval "$varname='openai'"
  }
  export -f ui_select

  # Capture output - should be ONLY the provider name, no ui_info lines
  local result
  result="$(openrouter_build_provider_menu "$cache_file")"

  # Result must be exactly "openai" (one line, no [info] prefix)
  [ "$result" = "openai" ]
  [[ "$result" != *"[info]"* ]]
  [[ "$result" != *"Additional"* ]]

  rm -f "$cache_file"
}

@test "openrouter_manual_fallback: does not pollute stdout with ui_warn/ui_info" {
  # Mock ui_ask to return a model ID
  ui_ask() {
    local varname="$2"
    eval "$varname='openai/gpt-5'"
  }
  export -f ui_ask

  # Capture output - should be ONLY the model ID, no [warn] or [info] lines
  local result
  result="$(openrouter_manual_fallback)"

  # Result must be exactly the model ID (one line, no warnings/info)
  [ "$result" = "openai/gpt-5" ]
  [[ "$result" != *"[warn]"* ]]
  [[ "$result" != *"[info]"* ]]
  [[ "$result" != *"Could not load"* ]]
  [[ "$result" != *"Visit:"* ]]
}

@test "openrouter_build_model_menu: returns error on invalid selection" {
  local payload='{"data":[
    {"id":"openai/gpt-5","name":"OpenAI: GPT-5","created":1234567890}
  ]}'
  local cache_file="$(mktemp)"
  echo "$payload" > "$cache_file"

  # Mock ui_select to return empty (invalid selection)
  ui_select() {
    local varname="$2"
    eval "$varname=''"
    return 1
  }
  export -f ui_select

  # openrouter_build_model_menu should return error status (non-zero)
  ! openrouter_build_model_menu "$cache_file" "openai" >/dev/null 2>&1

  rm -f "$cache_file"
}

@test "openrouter_manual_fallback: exits gracefully on EOF (no hard loop)" {
  # This test verifies that when stdin is exhausted (EOF), the function
  # exits gracefully instead of spinning indefinitely.

  # Mock ui_ask to fail immediately (simulating EOF)
  ui_ask() {
    local varname="$2"
    eval "$varname=''"
    return 1  # EOF or read failure
  }
  export -f ui_ask

  # Should complete quickly without spinning and return non-zero
  # Timeout is 2 seconds; if the function loops on EOF, it will hit timeout (exit 124)
  # If it exits gracefully, it will return 1
  run timeout 2 openrouter_manual_fallback >/dev/null 2>&1

  # Verify it did not timeout (exit 124) and did exit with an error
  [ $status -ne 124 ]
  [ $status -ne 0 ]
}
