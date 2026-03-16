#!/usr/bin/env bats
# tests/hybrid-dispatch.bats — TS runtime dispatch contract checks
#
# After the full TypeScript Commander.js transition (PR #12), the hermes-fly
# shim is a simple `exec node dist/cli.js "$@"`.  These tests validate the
# TS runtime is the sole execution path and that version/help contracts hold.

setup() {
  load 'test_helper/common-setup'
  _common_setup

  EXPECTED_VERSION="$(
    sed -n 's/.*HERMES_FLY_TS_VERSION = "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' \
      "${PROJECT_ROOT}/src/version.ts" | head -1
  )"
}

teardown() {
  if [[ ! -f "${PROJECT_ROOT}/dist/cli.js" ]]; then
    (cd "${PROJECT_ROOT}" && npm run build >/dev/null)
  fi
  _common_teardown
}

@test "hermes-fly version outputs version string" {
  run bash -c '"${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_output "hermes-fly ${EXPECTED_VERSION}"
}

@test "dist cli --version preserves version contract when built artifact is present" {
  run bash -c 'npm run build >/dev/null && node "${PROJECT_ROOT}/dist/cli.js" --version'
  assert_success
  assert_output "hermes-fly ${EXPECTED_VERSION}"
}

@test "dist cli version subcommand preserves version contract when built artifact is present" {
  run bash -c 'npm run build >/dev/null && node "${PROJECT_ROOT}/dist/cli.js" version'
  assert_success
  assert_output "hermes-fly ${EXPECTED_VERSION}"
}

@test "dist cli help prints root help text and exits successfully" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    exit_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\" \"${exit_file}\"" EXIT
    node "${PROJECT_ROOT}/dist/cli.js" help >"${out_file}" 2>"${err_file}"
    printf "%s\n" "$?" >"${exit_file}"
    grep -F "Usage:" "${out_file}" >/dev/null
    grep -F "Commands:" "${out_file}" >/dev/null
    ! grep -F "No deployed agents found." "${out_file}" >/dev/null
    ! grep -F "App Name" "${out_file}" >/dev/null
    test ! -s "${err_file}"
    test "$(cat "${exit_file}")" = "0"
  '
  assert_success
}

@test "dist cli version --help prints only version line" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    node "${PROJECT_ROOT}/dist/cli.js" version --help >"${out_file}" 2>"${err_file}"
    test "$(cat "${out_file}")" = "hermes-fly ${EXPECTED_VERSION}"
    test ! -s "${err_file}"
  '
  assert_success
}

@test "dist cli version unknown flag prints only version line" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    node "${PROJECT_ROOT}/dist/cli.js" version --unknown-flag >"${out_file}" 2>"${err_file}"
    test "$(cat "${out_file}")" = "hermes-fly ${EXPECTED_VERSION}"
    test ! -s "${err_file}"
  '
  assert_success
}
