#!/usr/bin/env bats
# tests/deploy.bats — TDD tests for lib/deploy.sh deploy wizard

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  export HERMES_FLY_RETRY_SLEEP=0
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/fly-helpers.sh"
  source "${PROJECT_ROOT}/lib/docker-helpers.sh"
  source "${PROJECT_ROOT}/lib/messaging.sh"
  source "${PROJECT_ROOT}/lib/config.sh"
  source "${PROJECT_ROOT}/lib/status.sh"
  source "${PROJECT_ROOT}/lib/deploy.sh"
}

teardown() {
  _common_teardown
}

# --- deploy_check_platform ---

@test "deploy_check_platform returns 0 on Darwin" {
  export HERMES_FLY_PLATFORM="Darwin"
  run deploy_check_platform
  assert_success
}

@test "deploy_check_platform exits 1 on Windows" {
  export HERMES_FLY_PLATFORM="MINGW64_NT"
  run deploy_check_platform
  assert_failure
  assert [ "$status" -eq 1 ]
}

# --- deploy_check_prerequisites ---

@test "deploy_check_prerequisites returns 0 when all present" {
  # fly, git, curl are all mocks on PATH
  run deploy_check_prerequisites
  assert_success
}

@test "deploy_check_prerequisites fails naming missing tool" {
  # Remove mocks from PATH so fly is not found
  PATH="/usr/bin:/bin"
  run deploy_check_prerequisites
  assert_failure
  assert_output --partial "fly"
}

# --- deploy_check_connectivity ---

@test "deploy_check_connectivity returns 0 when online" {
  run deploy_check_connectivity
  assert_success
}

@test "deploy_check_connectivity exits 3 when offline" {
  export MOCK_CURL_FAIL=true
  run deploy_check_connectivity
  assert_failure
  assert [ "$status" -eq 3 ]
}

# --- deploy_collect_app_name ---

@test "deploy_collect_app_name uses suggestion on empty input" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_app_name RESULT <<< "" 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output --partial "hermes-"
}

@test "deploy_collect_app_name uses custom input" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_app_name RESULT <<< "my-hermes" 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "my-hermes"
}

@test "deploy_collect_app_name re-prompts when app name is taken" {
  run bash -c '
    export NO_COLOR=1
    export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"
    source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh
    source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh
    fly_create_app() {
      if [[ "$1" == "taken-name" ]]; then
        echo "Name has already been taken" >&2
        return 1
      fi
      echo "{\"name\":\"$1\",\"status\":\"pending\"}"
      return 0
    }
    deploy_collect_app_name RESULT <<< "$(printf "taken-name\ngood-name\n")" 2>/dev/null
    echo "$RESULT"
  '
  assert_success
  assert_output "good-name"
}

@test "deploy_collect_app_name sets DEPLOY_APP_CREATED on success" {
  run bash -c '
    export NO_COLOR=1
    export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"
    source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh
    source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh
    deploy_collect_app_name RESULT <<< "my-hermes" 2>/dev/null
    echo "RESULT=$RESULT CREATED=${DEPLOY_APP_CREATED:-0}"
  '
  assert_success
  assert_output "RESULT=my-hermes CREATED=1"
}

@test "deploy_collect_app_name accepts name on non-availability error" {
  run bash -c '
    export NO_COLOR=1
    export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"
    source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh
    source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh
    fly_create_app() {
      echo "network timeout" >&2
      return 1
    }
    deploy_collect_app_name RESULT <<< "my-hermes" 2>/dev/null
    echo "RESULT=$RESULT CREATED=${DEPLOY_APP_CREATED:-0}"
  '
  assert_success
  assert_output "RESULT=my-hermes CREATED=0"
}

# --- deploy_collect_vm_size ---

@test "deploy_collect_vm_size selects first option" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>/dev/null; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output "SIZE=shared-cpu-1x MEM=256mb"
}

@test "deploy_collect_vm_size default selects recommended option 2" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "" 2>/dev/null; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output "SIZE=shared-cpu-2x MEM=512mb"
}

@test "deploy_collect_vm_size option 4 selects dedicated-cpu-1x" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "4" 2>/dev/null; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output --partial "SIZE=dedicated-cpu-1x"
}

# --- deploy_collect_volume_size ---

@test "deploy_collect_volume_size selects recommended" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_volume_size VSIZE <<< "2" 2>/dev/null; echo "$VSIZE"'
  assert_success
  assert_output "5"
}

