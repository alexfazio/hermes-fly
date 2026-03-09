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

@test "deploy_collect_app_name prompt says Deployment name" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_app_name RESULT <<< "" 2>&1'
  assert_success
  assert_output --partial "Deployment name"
  refute_output --partial "App name"
}

@test "deploy_collect_app_name shows guidance about unique names" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_app_name RESULT <<< "" 2>&1'
  assert_success
  assert_output --partial "unique name"
}

@test "deploy_collect_app_name shows visibility and Enter guidance" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_app_name RESULT <<< "" 2>&1'
  assert_success
  assert_output --partial "visible to anyone chatting"
  assert_output --partial "Press Enter"
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

@test "deploy_collect_vm_size option 3 selects performance-1x with 2gb" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "3" 2>/dev/null; echo "SIZE=$SIZE MEM=$MEM"'
  assert_success
  assert_output "SIZE=performance-1x MEM=2gb"
}

@test "deploy_collect_vm_size shows tier names" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>&1'
  assert_success
  assert_output --partial "Starter"
  assert_output --partial "Standard"
  assert_output --partial "Pro"
}

@test "deploy_collect_vm_size Pro shows 2 GB RAM" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>&1'
  assert_success
  assert_output --partial "2 GB"
}

@test "deploy_collect_vm_size hides tiers not in API response" {
  # Mock only returns shared-cpu-1x and shared-cpu-2x
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_VM_SIZES_JSON='"'"'[{"name":"shared-cpu-1x","cpu_cores":1,"memory_mb":256,"price_month":2.02},{"name":"shared-cpu-2x","cpu_cores":2,"memory_mb":512,"price_month":4.04}]'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>&1'
  assert_success
  assert_output --partial "Starter"
  assert_output --partial "Standard"
  refute_output --partial "Pro"
  refute_output --partial "Power"
}

@test "deploy_collect_vm_size fallback shows correct performance-1x price ~32" {
  # Force fallback by making fly platform vm-sizes fail (MOCK_FLY_VM_SIZES_FAIL=true)
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_VM_SIZES_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "3" 2>&1'
  assert_success
  assert_output --partial '$32.19'
}

@test "deploy_collect_vm_size shows pricing disclaimer with calculator link" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_vm_size SIZE MEM <<< "1" 2>&1'
  assert_success
  assert_output --partial "estimates"
  assert_output --partial "fly.io/calculator"
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
  assert_output --partial "Recommended"
}

@test "deploy_collect_volume_size shows storage guidance" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_volume_size VSIZE <<< "1" 2>&1'
  assert_success
  assert_output --partial "storage"
}

@test "deploy_collect_volume_size shows Best for column" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_volume_size VSIZE <<< "1" 2>&1'
  assert_success
  assert_output --partial "Best for"
}

@test "deploy_collect_volume_size shows pricing disclaimer with calculator link" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_volume_size VSIZE <<< "1" 2>&1'
  assert_success
  assert_output --partial "estimates"
  assert_output --partial "fly.io/calculator"
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
  refute_output --partial "Choose a workspace"
}

@test "deploy_collect_org shows table for multiple orgs" {
  export MOCK_FLY_ORGS_JSON='{"personal":"Personal","my-team":"My Team"}'
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Personal","my-team":"My Team"}'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG < <(printf "1\n") 2>&1; echo "ORG=$DEPLOY_ORG"'
  assert_success
  assert_output --partial "Choose a workspace"
  assert_output --partial "my-team"
  assert_output --partial "ORG=personal"
}

@test "deploy_collect_org table shows Workspace and ID headers" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Personal","my-team":"My Team"}'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG < <(printf "1\n") 2>&1'
  assert_success
  assert_output --partial "Workspace"
  assert_output --partial "ID"
  refute_output --partial "Organization"
  refute_output --partial "Slug"
}

@test "deploy_collect_org shows guidance text for multiple orgs" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Personal","my-team":"My Team"}'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG < <(printf "1\n") 2>&1'
  assert_success
  assert_output --partial "workspaces"
}

