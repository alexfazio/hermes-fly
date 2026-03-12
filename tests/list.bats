#!/usr/bin/env bats
# tests/list.bats — Tests for lib/list.sh fleet listing

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/fly-helpers.sh"
  source "${PROJECT_ROOT}/lib/config.sh"
  source "${PROJECT_ROOT}/lib/list.sh"
}

teardown() {
  _common_teardown
}

@test "cmd_list shows no agents message when config is empty" {
  run cmd_list
  assert_success
  assert_output --partial "No deployed agents"
}

@test "cmd_list shows deployed app name" {
  config_save_app "my-hermes" "ams"
  run cmd_list
  assert_success
  assert_output --partial "my-hermes"
}

@test "cmd_list shows region in table" {
  config_save_app "my-hermes" "ams"
  run cmd_list
  assert_success
  assert_output --partial "ams"
}

@test "cmd_list truncates long app names with ellipsis" {
  config_save_app "my-extremely-long-hermes-agent-name" "ams"
  run cmd_list
  assert_success
  assert_output --partial "my-extremely-long-herme..."
}

@test "cmd_list shows messaging platform from deploy YAML" {
  config_save_app "my-hermes" "ams"
  mkdir -p "${HERMES_FLY_CONFIG_DIR}/deploys"
  printf 'messaging:\n  platform: telegram\n' > "${HERMES_FLY_CONFIG_DIR}/deploys/my-hermes.yaml"
  run cmd_list
  assert_success
  assert_output --partial "telegram"
}

@test "_config_file normalizes HOME-unset fallback to /.hermes-fly" {
  run bash -c '
    set -euo pipefail
    source "${PROJECT_ROOT}/lib/config.sh"
    unset HERMES_FLY_CONFIG_DIR
    unset HOME
    test "$(_config_file)" = "/.hermes-fly/config.yaml"
  '
  assert_success
}

@test "_config_file canonicalizes repeated trailing slashes in HERMES_FLY_CONFIG_DIR" {
  run bash -c '
    set -euo pipefail
    source "${PROJECT_ROOT}/lib/config.sh"
    export HERMES_FLY_CONFIG_DIR="/tmp///"
    test "$(_config_file)" = "/tmp/config.yaml"
  '
  assert_success
}

@test "_config_file canonicalizes internal duplicate separators in HERMES_FLY_CONFIG_DIR" {
  run bash -c '
    set -euo pipefail
    source "${PROJECT_ROOT}/lib/config.sh"
    export HERMES_FLY_CONFIG_DIR="/tmp//nested//"
    test "$(_config_file)" = "/tmp/nested/config.yaml"
  '
  assert_success
}

@test "_config_file canonicalizes leading dot-slash in HERMES_FLY_CONFIG_DIR" {
  run bash -c '
    set -euo pipefail
    source "${PROJECT_ROOT}/lib/config.sh"
    export HERMES_FLY_CONFIG_DIR="./tmp//nested//"
    test "$(_config_file)" = "tmp/nested/config.yaml"
  '
  assert_success
}
