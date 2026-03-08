#!/usr/bin/env bats
# tests/integration.bats — Integration tests for hermes-fly entry point

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

teardown() {
  _common_teardown
}

# --- Version ---

@test "hermes-fly --version outputs version string" {
  run "${PROJECT_ROOT}/hermes-fly" --version
  assert_success
  assert_output --partial "hermes-fly 0.1.11"
}

@test "hermes-fly version outputs version string" {
  run "${PROJECT_ROOT}/hermes-fly" version
  assert_success
  assert_output --partial "hermes-fly 0.1.11"
}

# --- Help ---

@test "hermes-fly help lists all commands" {
  run "${PROJECT_ROOT}/hermes-fly" help
  assert_success
  assert_output --partial "deploy"
  assert_output --partial "status"
  assert_output --partial "logs"
  assert_output --partial "doctor"
  assert_output --partial "destroy"
}

@test "hermes-fly --help same as help" {
  run "${PROJECT_ROOT}/hermes-fly" --help
  assert_success
  assert_output --partial "deploy"
}

@test "hermes-fly with no args shows help" {
  run "${PROJECT_ROOT}/hermes-fly"
  assert_success
  assert_output --partial "deploy"
}

# --- Unknown command ---

@test "hermes-fly unknowncmd exits 1" {
  run "${PROJECT_ROOT}/hermes-fly" unknowncmd
  assert_failure
  assert_output --partial "Unknown command"
}

# --- Deploy help ---

@test "hermes-fly deploy --help shows deploy help" {
  run "${PROJECT_ROOT}/hermes-fly" deploy --help
  assert_success
  assert_output --partial "Deployment Wizard"
}

# --- Status with -a flag ---

@test "hermes-fly status with -a flag works" {
  # Save a config so config_resolve_app can find it (not strictly needed
  # since -a flag takes precedence, but good for completeness)
  source "${PROJECT_ROOT}/lib/config.sh"
  config_save_app "test-app" "ord"

  run "${PROJECT_ROOT}/hermes-fly" status -a test-app
  assert_success
  assert_output --partial "test-app"
}

# --- Deploy with --no-auto-install flag ---

@test "hermes-fly deploy --help mentions --no-auto-install" {
  run "${PROJECT_ROOT}/hermes-fly" deploy --help
  assert_success
  assert_output --partial "--no-auto-install"
}

@test "hermes-fly deploy --no-auto-install skips install when fly not on PATH" {
  export PATH="/usr/bin:/bin"  # exclude mocks
  export HERMES_FLY_TEST_MODE=1
  run "${PROJECT_ROOT}/hermes-fly" deploy --no-auto-install 2>&1
  # Should show error about missing prerequisites with auto-install disabled
  assert_output --partial "auto-install disabled"
}