@test "deploy_collect_volume_size renders as box-drawing table" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_volume_size VSIZE <<< "1" 2>&1; echo "$VSIZE"'
  assert_success
  assert_output --partial "┌"
  assert_output --partial "┘"
  assert_output --partial "Size"
  assert_output --partial "recommended"
}

# --- deploy_create_build_context ---

@test "deploy_create_build_context generates files" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VM_SIZE="shared-cpu-1x"
  export DEPLOY_VM_MEMORY="256mb"
  export DEPLOY_VOLUME_SIZE="5"
  run deploy_create_build_context
  assert_success
  # DEPLOY_BUILD_DIR is set inside the subshell of run, so we run again to check files
  deploy_create_build_context
  assert [ -f "${DEPLOY_BUILD_DIR}/Dockerfile" ]
  assert [ -f "${DEPLOY_BUILD_DIR}/fly.toml" ]
  assert [ -f "${DEPLOY_BUILD_DIR}/entrypoint.sh" ]
  rm -rf "${DEPLOY_BUILD_DIR}"
}

# --- deploy_collect_org ---

@test "deploy_collect_org auto-selects single org silently" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG 2>&1; echo "ORG=$DEPLOY_ORG"'
  assert_success
  assert_output --partial "ORG=personal"
  refute_output --partial "Select organization"
}

@test "deploy_collect_org shows table for multiple orgs" {
  export MOCK_FLY_ORGS_JSON='{"personal":"Personal","my-team":"My Team"}'
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Personal","my-team":"My Team"}'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG < <(printf "1\n") 2>&1; echo "ORG=$DEPLOY_ORG"'
  assert_success
  assert_output --partial "Select organization"
  assert_output --partial "my-team"
  assert_output --partial "ORG=personal"
}

@test "deploy_collect_org selects second org from table" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Personal","my-team":"My Team"}'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG < <(printf "2\n") 2>&1; echo "ORG=$DEPLOY_ORG"'
  assert_success
  assert_output --partial "ORG=my-team"
}

@test "deploy_collect_org fails on API error" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS=fail; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG 2>&1'
  assert_failure
  assert_output --partial "Failed to fetch"
}

# --- deploy_provision_resources ---

@test "deploy_provision_resources calls create app and volume" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  run deploy_provision_resources
  assert_success
}

@test "deploy_provision_resources passes org to fly_create_app" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export DEPLOY_ORG="my-org"
  run deploy_provision_resources
  assert_success
}

# --- deploy_show_success ---

@test "deploy_show_success contains app URL and Next steps" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VM_SIZE="shared-cpu-1x"
  export DEPLOY_VOLUME_SIZE="5"
  run deploy_show_success
  assert_success
  assert_output --partial "fly.dev"
  assert_output --partial "Next steps"
}

# --- deploy_cleanup_on_failure ---

@test "deploy_cleanup_on_failure destroys app" {
  run deploy_cleanup_on_failure "test-app"
  assert_success
}

# --- deploy_collect_llm_config ---

@test "deploy_collect_llm_config stores API key and default model" {
  # Choice 1 (OpenRouter), API key, model choice 1 (default)
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test-123\n1\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL"'
  assert_success
  assert_output --partial "KEY=sk-test-123"
  assert_output --partial "MODEL=anthropic/claude-sonnet"
}

@test "deploy_collect_llm_config re-prompts on empty key then accepts" {
  # Choice 1 (OpenRouter), empty key (re-prompt), API key, model choice 1
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\n\nsk-test-456\n1\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL"'
  assert_success
  assert_output --partial "KEY=sk-test-456"
}

# --- deploy_collect_llm_config table rendering ---

@test "deploy_collect_llm_config renders provider as box-drawing table" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>&1'
  assert_success
  assert_output --partial "┌"
  assert_output --partial "Provider"
  assert_output --partial "OpenRouter"
  assert_output --partial "Nous"
}

@test "deploy_collect_llm_config OpenRouter shows model table" {
  # Choice 1 (OpenRouter), API key, model choice 1 (default)
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>&1; echo "MODEL=$MODEL"'
  assert_success
  assert_output --partial "Select model"
  assert_output --partial "claude"
}

@test "deploy_collect_llm_config OpenRouter model choice 1 picks default" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output --partial "MODEL=anthropic/claude-sonnet"
}

# --- deploy_collect_llm_config provider choices ---

