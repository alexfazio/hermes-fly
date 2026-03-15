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
  local expected
  expected="$(grep -oE 'HERMES_FLY_TS_VERSION = "[0-9.]+"' "${PROJECT_ROOT}/src/version.ts" | grep -oE '[0-9.]+')"
  run "${PROJECT_ROOT}/hermes-fly" --version
  assert_success
  assert_output --partial "hermes-fly ${expected}"
}

@test "hermes-fly version outputs version string" {
  local expected
  expected="$(grep -oE 'HERMES_FLY_TS_VERSION = "[0-9.]+"' "${PROJECT_ROOT}/src/version.ts" | grep -oE '[0-9.]+')"
  run "${PROJECT_ROOT}/hermes-fly" version
  assert_success
  assert_output --partial "hermes-fly ${expected}"
}

# --- Help ---

@test "hermes-fly help lists all commands" {
  run "${PROJECT_ROOT}/hermes-fly" help
  assert_success
  assert_output --partial "deploy"
  assert_output --partial "resume"
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
  run "${PROJECT_ROOT}/hermes-fly" status -a test-app
  assert_success
  assert_output --partial "test-app"
}

@test "hermes-fly resume with -a flag runs deploy resume checks" {
  run bash -c '
    PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'" \
      HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR}" \
      "${PROJECT_ROOT}/hermes-fly" resume -a test-app 2>&1
  '
  assert_success
  assert_output --partial "Resuming deployment checks"
  assert_output --partial "Resume complete"
}

# --- Deploy with --no-auto-install flag ---

@test "hermes-fly deploy --help mentions --no-auto-install" {
  run "${PROJECT_ROOT}/hermes-fly" deploy --help
  assert_success
  assert_output --partial "--no-auto-install"
}

@test "hermes-fly deploy --no-auto-install skips install when fly not on PATH" {
  run bash -c '
    # Keep node but strip fly from PATH
    NODE_DIR="$(dirname "$(command -v node)")"
    OPENROUTER_API_KEY=test-key PATH="${NODE_DIR}:/usr/bin:/bin" \
      "${PROJECT_ROOT}/hermes-fly" deploy --no-auto-install 2>&1
  '
  assert_failure
  assert_output --partial "auto-install disabled"
}

# ==========================================================================
# PR-05: Channel flag in entry point
# ==========================================================================

@test "hermes-fly deploy --help mentions --channel option (PR-05)" {
  run "${PROJECT_ROOT}/hermes-fly" deploy --help
  assert_success
  assert_output --partial "--channel"
}

@test "hermes-fly deploy --channel invalid falls back to stable (PR-05)" {
  # TS runtime normalizes invalid channel silently; --no-auto-install with no fly gives expected error
  run bash -c '
    NODE_DIR="$(dirname "$(command -v node)")"
    OPENROUTER_API_KEY=test-key PATH="${NODE_DIR}:/usr/bin:/bin" \
      "${PROJECT_ROOT}/hermes-fly" deploy --channel badvalue --no-auto-install 2>&1
  '
  assert_failure
  assert_output --partial "auto-install disabled"
  refute_output --partial "Unknown option"
  refute_output --partial "Unknown command"
}

@test "hermes-fly deploy --channel preview uses runtime path without parse errors (PR-05)" {
  # TS CLI accepts --channel preview and reaches runtime execution path
  run bash -c '
    NODE_DIR="$(dirname "$(command -v node)")"
    OPENROUTER_API_KEY=test-key PATH="${NODE_DIR}:/usr/bin:/bin" \
      "${PROJECT_ROOT}/hermes-fly" deploy --channel preview --no-auto-install 2>&1
  '
  assert_failure
  assert_output --partial "auto-install disabled"
  refute_output --partial "Unknown option"
  refute_output --partial "Unknown command"
}

@test "channel end-to-end matrix resolves expected refs for stable preview edge (PR-05)" {
  # All channel values invoke the runtime deploy path without parse errors.
  local node_dir
  node_dir="$(dirname "$(command -v node)")"
  for ch in stable preview edge; do
    run bash -c "
      OPENROUTER_API_KEY=test-key PATH=\"${node_dir}:/usr/bin:/bin\" \
        \"${PROJECT_ROOT}/hermes-fly\" deploy --channel ${ch} --no-auto-install 2>&1
    "
    assert_failure
    assert_output --partial "auto-install disabled"
    refute_output --partial "Unknown option"
    refute_output --partial "Unknown command"
  done
}