@test "deploy_collect_org shows dashboard link for multiple orgs" {
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_ORGS_JSON='"'"'{"personal":"Personal","my-team":"My Team"}'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_org DEPLOY_ORG < <(printf "1\n") 2>&1'
  assert_success
  assert_output --partial "fly.io/dashboard"
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

@test "deploy_show_success shows Telegram deep link" {
  export DEPLOY_APP_NAME="my-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VM_SIZE="shared-cpu-1x"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_TELEGRAM_BOT_USERNAME="test_bot"
  run deploy_show_success
  assert_success
  assert_output --partial "t.me/test_bot?start=my-app"
}

# --- deploy_cleanup_on_failure ---

@test "deploy_cleanup_on_failure destroys app" {
  run deploy_cleanup_on_failure "test-app"
  assert_success
}

# --- deploy_collect_llm_config ---

@test "deploy_collect_llm_config stores API key and default model" {
  # Choice 1 (OpenRouter), API key, model choice 1 (default)
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test-123\n1\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL"'
  assert_success
  assert_output --partial "KEY=sk-test-123"
  assert_output --partial "MODEL=anthropic/claude-sonnet"
}

@test "deploy_collect_llm_config re-prompts on empty key then accepts" {
  # Choice 1 (OpenRouter), empty key (re-prompt), API key, model choice 1
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\n\nsk-test-456\n1\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL"'
  assert_success
  assert_output --partial "KEY=sk-test-456"
}

@test "deploy_collect_llm_config shows OpenRouter key URL" {
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>&1'
  assert_success
  assert_output --partial "openrouter.ai/settings/keys"
}

@test "deploy_collect_llm_config shows Nous Portal key URL" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "2\nnous-key\n") 2>&1'
  assert_success
  assert_output --partial "Get your API key"
}

# --- deploy_collect_llm_config table rendering ---

@test "deploy_collect_llm_config renders provider as box-drawing table" {
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>&1'
  assert_success
  assert_output --partial "┌"
  assert_output --partial "Provider"
  assert_output --partial "OpenRouter"
  assert_output --partial "Nous"
}

@test "deploy_collect_llm_config OpenRouter shows model table" {
  # Choice 1 (OpenRouter), API key, model choice 1 (default)
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>&1; echo "MODEL=$MODEL"'
  assert_success
  assert_output --partial "Select model"
  assert_output --partial "Claude"
}

@test "deploy_collect_llm_config OpenRouter model choice 1 picks default" {
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output --partial "MODEL=anthropic/claude-sonnet"
}

# --- deploy_collect_llm_config provider choices ---