@test "deploy_collect_llm_config choice 1 sets OpenRouter provider" {
  # Choice 1 = OpenRouter, then API key, then model choice 1
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-or-key\n1\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL PROVIDER=$DEPLOY_LLM_PROVIDER"'
  assert_success
  assert_output --partial "KEY=sk-or-key"
  assert_output --partial "PROVIDER=openrouter"
}

@test "deploy_collect_llm_config choice 2 sets empty model for Nous" {
  # Choice 2 = Nous Portal, then API key
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "2\nnous-key-123\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL PROVIDER=$DEPLOY_LLM_PROVIDER"'
  assert_success
  assert_output --partial "KEY=nous-key-123"
  assert_output --partial "MODEL= "
  assert_output --partial "PROVIDER=nous"
}

@test "deploy_collect_llm_config choice 3 stores base URL in DEPLOY_LLM_BASE_URL" {
  # Choice 3 = Custom, then base URL, then API key
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "3\nhttps://my-llm.example.com/v1\ncustom-key-456\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL PROVIDER=$DEPLOY_LLM_PROVIDER BASE_URL=$DEPLOY_LLM_BASE_URL"'
  assert_success
  assert_output --partial "KEY=custom-key-456"
  assert_output --partial "MODEL= "
  assert_output --partial "PROVIDER=custom"
  assert_output --partial "BASE_URL=https://my-llm.example.com/v1"
}

# --- deploy_parse_orgs ---

@test "deploy_parse_orgs extracts slug and name from single org" {
  deploy_parse_orgs '{"personal":"Personal"}'
  [[ "${_ORG_SLUGS[0]}" == "personal" ]]
  [[ "${_ORG_NAMES[0]}" == "Personal" ]]
}

