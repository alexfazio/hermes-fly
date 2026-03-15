#!/usr/bin/env bats
# tests/verify-pr-full-commander.bats — Guards for hybrid dispatch removal
# After Slice 7: hermes-fly must be a thin Node.js launcher with no Bash runtime dependency.

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  cd "${PROJECT_ROOT}"
}

teardown() {
  _common_teardown
}

# Guard: hermes-fly entrypoint must not source lib/ at runtime
@test "hermes-fly does not source lib/*.sh at startup" {
  run grep -n "^source.*lib/" "${PROJECT_ROOT}/hermes-fly"
  assert_failure  # grep exit 1 = no matches = pass
}

# Guard: hermes-fly must not reference HERMES_FLY_IMPL_MODE
@test "hermes-fly does not reference HERMES_FLY_IMPL_MODE" {
  run grep -n "HERMES_FLY_IMPL_MODE" "${PROJECT_ROOT}/hermes-fly"
  assert_failure  # grep exit 1 = no matches = pass
}

# Guard: hermes-fly must not reference HERMES_FLY_TS_COMMANDS
@test "hermes-fly does not reference HERMES_FLY_TS_COMMANDS" {
  run grep -n "HERMES_FLY_TS_COMMANDS" "${PROJECT_ROOT}/hermes-fly"
  assert_failure  # grep exit 1 = no matches = pass
}

# Behavior: all 9 commands are reachable via ./hermes-fly
@test "hermes-fly help shows all 9 commands" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" node dist/cli.js help 2>&1
  '
  assert_success
  assert_output --partial "deploy"
  assert_output --partial "resume"
  assert_output --partial "list"
  assert_output --partial "status"
  assert_output --partial "logs"
  assert_output --partial "doctor"
  assert_output --partial "destroy"
  assert_output --partial "help"
  assert_output --partial "version"
}

# Behavior: hermes-fly is a thin launcher — must invoke node dist/cli.js
@test "hermes-fly entrypoint invokes node dist/cli.js" {
  run grep -n "node.*dist/cli.js" "${PROJECT_ROOT}/hermes-fly"
  assert_success
}

# Behavior: list command works via hermes-fly
@test "hermes-fly list works" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      "${PROJECT_ROOT}/hermes-fly" list 2>&1
  '
  assert_success
}

# Behavior: version command works via hermes-fly
@test "hermes-fly version works" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      "${PROJECT_ROOT}/hermes-fly" version 2>&1
  '
  assert_success
  assert_output --partial "hermes-fly"
}

# Static: src/ must not reference lib/*.sh, cmd_deploy, cmd_doctor, cmd_destroy
@test "src/ has no references to lib/*.sh or legacy cmd_ functions" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    if grep -rn "lib/.*\.sh\|cmd_deploy\b\|cmd_doctor\b\|cmd_destroy\b" src/ 2>/dev/null; then
      exit 1
    fi
    exit 0
  '
  assert_success
}

# Static: verify-pr-full-commander.sh exists and is executable
@test "scripts/verify-pr-full-commander.sh exists and is executable" {
  assert [ -f "${PROJECT_ROOT}/scripts/verify-pr-full-commander.sh" ]
  assert [ -x "${PROJECT_ROOT}/scripts/verify-pr-full-commander.sh" ]
}

# Functional: verify-pr-full-commander.sh outputs all four category lines
@test "scripts/verify-pr-full-commander.sh outputs all four PASS categories" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    PATH="tests/mocks:${PATH}" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      bash scripts/verify-pr-full-commander.sh 2>&1
  '
  assert_success
  assert_output --partial "[HAPPY] PASS"
  assert_output --partial "[EDGE] PASS"
  assert_output --partial "[FAILURE] PASS"
  assert_output --partial "[REGRESSION] PASS"
}
