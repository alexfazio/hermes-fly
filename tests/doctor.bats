#!/usr/bin/env bats
# tests/doctor.bats — Tests for lib/doctor.sh diagnostics command

setup() {
  load 'test_helper/common-setup'
  _common_setup
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/fly-helpers.sh"
  source "${PROJECT_ROOT}/lib/doctor.sh"
}

teardown() {
  _common_teardown
}

# --- doctor_report ---

@test "doctor_report formats PASS correctly" {
  run doctor_report "auth" "pass" "Authenticated"
  assert_success
  assert_output --partial "[PASS]"
  assert_output --partial "auth"
  assert_output --partial "Authenticated"
}

@test "doctor_report formats FAIL correctly" {
  run doctor_report "auth" "fail" "Not logged in"
  assert_success
  assert_output --partial "[FAIL]"
  assert_output --partial "auth"
  assert_output --partial "Not logged in"
}

# --- cmd_doctor ---

@test "cmd_doctor with all checks passing exits 0" {
  run cmd_doctor "test-app"
  assert_success
  assert_output --partial "PASS"
}

@test "cmd_doctor with machine stopped exits 1 with hint" {
  export MOCK_FLY_MACHINE_STATE=stopped
  run cmd_doctor "test-app"
  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "fly machine start"
}

@test "cmd_doctor with app not found exits 1" {
  export MOCK_FLY_STATUS=fail
  run cmd_doctor "test-app"
  assert_failure
}

@test "cmd_doctor runs all 8 checks when app exists" {
  run cmd_doctor "test-app"
  assert_success
  assert_output --partial "8 passed, 0 failed"
}

# --- doctor_check_volume_mounted ---

@test "doctor_check_volume_mounted passes with volumes" {
  run doctor_check_volume_mounted "test-app"
  assert_success
}

@test "doctor_check_volume_mounted fails when empty" {
  export MOCK_FLY_VOLUMES_EMPTY=true
  run doctor_check_volume_mounted "test-app"
  assert_failure
}

# --- doctor_check_secrets_set ---

@test "doctor_check_secrets_set passes when key present" {
  local json='[{"Name":"OPENROUTER_API_KEY","Digest":"abc123"}]'
  run doctor_check_secrets_set "$json"
  assert_success
}

@test "doctor_check_secrets_set fails when missing" {
  run doctor_check_secrets_set ""
  assert_failure
}

@test "doctor_check_secrets_set passes with Nous API key" {
  local json='[{"Name":"NOUS_API_KEY","Digest":"nous123"}]'
  run doctor_check_secrets_set "$json"
  assert_success
}

@test "doctor_check_secrets_set passes with custom LLM API key" {
  local json='[{"Name":"LLM_API_KEY","Digest":"llm123"}]'
  run doctor_check_secrets_set "$json"
  assert_success
}

# --- doctor_check_machine_running fallback hardening ---

@test "doctor_check_machine_running handles pretty-printed JSON without jq" {
  # Build a minimal bin dir with core utilities but no jq
  local nojq_bin="${TEST_TEMP_DIR}/nojq_bin"
  mkdir -p "$nojq_bin"
  for cmd in grep sed head tr printf cat; do
    local cmd_path
    cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
    [[ -n "$cmd_path" && -x "$cmd_path" ]] && ln -sf "$cmd_path" "$nojq_bin/$cmd"
  done

  local pretty_json='{
  "machines": [
    {
      "id": "machine123",
      "state": "started",
      "region": "ord"
    }
  ]
}'
  PATH="$nojq_bin" run doctor_check_machine_running "$pretty_json"
  assert_success
}

@test "doctor_check_machine_running handles compact JSON without jq" {
  local nojq_bin="${TEST_TEMP_DIR}/nojq_bin"
  mkdir -p "$nojq_bin"
  for cmd in grep sed head tr printf cat; do
    local cmd_path
    cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
    [[ -n "$cmd_path" && -x "$cmd_path" ]] && ln -sf "$cmd_path" "$nojq_bin/$cmd"
  done

  local compact_json='{"machines":[{"id":"machine123","state":"started","region":"ord"}]}'
  PATH="$nojq_bin" run doctor_check_machine_running "$compact_json"
  assert_success
}

# --- doctor_check_hermes_process ---

@test "doctor_check_hermes_process returns 0 when process field is hermes" {
  local json='{"machines":[{"process":"hermes","state":"started"}]}'
  run doctor_check_hermes_process "$json"
  assert_success
}

@test "doctor_check_hermes_process returns 1 when process is not hermes" {
  local json='{"machines":[{"process":"web","state":"started"}]}'
  run doctor_check_hermes_process "$json"
  assert_failure
}

@test "doctor_check_hermes_process ignores hermes in app name" {
  local json='{"app":{"name":"my-hermes-app"},"machines":[{"process":"web"}]}'
  run doctor_check_hermes_process "$json"
  assert_failure
}

# --- doctor_check_gateway_health ---

@test "doctor_check_gateway_health returns 0 when Telegram getMe succeeds" {
  export MOCK_FLY_SECRETS_HAS_TELEGRAM=true
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    export MOCK_FLY_SECRETS_HAS_TELEGRAM=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/doctor.sh;
    doctor_check_gateway_health "test-app"'
  assert_success
}

