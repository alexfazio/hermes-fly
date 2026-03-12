#!/usr/bin/env bats
# tests/verify-pr-d1-list-command.bats — one-command verifier contract checks

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

teardown() {
  _common_teardown
}

@test "verify-pr-d1-list-command enforces dist root help contract" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d1-list-command.sh"

    grep -F "node dist/cli.js help" "${script}" >/dev/null
    grep -F "dist_root_help_out" "${script}" >/dev/null
    grep -F "grep -F \"Usage: hermes-fly\"" "${script}" >/dev/null
    grep -F "grep -F \"App Name\"" "${script}" >/dev/null
    grep -F "assert_empty_file \"\${dist_root_help_err}\" \"dist help stderr\"" "${script}" >/dev/null
    grep -F "assert_exit_code \"\${dist_root_help_exit}\" \"dist help\"" "${script}" >/dev/null
  '
  assert_success
}

@test "verify-pr-d1-list-command asserts explicit success exits for dist entrypoints" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d1-list-command.sh"

    grep -F "dist_flag_version_exit" "${script}" >/dev/null
    grep -F "dist_command_version_exit" "${script}" >/dev/null
    grep -F "dist_root_help_exit" "${script}" >/dev/null
    grep -F "dist_subcommand_help_exit" "${script}" >/dev/null
    grep -F "dist_unknown_exit" "${script}" >/dev/null
  '
  assert_success
}
