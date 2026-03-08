#!/usr/bin/env bats
# tests/fly-helpers.bats — Tests for lib/fly-helpers.sh Fly.io CLI wrappers

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export HERMES_FLY_RETRY_SLEEP=0
  source "${PROJECT_ROOT}/lib/fly-helpers.sh"
}

teardown() {
  _common_teardown
}

# --- fly_check_installed ---

@test "fly_check_installed returns 0 with mock fly" {
  run fly_check_installed
  assert_success
}

@test "fly_check_installed fails when fly not on PATH" {
  # Override PATH to exclude mocks dir so 'fly' is not found
  PATH="/usr/bin:/bin"
  run fly_check_installed
  assert_failure
}

@test "fly_check_installed fails when only flyctl exists on PATH" {
  # Create a mock flyctl
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"

  PATH="$fake_dir:/usr/bin:/bin"
  run fly_check_installed
  assert_failure

  rm -rf "$fake_dir"
}

@test "fly_check_installed delegates to _prereqs_check_tool_available when prereqs.sh sourced" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_success

  rm -rf "$fake_home"
}

@test "fly_check_installed falls back to direct command -v when prereqs.sh not sourced" {
  run bash -c "
    # Don't source prereqs.sh — only fly-helpers.sh
    source '${PROJECT_ROOT}/lib/ui.sh'
    # Undefine _prereqs_check_tool_available if it exists
    unset -f _prereqs_check_tool_available 2>/dev/null || true

    PATH='${BATS_TEST_DIRNAME}/mocks:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_success
}

@test "fly_check_installed returns 0 when fly is in ~/.fly/bin via prereqs delegation" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_success

  rm -rf "$fake_home"
}

@test "fly_check_installed returns 1 with error message when all checks fail" {
  local fake_home
  fake_home="$(mktemp -d)"
  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks and ~/.fly/bin doesn't exist

  run bash -c "
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_failure
  assert_output --partial "Error"

  rm -rf "$fake_home"
}

@test "fly_check_installed returns 1 when only flyctl exists (no fly sibling) in fallback path" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    unset -f _prereqs_check_tool_available 2>/dev/null || true
    PATH='$fake_dir:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_failure
  assert_output --partial "Error"

  rm -rf "$fake_dir"
}

@test "fly_check_installed fallback restores PATH when flyctl probe fails" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    unset -f _prereqs_check_tool_available 2>/dev/null || true
    PATH='$fake_dir:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    before=\"\$PATH\"
    fly_check_installed >/dev/null 2>&1
    rc=\$?
    after=\"\$PATH\"
    echo \"rc=\$rc\"
    echo \"before=\$before\"
    echo \"after=\$after\"
  "
  assert_success
  assert_line "rc=1"
  assert_line "before=$fake_dir:/usr/bin:/bin"
  assert_line "after=$fake_dir:/usr/bin:/bin"

  rm -rf "$fake_dir"
}

@test "fly_check_installed returns 0 when flyctl exists with fly sibling in fallback path" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"
  # Create fly symlink alongside flyctl
  ln -s "$fake_dir/flyctl" "$fake_dir/fly"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    unset -f _prereqs_check_tool_available 2>/dev/null || true
    PATH='$fake_dir:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_success

  rm -rf "$fake_dir"
}

@test "fly_check_installed returns 0 when fly directly on PATH in fallback path" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/fly"
  chmod +x "$fake_dir/fly"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    unset -f _prereqs_check_tool_available 2>/dev/null || true
    PATH='$fake_dir:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/fly-helpers.sh'
    fly_check_installed
  "
  assert_success

  rm -rf "$fake_dir"
}

# --- fly_check_version ---

@test "fly_check_version returns 0 for v0.3.52" {
  export MOCK_FLY_VERSION="0.3.52"
  run fly_check_version
  assert_success
}

@test "fly_check_version fails for v0.1.9" {
  export MOCK_FLY_VERSION="0.1.9"
  run fly_check_version
  assert_failure
}

# --- fly_check_auth ---

@test "fly_check_auth returns 0 when authenticated" {
  run fly_check_auth
  assert_success
}

@test "fly_check_auth returns exit 2 when not authenticated" {
  export MOCK_FLY_AUTH=fail
  run fly_check_auth
  assert_failure
  assert [ "$status" -eq 2 ]
}

# --- fly_create_app ---

@test "fly_create_app passes name and returns JSON" {
  run fly_create_app "my-app"
  assert_success
  assert_output --partial "my-app"
}

@test "fly_create_app passes org when provided" {
  run fly_create_app "my-app" "my-org"
  assert_success
  assert_output --partial "my-app"
}

# --- fly_set_secrets ---

@test "fly_set_secrets passes all pairs" {
  run fly_set_secrets "my-app" "KEY1=val1" "KEY2=val2"
  assert_success
}

# --- fly_status ---

@test "fly_status returns JSON with app info" {
  run fly_status "test-app"
  assert_success
  assert_output --partial "test-app"
}

# --- fly_retry ---

@test "fly_retry succeeds on first try" {
  run fly_retry 3 true
  assert_success
}

@test "fly_retry fails after max attempts" {
  run fly_retry 3 false
  assert_failure
}

# --- fly_get_vm_sizes ---

@test "fly_get_vm_sizes returns JSON" {
  run fly_get_vm_sizes
  assert_success
  assert_output --partial "shared-cpu-1x"
}

# --- fly_get_orgs ---

@test "fly_get_orgs returns JSON" {
  run fly_get_orgs
  assert_success
  assert_output --partial "personal"
}

# --- fly_check_auth_interactive ---

@test "fly_check_auth_interactive succeeds when already authed" {
  run fly_check_auth_interactive
  assert_success
}

@test "fly_check_auth_interactive retries after user presses Enter" {
  export MOCK_FLY_AUTH_SEQUENCE="fail,success"
  export MOCK_FLY_AUTH_COUNTER_FILE="${TEST_TEMP_DIR}/auth_counter"
  # Simulate user pressing Enter for the retry prompt
  run fly_check_auth_interactive <<< ""
  assert_success
}

# --- fly_deploy timeout ---

@test "fly_deploy passes --wait-timeout to fly command" {
  local build_dir="${TEST_TEMP_DIR}/deploy_dir"
  mkdir -p "$build_dir"
  export MOCK_FLY_DEPLOY_ARGS_FILE="${TEST_TEMP_DIR}/deploy_args"
  fly_deploy "test-app" "$build_dir" "3m0s" >/dev/null
  run cat "${MOCK_FLY_DEPLOY_ARGS_FILE}"
  assert_output --partial "--wait-timeout"
  assert_output --partial "3m0s"
}

@test "fly_deploy uses default timeout when no third arg" {
  local build_dir="${TEST_TEMP_DIR}/deploy_dir"
  mkdir -p "$build_dir"
  export MOCK_FLY_DEPLOY_ARGS_FILE="${TEST_TEMP_DIR}/deploy_args2"
  fly_deploy "test-app" "$build_dir" >/dev/null
  run cat "${MOCK_FLY_DEPLOY_ARGS_FILE}"
  assert_output --partial "--wait-timeout"
  assert_output --partial "5m0s"
}

@test "fly_check_auth_interactive returns EXIT_AUTH after second failure" {
  export MOCK_FLY_AUTH=fail
  run fly_check_auth_interactive <<< ""
  assert_failure
  assert [ "$status" -eq 2 ]
}

@test "fly_check_auth_interactive completes on closed stdin" {
  export MOCK_FLY_AUTH=fail
  run fly_check_auth_interactive < /dev/null
  assert_failure
  assert [ "$status" -eq 2 ]
}