@test "doctor_check_gateway_health returns 1 when getMe fails for Telegram app" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    export MOCK_FLY_SECRETS_HAS_TELEGRAM=true; export MOCK_CURL_FAIL=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/doctor.sh;
    doctor_check_gateway_health "test-app"'
  assert_failure
}

@test "doctor_check_gateway_health falls back to HTTP probe for non-Telegram apps" {
  run doctor_check_gateway_health "test-app"
  assert_success
}

# --- doctor_check_api_connectivity ---

@test "doctor_check_api_connectivity returns 0 when API reachable" {
  run doctor_check_api_connectivity ""
  assert_success
}

@test "doctor_check_api_connectivity returns 1 when API down" {
  export MOCK_CURL_FAIL=true
  run doctor_check_api_connectivity ""
  assert_failure
}

@test "doctor_check_api_connectivity checks Nous portal with Nous key" {
  local json='[{"Name":"NOUS_API_KEY","Digest":"nous123"}]'
  run doctor_check_api_connectivity "$json"
  assert_success
}

@test "doctor_check_api_connectivity skips for custom provider" {
  local json='[{"Name":"LLM_API_KEY","Digest":"llm123"}]'
  run doctor_check_api_connectivity "$json"
  assert_success
}

# --- doctor_check_machine_running fallback hardening ---

@test "doctor_check_machine_running fallback returns failure for stopped machine" {
  local nojq_bin="${TEST_TEMP_DIR}/nojq_bin"
  mkdir -p "$nojq_bin"
  for cmd in grep sed head tr printf cat; do
    local cmd_path
    cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
    [[ -n "$cmd_path" && -x "$cmd_path" ]] && ln -sf "$cmd_path" "$nojq_bin/$cmd"
  done

  local json='{"machines":[{"id":"machine123","state":"stopped","region":"ord"}]}'
  PATH="$nojq_bin" run doctor_check_machine_running "$json"
  assert_failure
}

# ==========================================================================
# PR-05: Drift detection
# ==========================================================================

# --- doctor_load_deploy_summary ---

@test "doctor_load_deploy_summary returns content for existing app (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/test-app.yaml" <<'EOF'
app_name: test-app
hermes_agent_ref: abc123def456abc123def456abc123def456abc123
deploy_channel: stable
compatibility_policy_version: v1
EOF
  run doctor_load_deploy_summary "test-app"
  assert_success
  assert_output --partial "hermes_agent_ref"
  assert_output --partial "deploy_channel"
}

@test "doctor_load_deploy_summary returns empty for missing app (PR-05)" {
  run doctor_load_deploy_summary "no-such-app-xyz"
  assert_success
  assert_output ""
}

# --- doctor_check_drift ---

@test "doctor_check_drift returns 0 when provenance secrets present (PR-05)" {
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"},{"Name":"HERMES_FLY_VERSION","Digest":"ver_hash"}]'
  run doctor_check_drift "test-app" "$secrets_json"
  assert_success
}

@test "doctor_check_drift returns 1 when HERMES_AGENT_REF missing (PR-05)" {
  local secrets_json='[{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"},{"Name":"HERMES_FLY_VERSION","Digest":"ver_hash"}]'
  run doctor_check_drift "test-app" "$secrets_json"
  assert_failure
}

@test "doctor_check_drift returns 1 when HERMES_DEPLOY_CHANNEL missing (PR-05)" {
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_FLY_VERSION","Digest":"ver_hash"}]'
  run doctor_check_drift "test-app" "$secrets_json"
  assert_failure
}

@test "doctor_check_drift includes informative message when provenance missing (PR-05)" {
  local secrets_json='[{"Name":"OPENROUTER_API_KEY","Digest":"abc123"}]'
  run doctor_check_drift "test-app" "$secrets_json" 2>&1
  assert_failure
  assert_output --partial "provenance"
}

@test "doctor_check_drift returns 0 when no local summary exists but provenance present (PR-05)" {
  # No deploy summary on disk for this app — skip channel/ref drift cleanly
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"}]'
  run doctor_check_drift "no-summary-app-xyz" "$secrets_json"
  assert_success
}

@test "doctor_check_drift detects unknown channel in local summary (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/drift-channel-app.yaml" <<'EOF'
app_name: drift-channel-app
deploy_channel: nightlycanary
hermes_agent_ref: abc123
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"}]'
  run doctor_check_drift "drift-channel-app" "$secrets_json" 2>&1
  assert_failure
  assert_output --partial "channel"
}

@test "doctor_check_drift passes for stable channel in local summary (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/stable-app.yaml" <<'EOF'
app_name: stable-app
deploy_channel: stable
hermes_agent_ref: abc123def456
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"}]'
  run doctor_check_drift "stable-app" "$secrets_json"
  assert_success
}

@test "doctor_check_drift passes for preview channel in local summary (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/preview-app.yaml" <<'EOF'
app_name: preview-app
deploy_channel: preview
hermes_agent_ref: abc123def456
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"preview_hash"}]'
  run doctor_check_drift "preview-app" "$secrets_json"
  assert_success
}

@test "doctor_check_drift passes for edge channel in local summary (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/edge-app.yaml" <<'EOF'
app_name: edge-app
deploy_channel: edge
hermes_agent_ref: abc123def456
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"edge_hash"}]'
  run doctor_check_drift "edge-app" "$secrets_json"
  assert_success
}

@test "cmd_doctor includes drift check in output (PR-05)" {
  run cmd_doctor "test-app"
  assert_output --partial "drift"
}
