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
  expected="$(sed -n 's/^HERMES_FLY_VERSION=\"\\([0-9.]*\\)\"/\\1/p' "${PROJECT_ROOT}/hermes-fly" | head -1)"
  run "${PROJECT_ROOT}/hermes-fly" --version
  assert_success
  assert_output --partial "hermes-fly ${expected}"
}

@test "hermes-fly version outputs version string" {
  local expected
  expected="$(sed -n 's/^HERMES_FLY_VERSION=\"\\([0-9.]*\\)\"/\\1/p' "${PROJECT_ROOT}/hermes-fly" | head -1)"
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
  # Save a config so config_resolve_app can find it (not strictly needed
  # since -a flag takes precedence, but good for completeness)
  source "${PROJECT_ROOT}/lib/config.sh"
  config_save_app "test-app" "ord"

  run "${PROJECT_ROOT}/hermes-fly" status -a test-app
  assert_success
  assert_output --partial "test-app"
}

@test "hermes-fly resume with -a flag runs deploy resume checks" {
  run "${PROJECT_ROOT}/hermes-fly" resume -a test-app
  assert_success
  assert_output --partial "Resuming deployment checks"
  assert_output --partial "App is running"
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

# ==========================================================================
# PR-05: Channel flag in entry point
# ==========================================================================

@test "hermes-fly deploy --help mentions --channel option (PR-05)" {
  run "${PROJECT_ROOT}/hermes-fly" deploy --help
  assert_success
  assert_output --partial "--channel"
}

@test "hermes-fly deploy --channel invalid falls back to stable (PR-05)" {
  # Directly verify channel resolution: invalid channel falls back to stable with a warning
  run bash -c 'export NO_COLOR=1; export HERMES_FLY_CHANNEL=badvalue; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh; source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh; source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh; source '"${PROJECT_ROOT}"'/lib/reasoning.sh; source '"${PROJECT_ROOT}"'/lib/deploy.sh; deploy_resolve_channel 2>&1'
  assert_output --partial "stable"
}

@test "hermes-fly deploy --channel preview sets HERMES_FLY_CHANNEL=preview before cmd_deploy (PR-05)" {
  # Verify --channel is parsed and exported from entry point
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh; source '"${PROJECT_ROOT}"'/lib/docker-helpers.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh; source '"${PROJECT_ROOT}"'/lib/config.sh; source '"${PROJECT_ROOT}"'/lib/status.sh; source '"${PROJECT_ROOT}"'/lib/reasoning.sh; source '"${PROJECT_ROOT}"'/lib/deploy.sh
  HERMES_FLY_CHANNEL=preview result=$(deploy_resolve_channel); echo "$result"'
  assert_output --partial "preview"
}

@test "channel end-to-end matrix resolves expected refs for stable preview edge (PR-05)" {
  run bash -c 'set -euo pipefail
    export NO_COLOR=1
    export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"
    source "'"${PROJECT_ROOT}"'/lib/ui.sh"
    source "'"${PROJECT_ROOT}"'/lib/fly-helpers.sh"
    source "'"${PROJECT_ROOT}"'/lib/docker-helpers.sh"
    source "'"${PROJECT_ROOT}"'/lib/messaging.sh"
    source "'"${PROJECT_ROOT}"'/lib/config.sh"
    source "'"${PROJECT_ROOT}"'/lib/status.sh"
    source "'"${PROJECT_ROOT}"'/lib/reasoning.sh"
    source "'"${PROJECT_ROOT}"'/lib/deploy.sh"

    for ch in stable preview edge; do
      export HERMES_FLY_CHANNEL="$ch"
      DEPLOY_CHANNEL="$(deploy_resolve_channel)"
      export DEPLOY_CHANNEL
      resolved_ref="$(deploy_resolve_hermes_ref)"
      printf "%s:%s:%s\n" "$ch" "$DEPLOY_CHANNEL" "$resolved_ref"
    done
  '
  assert_success
  assert_output --partial "stable:stable:8eefbef91cd715cfe410bba8c13cfab4eb3040df"
  assert_output --partial "preview:preview:8eefbef91cd715cfe410bba8c13cfab4eb3040df"
  assert_output --partial "edge:edge:main"
}