@test "deploy_parse_orgs extracts multiple orgs" {
  deploy_parse_orgs '{"personal":"Personal","my-team":"My Team"}'
  [[ ${#_ORG_SLUGS[@]} -eq 2 ]]
  [[ "${_ORG_SLUGS[0]}" == "personal" ]]
  [[ "${_ORG_SLUGS[1]}" == "my-team" ]]
  [[ "${_ORG_NAMES[1]}" == "My Team" ]]
}

@test "deploy_parse_orgs handles empty JSON" {
  deploy_parse_orgs "{}"
  [[ ${#_ORG_SLUGS[@]} -eq 0 ]]
}

@test "deploy_parse_orgs handles JSON with spaces after colons" {
  deploy_parse_orgs '{"personal": "Alex Fazio", "my-team": "My Team"}'
  [[ ${#_ORG_SLUGS[@]} -eq 2 ]]
  [[ "${_ORG_SLUGS[0]}" == "personal" ]]
  [[ "${_ORG_NAMES[0]}" == "Alex Fazio" ]]
  [[ "${_ORG_SLUGS[1]}" == "my-team" ]]
  [[ "${_ORG_NAMES[1]}" == "My Team" ]]
}

# --- deploy_parse_regions ---

@test "deploy_parse_regions extracts codes and names from JSON" {
  local json='[{"code":"iad","name":"Ashburn, Virginia (US)"},{"code":"ord","name":"Chicago, Illinois (US)"}]'
  deploy_parse_regions "$json"
  [[ "${_REGION_CODES[0]}" == "iad" ]]
  [[ "${_REGION_CODES[1]}" == "ord" ]]
  [[ "${_REGION_NAMES[0]}" == "Ashburn, Virginia (US)" ]]
  [[ "${_REGION_NAMES[1]}" == "Chicago, Illinois (US)" ]]
}

@test "deploy_parse_regions handles empty JSON" {
  deploy_parse_regions "[]"
  [[ ${#_REGION_CODES[@]} -eq 0 ]]
}

@test "deploy_get_region_continent maps known codes" {
  [[ "$(deploy_get_region_continent "iad")" == "Americas" ]]
  [[ "$(deploy_get_region_continent "ams")" == "Europe" ]]
  [[ "$(deploy_get_region_continent "nrt")" == "Asia-Pacific" ]]
  [[ "$(deploy_get_region_continent "syd")" == "Oceania" ]]
  [[ "$(deploy_get_region_continent "gru")" == "South America" ]]
}

@test "deploy_get_region_continent returns Other for unknown codes" {
  [[ "$(deploy_get_region_continent "xyz")" == "Other" ]]
}

@test "deploy_collect_region uses dynamic regions from fly API" {
  # Mock returns 10 regions; pick option 4 (ams)
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT <<< "4" 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "ams"
}

@test "deploy_collect_region falls back to static list on API failure" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_REGIONS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT <<< "1" 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "iad"
}

@test "deploy_collect_region does not crash under set -u when API fails" {
  run bash -c 'set -u; export NO_COLOR=1; export MOCK_FLY_REGIONS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT <<< "1" 2>/dev/null; echo "$RESULT"'
  assert_success
}

# --- deploy_parse_vm_sizes ---

@test "deploy_parse_vm_sizes extracts names and prices from JSON" {
  local json='[{"name":"shared-cpu-1x","cpu_cores":1,"memory_mb":256,"price_month":1.94},{"name":"shared-cpu-2x","cpu_cores":2,"memory_mb":512,"price_month":3.88}]'
  deploy_parse_vm_sizes "$json"
  [[ "${_VM_NAMES[0]}" == "shared-cpu-1x" ]]
  [[ "${_VM_NAMES[1]}" == "shared-cpu-2x" ]]
  [[ "${_VM_MEMORY[0]}" == "256" ]]
  [[ "${_VM_MEMORY[1]}" == "512" ]]
}

@test "deploy_collect_vm_size uses dynamic pricing from fly API" {
  # Pick option 1 explicitly
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>/dev/null; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output "SIZE=shared-cpu-1x MEM=256mb"
}

@test "deploy_collect_vm_size renders as box-drawing table" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>&1; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output --partial "┌"
  assert_output --partial "┘"
  assert_output --partial "shared-cpu-1x"
  assert_output --partial "recommended"
}

@test "deploy_collect_vm_size falls back to static on API failure" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_VM_SIZES_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "" 2>/dev/null; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output "SIZE=shared-cpu-2x MEM=512mb"
}

# --- deploy_validate_app_name ---

@test "deploy_validate_app_name accepts valid name" {
  source "${PROJECT_ROOT}/lib/deploy.sh"
  run deploy_validate_app_name "my-hermes-app"
  assert_success
}

@test "deploy_validate_app_name rejects uppercase name" {
  source "${PROJECT_ROOT}/lib/deploy.sh"
  run deploy_validate_app_name "My-Hermes"
  assert_failure
}

@test "deploy_validate_app_name rejects single char name" {
  source "${PROJECT_ROOT}/lib/deploy.sh"
  run deploy_validate_app_name "a"
  assert_failure
}

# --- config persistence ---

# --- fly_retry integration ---

@test "deploy_provision_resources uses fly_retry for app creation" {
  # Override fly_create_app to fail once, then succeed — fly_retry should handle it
  local call_count_file="${TEST_TEMP_DIR}/create_app_calls"
  echo "0" > "$call_count_file"

  fly_create_app() {
    local count
    count=$(cat "$call_count_file")
    count=$((count + 1))
    echo "$count" > "$call_count_file"
    if [[ "$count" -eq 1 ]]; then
      return 1
    fi
    echo '{"name":"test-app","status":"pending"}'
    return 0
  }
  export -f fly_create_app

  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export DEPLOY_LLM_PROVIDER="openrouter"
  run deploy_provision_resources
  assert_success
}

# --- deploy_preflight (default spinner mode) ---

@test "deploy_preflight default mode shows success message" {
  run deploy_preflight
  assert_success
  assert_output --partial "All preflight checks passed"
}

@test "deploy_preflight default mode shows failure on bad platform" {
  export HERMES_FLY_PLATFORM="MINGW64_NT"
  run deploy_preflight
  assert_failure
  assert_output --partial "Unsupported platform"
}

@test "deploy_preflight default mode does not show step numbers" {
  run deploy_preflight
  assert_success
  refute_output --partial "[1/6]"
  refute_output --partial "[2/6]"
}

# --- deploy_preflight (verbose mode) ---

@test "deploy_preflight verbose mode shows step numbers" {
  export HERMES_FLY_VERBOSE=1
  run deploy_preflight
  assert_success
  assert_output --partial "[1/6]"
  assert_output --partial "[6/6]"
}

@test "deploy_preflight verbose mode shows all check names" {
  export HERMES_FLY_VERBOSE=1
  run deploy_preflight
  assert_success
  assert_output --partial "Checking platform"
  assert_output --partial "Checking connectivity"
}

# --- config persistence ---

@test "deploy_provision_resources skips app creation when DEPLOY_APP_CREATED is set" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export DEPLOY_APP_CREATED=1
  export MOCK_FLY_APPS_CREATE=fail
  run deploy_provision_resources
  assert_success
  refute_output --partial "Failed to create app"
}

# --- deploy_provision_resources error messages ---

@test "deploy_provision_resources shows hint when app name already taken" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_APPS_CREATE=fail
  run deploy_provision_resources
  assert_failure
  assert_output --partial "Hint"
  assert_output --partial "already be taken"
}

# --- deploy_run_deploy error reporting ---

@test "deploy_run_deploy shows error details on failure" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_BUILD_DIR="$TEST_TEMP_DIR"
  export MOCK_FLY_DEPLOY=fail
  run deploy_run_deploy
  assert_failure
  assert_output --partial "Deployment failed"
  assert_output --partial "deployment failed"
}

@test "deploy_run_deploy shows machine state on failure" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_BUILD_DIR="$TEST_TEMP_DIR"
  export MOCK_FLY_DEPLOY=fail
  export MOCK_FLY_MACHINE_STATE="stopped"
  run deploy_run_deploy
  assert_failure
  assert_output --partial "stopped"
}

@test "deploy_run_deploy suggests diagnostic commands on failure" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_BUILD_DIR="$TEST_TEMP_DIR"
  export MOCK_FLY_DEPLOY=fail
  run deploy_run_deploy
  assert_failure
  assert_output --partial "hermes-fly logs"
  assert_output --partial "hermes-fly doctor"
}

# --- deploy_post_deploy_check retry ---

@test "deploy_post_deploy_check retries when user approves and succeeds" {
  export DEPLOY_APP_NAME="test-app"
  export MOCK_FLY_STATUS_SEQUENCE="stopped,running"
  export MOCK_FLY_STATUS_COUNTER_FILE="${TEST_TEMP_DIR}/status_counter"
  export HERMES_FLY_RETRY_SLEEP=0
  _run_with_stdin() { printf 'y\n' | deploy_post_deploy_check; }
  run _run_with_stdin
  assert_success
  assert_output --partial "stopped"
  assert_output --partial "App is running"
}

@test "deploy_post_deploy_check shows status trace" {
  export DEPLOY_APP_NAME="test-app"
  export MOCK_FLY_STATUS_SEQUENCE="stopped,running"
  export MOCK_FLY_STATUS_COUNTER_FILE="${TEST_TEMP_DIR}/status_counter"
  export HERMES_FLY_RETRY_SLEEP=0
  _run_with_stdin() { printf 'y\n' | deploy_post_deploy_check; }
  run _run_with_stdin
  assert_success
  assert_output --partial "Check 1"
  assert_output --partial "Check 2"
}

@test "deploy_post_deploy_check stops when user declines retry" {
  export DEPLOY_APP_NAME="test-app"
  export MOCK_FLY_MACHINE_STATE="stopped"
  _run_with_stdin() { printf 'n\n' | deploy_post_deploy_check; }
  run _run_with_stdin
  assert_failure
  assert_output --partial "stopped"
  assert_output --partial "hermes-fly doctor"
}

@test "deploy_post_deploy_check does not destroy app on failure" {
  export DEPLOY_APP_NAME="test-app"
  export MOCK_FLY_MACHINE_STATE="stopped"
  _run_with_stdin() { printf 'n\n' | deploy_post_deploy_check; }
  run _run_with_stdin
  assert_failure
  refute_output --partial "Cleaning up"
}

@test "deploy_post_deploy_check succeeds when app status is 'started'" {
  source "${PROJECT_ROOT}/lib/deploy.sh"
  export DEPLOY_APP_NAME="test-app"
  run deploy_post_deploy_check
  assert_success
  assert_output --partial "App is running"
}

@test "deploy_post_deploy_check shows HTTP health check message on success" {
  source "${PROJECT_ROOT}/lib/deploy.sh"
  export DEPLOY_APP_NAME="test-app"
  run deploy_post_deploy_check
  assert_success
  assert_output --partial "health check"
}

@test "deploy_post_deploy_check succeeds even when HTTP probe fails" {
  source "${PROJECT_ROOT}/lib/deploy.sh"
  export DEPLOY_APP_NAME="test-app"
  MOCK_CURL_FAIL=true run deploy_post_deploy_check
  assert_success
  assert_output --partial "App is running"
}

@test "deploy_provision_resources shows hint when name has already been taken" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_APPS_CREATE=fail
  export MOCK_FLY_APPS_CREATE_MSG="Name has already been taken"
  run deploy_provision_resources
  assert_failure
  assert_output --partial "Hint"
  assert_output --partial "already be taken"
}

@test "deploy_provision_resources shows error details on unknown failure" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_APPS_CREATE=fail
  export MOCK_FLY_APPS_CREATE_MSG="quota exceeded"
  run deploy_provision_resources
  assert_failure
  assert_output --partial "Details"
  assert_output --partial "quota exceeded"
}

@test "deploy_provision_resources shows only first error in details" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_APPS_CREATE=fail
  export MOCK_FLY_APPS_CREATE_MSG="quota exceeded"
  run deploy_provision_resources
  assert_failure
  assert_output --partial "quota exceeded"
  refute_output --partial "command failed after"
}

@test "deploy_provision_resources shows volume error details on failure" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_VOLUME_CREATE=fail
  run deploy_provision_resources
  assert_failure
  assert_output --partial "Details"
  assert_output --partial "no volumes available"
}

