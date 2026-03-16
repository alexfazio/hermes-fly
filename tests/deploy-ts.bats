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
    HOME_DIR="$(mktemp -d)"
    trap "rm -rf \"${HOME_DIR}\"" EXIT
    # Keep node but strip fly from PATH and isolate HOME so ~/.fly/bin/fly is absent
    NODE_DIR="$(dirname "$(command -v node)")"
    PATH="${NODE_DIR}:/usr/bin:/bin" \
      HOME="${HOME_DIR}" \
      HERMES_FLY_CONFIG_DIR="${HOME_DIR}/.hermes-fly" \
      OPENROUTER_API_KEY="sk-test-dummy" \
      node dist/cli.js deploy --no-auto-install 2>&1
  '
  assert_failure
  assert_output --partial "auto-install disabled"
}

@test "TS deploy auto-installs fly when missing" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    HOME_DIR="$(mktemp -d)"
    trap "rm -rf \"${HOME_DIR}\"" EXIT
    NODE_DIR="$(dirname "$(command -v node)")"
    INSTALL_CMD="mkdir -p \"${HOME_DIR}/.fly/bin\" && cp \"${PROJECT_ROOT}/tests/mocks/fly\" \"${HOME_DIR}/.fly/bin/fly\" && chmod +x \"${HOME_DIR}/.fly/bin/fly\""
    PATH="${NODE_DIR}:/usr/bin:/bin" \
      HOME="${HOME_DIR}" \
      HERMES_FLY_CONFIG_DIR="${HOME_DIR}/.hermes-fly" \
      HERMES_FLY_FLYCTL_INSTALL_CMD="${INSTALL_CMD}" \
      OPENROUTER_API_KEY="sk-test-dummy" \
      HERMES_FLY_APP_NAME="test-app" \
      HERMES_FLY_REGION="iad" \
      HERMES_FLY_VM_SIZE="shared-cpu-1x" \
      HERMES_FLY_VOLUME_SIZE="1" \
      HERMES_FLY_MODEL="anthropic/claude-sonnet-4-20250514" \
      node dist/cli.js deploy 2>&1
  '
  assert_success
  assert_output --partial "fly CLI installed successfully."
  refute_output --partial "Missing prerequisite: fly"
}
