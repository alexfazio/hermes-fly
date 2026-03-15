#!/usr/bin/env bats
# tests/destroy-ts.bats — Parity tests for TS destroy command implementation

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  # Build TS CLI artifact
  cd "${PROJECT_ROOT}"
  npm run build >/dev/null 2>&1
}

teardown() {
  _common_teardown
}

@test "TS destroy --force with -a APP succeeds when fly mock returns success" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js destroy -a test-app --force 2>&1
  '
  assert_success
}

@test "TS destroy --force with nonexistent app returns exit 4" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      MOCK_FLY_APPS_DESTROY=fail \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      node dist/cli.js destroy -a nonexistent-app --force 2>&1
  '
  assert_failure
  [ "$status" -eq 4 ]
  assert_output --partial "not found"
}

@test "TS destroy 'no' confirmation aborts" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      printf "no\n" | node dist/cli.js destroy -a test-app 2>&1
  '
  assert_failure
  assert_output --partial "Aborted"
}

@test "TS destroy 'yes' confirmation proceeds" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      printf "yes\n" | node dist/cli.js destroy -a test-app 2>&1
  '
  assert_success
}

@test "TS destroy with no app and no config returns exit 1 with error" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    tmp="$(mktemp -d)"
    trap "rm -rf ${tmp}" EXIT
    mkdir -p "${tmp}/config"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${tmp}/config" \
      node dist/cli.js destroy 2>&1
  '
  assert_failure
  assert_output --partial "No app specified"
}