@test "deploy_provision_resources shows custom volume error message" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_VOLUME_CREATE=fail
  export MOCK_FLY_VOLUME_CREATE_MSG="region full"
  run deploy_provision_resources
  assert_failure
  assert_output --partial "region full"
}

@test "deploy_provision_resources shows secrets error details on failure" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_SECRETS_SET=fail
  run deploy_provision_resources
  assert_failure
  assert_output --partial "Details"
  assert_output --partial "failed to set secrets"
}

@test "deploy_provision_resources shows custom secrets error message" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export MOCK_FLY_SECRETS_SET=fail
  export MOCK_FLY_SECRETS_SET_MSG="unauthorized"
  run deploy_provision_resources
  assert_failure
  assert_output --partial "unauthorized"
}

# --- deployment summary messaging ---

@test "deployment summary shows Telegram when configured" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_config < <(printf "my-test-app\n1\n2\n2\n1\nsk-test-key\n1\n1\n123:ABC-token\n12345\ny\n") 2>&1'
  assert_success
  assert_output --partial "Telegram (configured)"
}

@test "deployment summary shows none when messaging skipped" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_config < <(printf "my-test-app\n1\n2\n2\n1\nsk-test-key\n1\n3\ny\n") 2>&1'
  assert_success
  assert_output --partial "none (configure later)"
}

