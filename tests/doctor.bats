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
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/test-app.yaml" <<'EOF'
app_name: test-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  run cmd_doctor "test-app"
  assert_success
  assert_output --partial "PASS"
  unset MOCK_FLY_RUNTIME_MANIFEST
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
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/test-app.yaml" <<'EOF'
app_name: test-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  run cmd_doctor "test-app"
  assert_success
  assert_output --partial "8 passed, 0 failed"
  unset MOCK_FLY_RUNTIME_MANIFEST
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

@test "doctor_check_drift returns 0 when provenance secrets and local summary present (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/test-app.yaml" <<'EOF'
app_name: test-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"},{"Name":"HERMES_FLY_VERSION","Digest":"ver_hash"}]'
  run doctor_check_drift "test-app" "$secrets_json"
  assert_success
  unset MOCK_FLY_RUNTIME_MANIFEST
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

@test "doctor_check_drift fails when no local summary exists (REVIEW_3)" {
  # Absence of local summary is a provenance gap — must fail, not silently pass
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"}]'
  run doctor_check_drift "no-summary-app-xyz" "$secrets_json"
  assert_failure
  assert_output --partial "local deploy summary"
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
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"stable_hash"}]'
  run doctor_check_drift "stable-app" "$secrets_json"
  assert_success
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift passes for preview channel in local summary (PR-05)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/preview-app.yaml" <<'EOF'
app_name: preview-app
deploy_channel: preview
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  # Preview warns but passes when runtime manifest unavailable
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

# ==========================================================================
# REVIEW_2: Finding 2 — exact-name matching for provenance secrets
# ==========================================================================

@test "doctor_check_drift rejects superset name NOT_HERMES_AGENT_REF (REVIEW_2)" {
  # Substring match bug: NOT_HERMES_AGENT_REF must not satisfy HERMES_AGENT_REF check
  local secrets_json='[{"Name":"NOT_HERMES_AGENT_REF","Digest":"x"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"y"}]'
  run doctor_check_drift "test-app" "$secrets_json"
  assert_failure
}

@test "doctor_check_drift rejects superset name NOT_HERMES_DEPLOY_CHANNEL (REVIEW_2)" {
  # Substring match bug: NOT_HERMES_DEPLOY_CHANNEL must not satisfy HERMES_DEPLOY_CHANNEL check
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"x"},{"Name":"NOT_HERMES_DEPLOY_CHANNEL","Digest":"y"}]'
  run doctor_check_drift "test-app" "$secrets_json"
  assert_failure
}

# ==========================================================================
# REVIEW_2: Finding 3 — missing deploy_channel in local summary fails
# ==========================================================================

@test "doctor_check_drift fails when local summary exists but deploy_channel is absent (REVIEW_2)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/no-channel-app.yaml" <<'EOF'
app_name: no-channel-app
hermes_agent_ref: abc123def456
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "no-channel-app" "$secrets_json"
  assert_failure
  assert_output --partial "deploy_channel"
}

# ==========================================================================
# REVIEW_3: runtime manifest value comparison
# ==========================================================================

@test "doctor_check_drift detects channel mismatch between local summary and runtime (REVIEW_3)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/chan-drift-app.yaml" <<'EOF'
app_name: chan-drift-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"preview","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "chan-drift-app" "$secrets_json"
  assert_failure
  assert_output --partial "Channel drift"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift detects ref mismatch between local summary and runtime (REVIEW_3)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/ref-drift-app.yaml" <<'EOF'
app_name: ref-drift-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"different000000000000000000000000000000000","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "ref-drift-app" "$secrets_json"
  assert_failure
  assert_output --partial "Ref drift"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift passes when local summary and runtime manifest agree (REVIEW_3)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/agree-app.yaml" <<'EOF'
app_name: agree-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "agree-app" "$secrets_json"
  assert_success
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift passes when runtime manifest unavailable for edge channel (REVIEW_3)" {
  # Edge channel: SSH unavailable → warn-and-pass (only stable fails closed)
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/noruntime-app.yaml" <<'EOF'
app_name: noruntime-app
deploy_channel: edge
hermes_agent_ref: main
EOF
  # MOCK_FLY_RUNTIME_MANIFEST not set → SSH returns empty → edge warns and passes
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "noruntime-app" "$secrets_json"
  assert_success
}

@test "doctor_read_runtime_manifest function exists in lib/doctor.sh (REVIEW_3)" {
  declare -f doctor_read_runtime_manifest >/dev/null 2>&1
}

# ==========================================================================
# REVIEW_4: Finding 1 — fail-closed for missing fields in readable manifest
# ==========================================================================

