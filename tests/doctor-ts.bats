#!/usr/bin/env bats
# tests/doctor-ts.bats — Parity tests for TS doctor command implementation

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  cd "${PROJECT_ROOT}"
  npm run build >/dev/null 2>&1
}

teardown() {
  _common_teardown
}

@test "TS doctor with all checks passing exits 0 and shows PASS" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    # Provide deploy provenance for drift check
    mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
    cat > "${HERMES_FLY_CONFIG_DIR}/deploys/test-app.yaml" <<EOF
app_name: test-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
    export MOCK_FLY_RUNTIME_MANIFEST='"'"'{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'"'"'
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js doctor -a test-app 2>&1
  '
  assert_success
  assert_output --partial "PASS"
}

@test "TS doctor with machine stopped exits 1 and shows FAIL" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      MOCK_FLY_MACHINE_STATE=stopped \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js doctor -a test-app 2>&1
  '
  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "fly machine start"
}

@test "TS doctor with no app specified exits 1 and shows error" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    tmp="$(mktemp -d)"
    trap "rm -rf ${tmp}" EXIT
    mkdir -p "${tmp}/config"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${tmp}/config" \
      node dist/cli.js doctor 2>&1
  '
  assert_failure
  assert_output --partial "No app specified"
}

@test "TS doctor shows 8 passed 0 failed summary with all checks passing" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
    cat > "${HERMES_FLY_CONFIG_DIR}/deploys/test-app.yaml" <<EOF
app_name: test-app
deploy_channel: stable
hermes_agent_ref: 8eefbef91cd715cfe410bba8c13cfab4eb3040df
EOF
    export MOCK_FLY_RUNTIME_MANIFEST='"'"'{"deploy_channel":"stable","hermes_agent_ref":"8eefbef91cd715cfe410bba8c13cfab4eb3040df","hermes_fly_version":"0.1.14"}'"'"'
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js doctor -a test-app 2>&1
  '
  assert_success
  assert_output --partial "8 passed"
  assert_output --partial "0 failed"
}
