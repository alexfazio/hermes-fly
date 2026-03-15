#!/usr/bin/env bats
# tests/deploy-ts.bats — Parity tests for TS deploy command implementation

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

@test "TS deploy --help shows Deployment Wizard" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    node dist/cli.js deploy --help 2>&1
  '
  assert_success
  assert_output --partial "Deployment Wizard"
}

@test "TS deploy --help mentions --no-auto-install" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    node dist/cli.js deploy --help 2>&1
  '
  assert_success
  assert_output --partial "--no-auto-install"
}

@test "TS deploy --help mentions --channel" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    node dist/cli.js deploy --help 2>&1
  '
  assert_success
  assert_output --partial "--channel"
}

@test "TS deploy --no-auto-install shows auto-install disabled when fly missing" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    # Keep node but strip fly from PATH
    NODE_DIR="$(dirname "$(command -v node)")"
    PATH="${NODE_DIR}:/usr/bin:/bin" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js deploy --no-auto-install 2>&1
  '
  assert_failure
  assert_output --partial "auto-install disabled"
}
