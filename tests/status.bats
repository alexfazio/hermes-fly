#!/usr/bin/env bats
# tests/status.bats — Tests for lib/status.sh status command

setup() {
  load 'test_helper/common-setup'
  _common_setup
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/fly-helpers.sh"
  source "${PROJECT_ROOT}/lib/status.sh"
}

teardown() {
  _common_teardown
}

# --- cmd_status ---

@test "cmd_status shows machine state and URL" {
  run cmd_status "test-app"
  assert_success
  assert_output --partial "test-app"
  assert_output --partial "started"
  assert_output --partial "fly.dev"
}

@test "cmd_status with nonexistent app exits 1" {
  export MOCK_FLY_STATUS=fail
  run cmd_status "bad-app"
  assert_failure
}

# --- status_estimate_cost ---

@test "status_estimate_cost for shared-cpu-1x with 5GB" {
  run status_estimate_cost "shared-cpu-1x" 5
  assert_success
  assert_output --partial '$'
  # shared-cpu-1x = $2.02 base + 5 * $0.15 = $2.02 + $0.75 = $2.77
  # Check the value is reasonable (between $2 and $10)
  local amount
  amount="$(echo "$output" | sed 's/[^0-9.]//g')"
  [ "$(echo "$amount > 2" | bc)" -eq 1 ]
  [ "$(echo "$amount < 10" | bc)" -eq 1 ]
}

@test "status_estimate_cost for performance-2x returns ~65" {
  run status_estimate_cost "performance-2x" 5
  assert_success
  # performance-2x = $64.39 base + 5 * $0.15 = $65.14
  assert_output '~$65.14/mo'
}

@test "status_estimate_cost for performance-1x returns ~32" {
  run status_estimate_cost "performance-1x" 3
  assert_success
  # performance-1x = $32.19 base + 3 * $0.15 = $32.19 + $0.45 = $32.64
  assert_output '~$32.64/mo'
}

@test "status_estimate_cost for dedicated-cpu-1x returns ~23" {
  run status_estimate_cost "dedicated-cpu-1x" 1
  assert_success
  # dedicated-cpu-1x = $23.00 base + 1 * $0.15 = $23.15
  assert_output '~$23.15/mo'
}
