#!/usr/bin/env bats
# tests/ui.bats — Tests for lib/ui.sh UI helpers

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  source "${PROJECT_ROOT}/lib/ui.sh"
}

teardown() {
  _common_teardown
}

# --- ui_info ---

@test "ui_info prints to stderr" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; ui_info "hello" 2>&1'
  assert_success
  assert_output --partial "hello"
  # Verify it goes to stderr, not stdout: run with stderr redirected away
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; ui_info "hello" 2>/dev/null'
  assert_success
  assert_output ""
}

# --- ui_success ---

@test "ui_success prints to stderr" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; ui_success "done" 2>&1'
  assert_success
  assert_output --partial "done"
  # Verify it goes to stderr, not stdout: run with stderr redirected away
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; ui_success "done" 2>/dev/null'
  assert_success
  assert_output ""
}

# --- ui_warn ---

@test "ui_warn prints to stderr" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; ui_warn "caution" 2>&1'
  assert_success
  assert_output --partial "caution"
  # Verify it goes to stderr, not stdout: run with stderr redirected away
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; ui_warn "caution" 2>/dev/null'
  assert_success
  assert_output ""
}

# --- ui_error ---

@test "ui_error prints to stderr" {
  run bash -c 'source lib/ui.sh; ui_error "hello" 2>&1'
  assert_success
  assert_output --partial "hello"
  # Verify it goes to stderr, not stdout: run with stderr redirected away
  run bash -c 'source lib/ui.sh; ui_error "hello" 2>/dev/null'
  assert_success
  assert_output ""
}

# --- NO_COLOR ---

@test "NO_COLOR=1 disables color codes" {
  export NO_COLOR=1
  run ui_info "test"
  assert_success
  refute_output --partial $'\033'
  refute_output --partial $'\e'
}

# --- ui_confirm ---

@test "ui_confirm returns 0 for y" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; echo "y" | ui_confirm "proceed?"'
  assert_success
}

@test "ui_confirm returns 1 for n" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; echo "n" | ui_confirm "proceed?"'
  assert_failure
}

@test "ui_confirm returns 1 for empty" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; echo "" | ui_confirm "proceed?"'
  assert_failure
}

# --- ui_select ---

@test "ui_select stores second option" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; echo "2" | ui_select "Pick:" RESULT A B C; echo "$RESULT"'
  assert_success
  assert_output --partial "B"
}

# --- ui_step ---

@test "ui_step formats correctly" {
  run ui_step 1 5 "Creating volume"
  assert_success
  assert_output --partial "[1/5]"
  assert_output --partial "Creating volume"
}

# --- ui_banner ---

@test "ui_banner outputs title" {
  run ui_banner "Welcome"
  assert_success
  assert_output --partial "Welcome"
}

# --- log_init ---

@test "log_init creates log file" {
  run log_init
  assert_success
  [[ -f "${HERMES_FLY_LOG_DIR}/hermes-fly.log" ]]
}

# --- log_info ---

@test "log_info appends timestamped line" {
  log_init
  log_info "test message"
  run cat "${HERMES_FLY_LOG_DIR}/hermes-fly.log"
  assert_output --partial "INFO"
  assert_output --partial "test message"
}

# --- log_error ---

@test "log_error appends ERROR line" {
  log_init
  log_error "bad"
  run cat "${HERMES_FLY_LOG_DIR}/hermes-fly.log"
  assert_output --partial "ERROR"
  assert_output --partial "bad"
}