@test "doctor_check_drift fails when readable runtime manifest is missing deploy_channel (REVIEW_4)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/nodchan-app.yaml" <<'EOF'
app_name: nodchan-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "nodchan-app" "$secrets_json"
  assert_failure
  assert_output --partial "deploy_channel"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift fails when readable runtime manifest is missing hermes_agent_ref (REVIEW_4)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/noref-app.yaml" <<'EOF'
app_name: noref-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "noref-app" "$secrets_json"
  assert_failure
  assert_output --partial "hermes_agent_ref"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift fails when local summary is missing hermes_agent_ref and runtime is readable (REVIEW_4)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/nolocalref-app.yaml" <<'EOF'
app_name: nolocalref-app
deploy_channel: stable
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"abc123def456abc123def456abc123def456abc1","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "nolocalref-app" "$secrets_json"
  assert_failure
  assert_output --partial "hermes_agent_ref"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

# ==========================================================================
# REVIEW_4: Finding 2 — compatibility_policy_version drift detection
# ==========================================================================

@test "doctor_check_drift detects compatibility_policy_version mismatch (REVIEW_4)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/compat-drift-app.yaml" <<'EOF'
app_name: compat-drift-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 1.0.0
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"2.0.0","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "compat-drift-app" "$secrets_json"
  assert_failure
  assert_output --partial "Compat policy drift"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift passes when compatibility_policy_version matches (REVIEW_4)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/compat-match-app.yaml" <<'EOF'
app_name: compat-match-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 1.0.0
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"1.0.0","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "compat-match-app" "$secrets_json"
  assert_success
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift passes when compatibility_policy_version is absent from both (REVIEW_4)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/nocompat-app.yaml" <<'EOF'
app_name: nocompat-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "nocompat-app" "$secrets_json"
  assert_success
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift detects compat drift when local has policy but runtime does not (REVIEW_4)" {
  # Compat drift fires before semver check since values differ
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/compat-gone-app.yaml" <<'EOF'
app_name: compat-gone-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 1.0.0
EOF
  # Runtime has compat policy env var unset → empty string in manifest
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "compat-gone-app" "$secrets_json"
  assert_failure
  assert_output --partial "Compat policy drift"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

# ==========================================================================
# REVIEW_5: Finding 1 — channel-aware runtime-manifest-unavailable policy
#           Finding 2 — intended-ref canonical check (stable/preview)
#           Finding 3 — unknown compat policy version surfacing
# ==========================================================================

@test "doctor_check_drift fails for stable channel when runtime manifest is unavailable (REVIEW_5)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/stable-noruntime.yaml" <<'EOF'
app_name: stable-noruntime
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  # No MOCK_FLY_RUNTIME_MANIFEST → SSH returns empty → stable must fail (fail-closed)
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "stable-noruntime" "$secrets_json"
  assert_failure
  assert_output --partial "stable"
}

@test "doctor_check_drift warns but passes for preview channel when runtime manifest unavailable (REVIEW_5)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/preview-noruntime.yaml" <<'EOF'
app_name: preview-noruntime
deploy_channel: preview
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "preview-noruntime" "$secrets_json"
  assert_success
}

@test "doctor_check_drift warns but passes for edge channel when runtime manifest unavailable (REVIEW_5)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/edge-noruntime.yaml" <<'EOF'
app_name: edge-noruntime
deploy_channel: edge
hermes_agent_ref: main
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "edge-noruntime" "$secrets_json"
  assert_success
}

@test "doctor_check_drift detects unexpected ref for stable channel when both agree on non-canonical (REVIEW_5)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/unexpected-ref.yaml" <<'EOF'
app_name: unexpected-ref
deploy_channel: stable
hermes_agent_ref: deadbeef00000000000000000000000000000000
EOF
  # Both agree on non-canonical ref — a coordinated drift — must be caught
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"deadbeef00000000000000000000000000000000","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "unexpected-ref" "$secrets_json"
  assert_failure
  assert_output --partial "Unexpected ref"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift detects unexpected ref for preview channel not matching canonical (REVIEW_5)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/preview-unexpected.yaml" <<'EOF'
app_name: preview-unexpected
deploy_channel: preview
hermes_agent_ref: deadbeef00000000000000000000000000000000
EOF
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "preview-unexpected" "$secrets_json"
  assert_failure
  assert_output --partial "Unexpected ref"
}

