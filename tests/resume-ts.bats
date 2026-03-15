#!/usr/bin/env bats
# tests/resume-ts.bats — Parity tests for TS resume command implementation

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

@test "TS resume with -a flag exits 0 and shows Resuming deployment checks" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js resume -a test-app 2>&1
  '
  assert_success
  assert_output --partial "Resuming deployment checks"
}

@test "TS resume with -a flag exits 0 and shows Resume complete" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js resume -a test-app 2>&1
  '
  assert_success
  assert_output --partial "Resume complete"
}

@test "TS resume with no app specified exits 1 and shows error" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    tmp="$(mktemp -d)"
    trap "rm -rf ${tmp}" EXIT
    mkdir -p "${tmp}/config"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${tmp}/config" \
      node dist/cli.js resume 2>&1
  '
  assert_failure
  assert_output --partial "No app specified"
}

@test "TS resume with fly status failure exits 1" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      MOCK_FLY_STATUS=fail \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js resume -a test-app 2>&1
  '
  assert_failure
  assert_output --partial "Could not fetch status"
}