@test "deploy_collect_llm_config choice 1 sets OpenRouter provider" {
  # Choice 1 = OpenRouter, then API key, then model choice 1
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-or-key\n1\n") 2>/dev/null; echo "KEY=$KEY MODEL=$MODEL PROVIDER=$DEPLOY_LLM_PROVIDER"'
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

@test "deploy_collect_llm_config shows only 2 provider options" {
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>&1'
  assert_success
  assert_output --partial "OpenRouter"
  assert_output --partial "Nous"
  # Custom provider row removed — "Custom model ID" in model table is expected
  refute_output --partial "your own endpoint"
}

@test "deploy_collect_llm_config expert override via env vars skips menu" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export DEPLOY_LLM_PROVIDER=custom; export DEPLOY_LLM_BASE_URL="https://my-llm.example.com/v1"; export DEPLOY_API_KEY="custom-key-456"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL 2>/dev/null; echo "KEY=$KEY PROVIDER=$DEPLOY_LLM_PROVIDER BASE_URL=$DEPLOY_LLM_BASE_URL"'
  assert_success
  assert_output --partial "KEY=custom-key-456"
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

@test "deploy_parse_orgs handles array-of-objects format" {
  deploy_parse_orgs '[{"name":"Alex Fazio","slug":"personal","type":"PERSONAL"},{"name":"ai-garden-srls","slug":"ai-garden-srls","type":"ORGANIZATION"}]'
  [[ ${#_ORG_SLUGS[@]} -eq 2 ]]
  [[ "${_ORG_SLUGS[0]}" == "personal" ]]
  [[ "${_ORG_NAMES[0]}" == "Alex Fazio" ]]
  [[ "${_ORG_SLUGS[1]}" == "ai-garden-srls" ]]
  [[ "${_ORG_NAMES[1]}" == "ai-garden-srls" ]]
}

@test "deploy_parse_orgs handles array with spacing between objects" {
  deploy_parse_orgs '[{"name":"Alex Fazio","slug":"personal","type":"PERSONAL"}, {"name":"AI Garden","slug":"ai-garden","type":"ORGANIZATION"}]'
  [[ ${#_ORG_SLUGS[@]} -eq 2 ]]
  [[ "${_ORG_SLUGS[0]}" == "personal" ]]
  [[ "${_ORG_NAMES[0]}" == "Alex Fazio" ]]
  [[ "${_ORG_SLUGS[1]}" == "ai-garden" ]]
  [[ "${_ORG_NAMES[1]}" == "AI Garden" ]]
}

@test "deploy_parse_orgs handles array with newlines between objects" {
  local json='[{"name":"Alex Fazio","slug":"personal","type":"PERSONAL"},
  {"name":"AI Garden","slug":"ai-garden","type":"ORGANIZATION"}]'
  deploy_parse_orgs "$json"
  [[ ${#_ORG_SLUGS[@]} -eq 2 ]]
  [[ "${_ORG_SLUGS[0]}" == "personal" ]]
  [[ "${_ORG_SLUGS[1]}" == "ai-garden" ]]
}

@test "deploy_parse_orgs handles empty array" {
  deploy_parse_orgs "[]"
  [[ ${#_ORG_SLUGS[@]} -eq 0 ]]
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

@test "deploy_collect_region step 1 shows continents with counts" {
  # Select continent 1 (Americas), then city 1
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "1\n1\n") 2>&1; echo "RESULT=$RESULT"'
  assert_success
  assert_output --partial "Americas"
  assert_output --partial "locations"
}

@test "deploy_collect_region step 2 shows cities for selected continent" {
  # Select continent 2 (Europe), then city 1
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "2\n1\n") 2>&1; echo "RESULT=$RESULT"'
  assert_success
  assert_output --partial "Amsterdam"
}

@test "deploy_collect_region routes unknown region codes to Other" {
  # Mock with unknown code
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_REGIONS_JSON='"'"'[{"code":"xyz","name":"Unknown City"},{"code":"iad","name":"Ashburn"}]'"'"'; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "2\n1\n") 2>&1; echo "RESULT=$RESULT"'
  assert_success
  assert_output --partial "Other"
}

@test "deploy_collect_region falls back to static list on API failure" {
  # Continent 1 (Americas), then city 1 (Ashburn)
  run bash -c 'export NO_COLOR=1; export MOCK_FLY_REGIONS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "1\n1\n") 2>/dev/null; echo "$RESULT"'
  assert_success
  assert_output "iad"
}

@test "deploy_collect_region does not crash under set -u when API fails" {
  run bash -c 'set -u; export NO_COLOR=1; export MOCK_FLY_REGIONS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "1\n1\n") 2>/dev/null; echo "$RESULT"'
  assert_success
}

# --- deploy_parse_vm_sizes ---

@test "deploy_parse_vm_sizes extracts names and prices from JSON" {
  local json='[{"name":"shared-cpu-1x","cpu_cores":1,"memory_mb":256,"price_month":2.02},{"name":"shared-cpu-2x","cpu_cores":2,"memory_mb":512,"price_month":4.04}]'
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
  assert_output --partial "Starter"
  assert_output --partial "Recommended"
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

# --- deploy_provision_resources new secrets ---

@test "deploy_provision_resources includes HERMES_APP_NAME" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  local secrets_file="${BATS_TEST_TMPDIR}/secrets_args"
  export MOCK_FLY_SECRETS_ARGS_FILE="$secrets_file"
  run deploy_provision_resources
  assert_success
  [[ -f "$secrets_file" ]]
  run cat "$secrets_file"
  assert_output --partial "HERMES_APP_NAME=test-app"
}

@test "deploy_provision_resources includes GATEWAY_ALLOW_ALL_USERS when set" {
  export DEPLOY_APP_NAME="test-app"
  export DEPLOY_REGION="ord"
  export DEPLOY_VOLUME_SIZE="5"
  export DEPLOY_API_KEY="sk-test-key"
  export DEPLOY_MODEL="anthropic/claude-sonnet-4-20250514"
  export DEPLOY_GATEWAY_ALLOW_ALL_USERS="true"
  local secrets_file="${BATS_TEST_TMPDIR}/secrets_args"
  export MOCK_FLY_SECRETS_ARGS_FILE="$secrets_file"
  run deploy_provision_resources
  assert_success
  [[ -f "$secrets_file" ]]
  run cat "$secrets_file"
  assert_output --partial "GATEWAY_ALLOW_ALL_USERS=true"
}

# --- deployment summary messaging ---

@test "deployment summary shows Telegram when configured" {
  # Sequence: app, continent, city, vm, vol, provider, key, model, msg(telegram), token, confirm_bot, access(Only me), user_id, home_channel_yes, proceed
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_config < <(printf "my-test-app\n1\n1\n2\n2\n1\nsk-test-key\n1\n1\n123:ABC-token\ny\n1\n12345\ny\ny\n") 2>&1'
  assert_success
  assert_output --partial "Telegram (configured)"
}

@test "deployment summary shows none when messaging skipped" {
  # Sequence: app_name, continent, city, vm_tier, vol_size, llm_provider, api_key, model, messaging(skip), proceed
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_config < <(printf "my-test-app\n1\n1\n2\n2\n1\nsk-test-key\n1\n2\ny\n") 2>&1'
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
  # garbage at continent level, then Americas (1), then city 1
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_region RESULT < <(printf "garbage\n1\n1\n") 2>/dev/null; echo "$RESULT"'
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
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\ngarbage\n2\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output "MODEL=anthropic/claude-haiku-4.5"
}

@test "deploy_collect_llm_config model choice 1 yields OpenRouter Sonnet 4 ID" {
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n1\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output "MODEL=anthropic/claude-sonnet-4"
}

@test "deploy_collect_llm_config model choice 2 yields OpenRouter Haiku 4.5 ID" {
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source lib/ui.sh; source lib/fly-helpers.sh; source lib/docker-helpers.sh; source lib/messaging.sh; source lib/config.sh; source lib/status.sh; source lib/deploy.sh; deploy_collect_llm_config KEY MODEL < <(printf "1\nsk-test\n2\n") 2>/dev/null; echo "MODEL=$MODEL"'
  assert_success
  assert_output "MODEL=anthropic/claude-haiku-4.5"
}

@test "config_save_app after deploy stores app in config.yaml" {
  config_save_app "deploy-test-app" "ord"
  run cat "${HERMES_FLY_CONFIG_DIR}/config.yaml"
  assert_success
  assert_output --partial "deploy-test-app"
}

# --- deploy_validate_openrouter_key ---

@test "deploy_validate_openrouter_key returns 0 for valid key" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_openrouter_key "sk-or-v1-valid" 2>/dev/null'
  assert_success
}

@test "deploy_validate_openrouter_key returns 1 for invalid key" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_CURL_FAIL=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_openrouter_key "bad-key" 2>/dev/null'
  assert_failure
}

@test "deploy_validate_nous_key returns 0 for valid key" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_nous_key "valid-nous-key" 2>/dev/null'
  assert_success
}

@test "deploy_validate_nous_key returns 1 on auth failure" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_NOUS_AUTH_FAIL=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_nous_key "bad-key" 2>/dev/null'
  assert_failure
}

@test "deploy_validate_nous_key warns and allows continue on timeout" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_NOUS_TIMEOUT=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_nous_key "timeout-key" < <(printf "y\n") 2>&1'
  assert_success
  assert_output --partial "Continue"
}

@test "deploy_validate_nous_key offers bypass on server error (500)" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_NOUS_SERVER_ERROR=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_nous_key "valid-key" < <(printf "y\n") 2>&1'
  assert_success
  assert_output --partial "server error"
}

@test "deploy_validate_nous_key returns 1 on server error declined" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_NOUS_SERVER_ERROR=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_nous_key "valid-key" < <(printf "n\n") 2>/dev/null'
  assert_failure
}

@test "deploy_collect_llm_config Nous auth failure never offers bypass" {
  # Feed: LLM choice=2 (Nous), 3 bad keys, decline bypass (if offered), then good key
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    export MOCK_NOUS_FAIL_DIR="$(mktemp -d)"
    touch "$MOCK_NOUS_FAIL_DIR/fail1" "$MOCK_NOUS_FAIL_DIR/fail2" "$MOCK_NOUS_FAIL_DIR/fail3"
    deploy_collect_llm_config DEPLOY_API_KEY DEPLOY_MODEL < <(printf "2\nbad-key1\nbad-key2\nbad-key3\nn\ngood-key\n") 2>&1
    rm -rf "$MOCK_NOUS_FAIL_DIR"'
  assert_success
  refute_output --partial "Continue with this key anyway"
}

@test "deploy_validate_nous_key returns 1 on rate limit (429)" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_NOUS_RATE_LIMIT=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_nous_key "some-key" 2>/dev/null'
  assert_failure
}

@test "deploy_collect_llm_config Nous loops until valid key" {
  # Feed: choice=2 (Nous), 2 bad keys, then valid key
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    export MOCK_NOUS_FAIL_DIR="$(mktemp -d)"
    touch "$MOCK_NOUS_FAIL_DIR/fail1" "$MOCK_NOUS_FAIL_DIR/fail2"
    deploy_collect_llm_config DEPLOY_API_KEY DEPLOY_MODEL < <(printf "2\nbad-key1\nbad-key2\nvalid-key-123\n") 2>/dev/null
    rm -rf "$MOCK_NOUS_FAIL_DIR"
    echo "KEY=$DEPLOY_API_KEY"'
  assert_success
  assert_output --partial "KEY=valid-key-123"
}

@test "deploy_write_summary creates YAML with all fields" {
  export DEPLOY_APP_NAME="my-agent" DEPLOY_REGION="ams" DEPLOY_VM_SIZE="shared-cpu-2x"
  export DEPLOY_VOLUME_SIZE="5" DEPLOY_MODEL="anthropic/claude-haiku-4.5"
  export DEPLOY_LLM_PROVIDER="openrouter" DEPLOY_TELEGRAM_BOT_USERNAME="my_bot"
  export DEPLOY_MESSAGING_PLATFORM="telegram" HERMES_FLY_VERSION="0.1.10"
  run bash -c 'source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_write_summary 2>/dev/null
    cat "${HERMES_FLY_CONFIG_DIR}/deploys/my-agent.yaml"'
  assert_success
  assert_output --partial "app_name: my-agent"
  assert_output --partial "region: ams"
  assert_output --partial "bot_username: my_bot"
  assert_output --partial "hermes_fly_version: 0.1.10"
}

@test "deploy_write_summary creates Markdown with management commands" {
  export DEPLOY_APP_NAME="my-agent" DEPLOY_REGION="ams" DEPLOY_VM_SIZE="shared-cpu-2x"
  export DEPLOY_VOLUME_SIZE="5" DEPLOY_MODEL="" DEPLOY_LLM_PROVIDER="openrouter"
  export DEPLOY_MESSAGING_PLATFORM="telegram" DEPLOY_TELEGRAM_BOT_USERNAME="my_bot"
  export HERMES_FLY_VERSION="0.1.10"
  run bash -c 'source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_write_summary 2>/dev/null
    cat "${HERMES_FLY_CONFIG_DIR}/deploys/my-agent.md"'
  assert_success
  assert_output --partial "hermes-fly status -a my-agent"
  assert_output --partial "https://my-agent.fly.dev"
}

@test "deploy_collect_llm_config re-prompts on invalid OpenRouter key" {
  local fail_file="${BATS_TEST_TMPDIR}/openrouter_fail"
  touch "$fail_file"
  run bash -c 'export NO_COLOR=1; export MOCK_OPENROUTER_MODELS_FAIL=true; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    export MOCK_OPENROUTER_FAIL_FILE="'"${fail_file}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_collect_llm_config DEPLOY_API_KEY DEPLOY_MODEL < <(printf "1\nbad-key\ngood-key\n1\n") 2>&1'
  assert_success
  assert_output --partial "rejected"
}

@test "deploy_validate_openrouter_key warns on free tier with zero usage" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_OPENROUTER_FREE_TIER=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_validate_openrouter_key "sk-or-v1-free" 2>&1'
  assert_success
  assert_output --partial "free tier"
}

# --- deploy_preflight with prereqs integration ---

@test "deploy_preflight calls prereqs_check_and_install when prerequisites missing" {
  export NO_COLOR=1
  export PATH="/usr/bin:/bin"  # exclude mocks so tools are missing
  export HERMES_FLY_VERBOSE=0  # use spinner mode

  run bash -c 'source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/prereqs.sh;
    prereqs_check_and_install() { echo "PREREQS_CALLED=1"; return 0; }
    export -f prereqs_check_and_install
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_preflight 2>&1 || true'
  assert_output --partial "PREREQS_CALLED=1"
}

@test "deploy_preflight returns 1 if prereqs_check_and_install fails" {
  export NO_COLOR=1
  export PATH="/usr/bin:/bin"  # exclude mocks
  export HERMES_FLY_VERBOSE=0

  run bash -c 'source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/prereqs.sh;
    prereqs_check_and_install() { return 1; }
    export -f prereqs_check_and_install
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_preflight 2>&1'
  assert_failure
}

# --- deploy_collect_model ---

@test "deploy_collect_model shows models grouped by provider with jq" {
  export DEPLOY_API_KEY="sk-or-test123"
  run deploy_collect_model MODEL_RESULT <<< "1"
  assert_success
  assert_output --partial "anthropic"
  assert_output --partial "Claude"
}

@test "deploy_collect_model falls back to static list without jq" {
  export DEPLOY_API_KEY="sk-or-test123"
  export MOCK_OPENROUTER_MODELS_FAIL=true
  run deploy_collect_model MODEL_RESULT <<< "1"
  assert_success
  assert_output --partial "Claude Sonnet 4"
  assert_output --partial "Llama 4 Maverick"
}

@test "deploy_collect_model Other accepts manual model ID" {
  export DEPLOY_API_KEY="sk-or-test123"
  export MOCK_OPENROUTER_MODELS_FAIL=true
  # Static list has 4 models + Other = option 5
  _test_collect_model_other() {
    deploy_collect_model MODEL_RESULT
    printf 'SELECTED=%s\n' "$MODEL_RESULT"
  }
  run _test_collect_model_other <<< $'5\nmy-custom/model-id'
  assert_success
  assert_output --partial "SELECTED=my-custom/model-id"
}

@test "verbose deploy_preflight calls prereqs_check_and_install on failure" {
  export NO_COLOR=1
  export PATH="/usr/bin:/bin"  # exclude mocks
  export HERMES_FLY_VERBOSE=1

  run bash -c 'source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh;
    source '"${PROJECT_ROOT}"'/lib/prereqs.sh;
    prereqs_check_and_install() { echo "VERBOSE_PREREQS_CALLED=1"; return 0; }
    export -f prereqs_check_and_install
    source '"${PROJECT_ROOT}"'/lib/deploy.sh;
    deploy_preflight 2>&1 || true'
  assert_output --partial "VERBOSE_PREREQS_CALLED=1"
}