@test "doctor_check_drift flags unknown compat policy version format when both agree (REVIEW_5)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/badcompat.yaml" <<'EOF'
app_name: badcompat
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: not-a-semver
EOF
  # Both agree on non-semver compat version — must be surfaced as unknown
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"not-a-semver","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "badcompat" "$secrets_json"
  assert_failure
  assert_output --partial "Unknown compat policy version"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift flags valid-semver but unsupported compat version when both agree (REVIEW_6)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/badcompat-semver.yaml" <<'EOF'
app_name: badcompat-semver
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 9.9.9
EOF
  # Both agree on valid-semver but unsupported version — must still be surfaced
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"9.9.9","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "badcompat-semver" "$secrets_json"
  assert_failure
  assert_output --partial "Unknown compat policy version: 9.9.9"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

@test "doctor_check_drift passes for supported compat version 1.0.0 (REVIEW_6)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/goodcompat.yaml" <<'EOF'
app_name: goodcompat
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 1.0.0
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"1.0.0","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "goodcompat" "$secrets_json"
  assert_success
  refute_output --partial "Unknown compat policy version"
  unset MOCK_FLY_RUNTIME_MANIFEST
}

# REVIEW_7: Finding 1 — snapshot robustness (_doctor_supported_compat_versions non-fatal)
#           Finding 2 — tri-state drift semantics (unverified vs consistent vs fail)

@test "doctor_check_drift fails with explicit message when snapshot file is missing (REVIEW_7)" {
  local _tmplib
  _tmplib="$(mktemp -d)/lib"
  mkdir -p "$_tmplib"
  local _saved_dir="$_DOCTOR_SCRIPT_DIR"
  _DOCTOR_SCRIPT_DIR="$_tmplib"  # no data/ sibling → snapshot missing
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/snapmissing.yaml" <<'EOF'
app_name: snapmissing
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 1.0.0
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"1.0.0","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "snapmissing" "$secrets_json"
  _DOCTOR_SCRIPT_DIR="$_saved_dir"
  unset MOCK_FLY_RUNTIME_MANIFEST
  assert_failure
  assert_output --partial "supported versions unavailable"
}

@test "doctor_check_drift fails with explicit message when snapshot has no valid policy_version (REVIEW_7)" {
  local _tmplib
  _tmplib="$(mktemp -d)"
  mkdir -p "${_tmplib}/lib" "${_tmplib}/data"
  printf '{"schema_version":"1","policy_version":"not-a-version"}\n' \
    > "${_tmplib}/data/reasoning-snapshot.json"
  local _saved_dir="$_DOCTOR_SCRIPT_DIR"
  _DOCTOR_SCRIPT_DIR="${_tmplib}/lib"
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/snapmalformed.yaml" <<'EOF'
app_name: snapmalformed
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
compatibility_policy_version: 1.0.0
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","compatibility_policy_version":"1.0.0","hermes_fly_version":"0.1.14"}'
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "snapmalformed" "$secrets_json"
  _DOCTOR_SCRIPT_DIR="$_saved_dir"
  unset MOCK_FLY_RUNTIME_MANIFEST
  assert_failure
  assert_output --partial "supported versions unavailable"
}

@test "cmd_doctor reports unverified provenance for preview channel with no runtime manifest (REVIEW_7)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/preview-unver.yaml" <<'EOF'
app_name: preview-unver
deploy_channel: preview
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
  # No MOCK_FLY_RUNTIME_MANIFEST → SSH returns empty → preview warns+passes
  run cmd_doctor "preview-unver"
  assert_success
  assert_output --partial "unverified"
  refute_output --partial "provenance consistent"
}

@test "cmd_doctor reports unverified provenance for edge channel with no runtime manifest (REVIEW_7)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/edge-unver.yaml" <<'EOF'
app_name: edge-unver
deploy_channel: edge
hermes_agent_ref: main
EOF
  # No MOCK_FLY_RUNTIME_MANIFEST → SSH returns empty → edge warns+passes
  run cmd_doctor "edge-unver"
  assert_success
  assert_output --partial "unverified"
  refute_output --partial "provenance consistent"
}

# REVIEW_8: Canonical ref sync invariant and runtime fallback to deploy pin