# --- Menu re-prompt validation ---

@test "deploy_collect_org re-prompts on invalid input" {
  export MOCK_FLY_ORGS_JSON='{"personal":"Alex Fazio","ai-garden":"AI Garden"}'
  run bash -c 'export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Alex Fazio","ai-garden":"AI Garden"}'"'"'; export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org RESULT < <(printf "garbage\n1\n") 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "personal"
}

@test "deploy_collect_region re-prompts on invalid input" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "garbage\n1\n") 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "iad"
}

@test "deploy_collect_vm_size re-prompts on invalid input" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size RESULT_SIZE RESULT_MEM < <(printf "garbage\n2\n") 2>/dev/null; echo "$RESULT_SIZE"'
  assert_success
  assert_output "shared-cpu-2x"
}

@test "deploy_collect_volume_size re-prompts on invalid input" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_volume_size RESULT < <(printf "garbage\n1\n") 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "1"
}

@test "deploy_collect_llm_config re-prompts on invalid provider" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "garbage\n2\nnous-key-123\n") 2>/dev/null; echo "PROVIDER=$DEPLOY_LLM_PROVIDER"'
  assert_success
  assert_output --partial "PROVIDER=nous"
}

@test "deploy_collect_llm_config re-prompts on invalid model choice" {
  # Choice 1 (OpenRouter), API key, garbage model, then valid model 2
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\ngarbage\n2\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output "MODEL=anthropic/claude-haiku-4.5"
}

@test "deploy_collect_llm_config model choice 1 yields OpenRouter Sonnet 4 ID" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output "MODEL=anthropic/claude-sonnet-4"
}

@test "deploy_collect_llm_config model choice 2 yields OpenRouter Haiku 4.5 ID" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n2\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output "MODEL=anthropic/claude-haiku-4.5"
}

@test "config_save_app after deploy stores app in config.yaml" {
  config_save_app "deploy-test-app" "ord"
  run cat "${HERMES_FLY_CONFIG_DIR}/config.yaml"
  assert_success
  assert_output --partial "deploy-test-app"
}