@test "doctor_check_drift uses deploy pin when doctor constant is stale (REVIEW_8)" {
  # Simulate a future release where deploy.sh was bumped but doctor.sh was not:
  # HERMES_AGENT_DEFAULT_REF points to the new canonical SHA,
  # _DOCTOR_HERMES_AGENT_STABLE_REF still holds the old value.
  local _canon="8eefbef91cd715cfe410bba8c13cfab4eb3040df"
  local _stale="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local _saved_stable="$_DOCTOR_HERMES_AGENT_STABLE_REF"
  _DOCTOR_HERMES_AGENT_STABLE_REF="$_stale"
  HERMES_AGENT_DEFAULT_REF="$_canon"  # deploy constant now in scope
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/stable-deploy-pin.yaml" <<EOF
app_name: stable-deploy-pin
deploy_channel: stable
hermes_agent_ref: ${_canon}
EOF
  export MOCK_FLY_RUNTIME_MANIFEST="{\"deploy_channel\":\"stable\",\"hermes_agent_ref\":\"${_canon}\",\"hermes_fly_version\":\"0.1.14\"}"
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "stable-deploy-pin" "$secrets_json"
  _DOCTOR_HERMES_AGENT_STABLE_REF="$_saved_stable"
  unset HERMES_AGENT_DEFAULT_REF
  unset MOCK_FLY_RUNTIME_MANIFEST
  assert_success
  refute_output --partial "Unexpected ref"
}

@test "doctor canonical refs stay in sync with deploy pins (REVIEW_8)" {
  # Regression guard: source deploy.sh and assert both modules carry the same SHA.
  # This test fails automatically if a release bumps only one module.
  source "${PROJECT_ROOT}/lib/deploy.sh"
  assert_equal "$_DOCTOR_HERMES_AGENT_STABLE_REF" "$HERMES_AGENT_DEFAULT_REF"
  assert_equal "$_DOCTOR_HERMES_AGENT_PREVIEW_REF" "$HERMES_AGENT_PREVIEW_REF"
}

# REVIEW_9: Finding 1 — edge channel local_ref field presence
#           Finding 2 — parsing helper safety under set -euo pipefail

@test "doctor_check_drift fails for edge channel when local summary is missing hermes_agent_ref (REVIEW_9)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/edge-noref.yaml" <<'EOF'
app_name: edge-noref
deploy_channel: edge
# hermes_agent_ref intentionally absent
EOF
  # No MOCK_FLY_RUNTIME_MANIFEST → unverified early-return path
  local secrets_json='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  run doctor_check_drift "edge-noref" "$secrets_json"
  assert_failure
  assert_output --partial "local summary missing hermes_agent_ref"
}

@test "_doctor_extract_yaml_field returns value on match and 0 on miss (REVIEW_9)" {
  run _doctor_extract_yaml_field 'deploy_channel' 'deploy_channel: stable'
  assert_success
  assert_output "stable"
  # No-match case: exits 0, emits empty
  run _doctor_extract_yaml_field 'deploy_channel' 'other_field: value'
  assert_success
  assert_output ""
}

@test "_doctor_extract_json_field returns value on match and 0 on miss (REVIEW_9)" {
  run _doctor_extract_json_field 'deploy_channel' '{"deploy_channel":"stable","foo":"bar"}'
  assert_success
  assert_output "stable"
  # No-match case: exits 0, emits empty
  run _doctor_extract_json_field 'deploy_channel' '{"other_field":"value"}'
  assert_success
  assert_output ""
}

@test "doctor_check_drift produces explicit message under set -euo pipefail when local ref absent (REVIEW_9)" {
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  cat > "${HERMES_FLY_CONFIG_DIR}/deploys/strict-noref.yaml" <<'EOF'
app_name: strict-noref
deploy_channel: stable
# hermes_agent_ref intentionally absent
EOF
  export MOCK_FLY_RUNTIME_MANIFEST='{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'
  local _config_dir="$HERMES_FLY_CONFIG_DIR"
  local _project_root="$PROJECT_ROOT"
  local _mocks_dir="${BATS_TEST_DIRNAME}/mocks"
  local _secrets='[{"Name":"HERMES_AGENT_REF","Digest":"abc123"},{"Name":"HERMES_DEPLOY_CHANNEL","Digest":"chan_hash"}]'
  local _manifest="$MOCK_FLY_RUNTIME_MANIFEST"
  run bash -c "
    set -euo pipefail
    export PATH=\"${_mocks_dir}:\$PATH\"
    export HERMES_FLY_CONFIG_DIR='${_config_dir}'
    export MOCK_FLY_RUNTIME_MANIFEST='${_manifest}'
    source '${_project_root}/lib/ui.sh'
    source '${_project_root}/lib/fly-helpers.sh'
    source '${_project_root}/lib/doctor.sh'
    doctor_check_drift 'strict-noref' '${_secrets}'
  "
  unset MOCK_FLY_RUNTIME_MANIFEST
  assert_failure
  assert_output --partial "local summary missing hermes_agent_ref"
}
