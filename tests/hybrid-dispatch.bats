#!/usr/bin/env bats
# tests/hybrid-dispatch.bats — hybrid dispatcher contract checks

setup() {
  load 'test_helper/common-setup'
  _common_setup

  EXPECTED_VERSION="$(
    sed -n 's/^HERMES_FLY_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' \
      "${PROJECT_ROOT}/hermes-fly" | head -1
  )"
}

teardown() {
  if [[ ! -f "${PROJECT_ROOT}/dist/cli.js" ]]; then
    (cd "${PROJECT_ROOT}" && npm run build >/dev/null)
  fi
  _common_teardown
}

@test "default impl mode is legacy" {
  run bash -c '"${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_output "hermes-fly ${EXPECTED_VERSION}"
}

@test "legacy mode ignores TS allowlist" {
  run bash -c 'HERMES_FLY_IMPL_MODE=legacy HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_output "hermes-fly ${EXPECTED_VERSION}"
}

@test "hybrid mode with non-allowlisted command stays legacy" {
  run bash -c 'HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list "${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_output "hermes-fly ${EXPECTED_VERSION}"
}

@test "hybrid mode allowlisted version uses dist runtime and preserves version contract when dist is present" {
  run bash -c 'npm run build >/dev/null && HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version 2>&1'
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

@test "hybrid allowlisted version --help matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --help >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --help >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "hybrid allowlisted version unknown flag matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --unknown-flag >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --unknown-flag >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "ts mode allowlisted version --help matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --help >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --help >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "ts mode allowlisted version unknown flag matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --unknown-flag >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --unknown-flag >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "ts mode allowlisted version -h matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version -h >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version -h >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "ts mode allowlisted version -V matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version -V >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version -V >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "ts mode allowlisted version --help --unknown-flag matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --help --unknown-flag >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --help --unknown-flag >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "ts mode allowlisted version --unknown-flag --help matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    ts_out="$(mktemp)"
    ts_err="$(mktemp)"
    ts_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${ts_out}\" \"${ts_err}\" \"${ts_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --unknown-flag --help >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --unknown-flag --help >"${ts_out}" 2>"${ts_err}"
    printf "%s\n" "$?" >"${ts_exit}"

    diff -u "${legacy_out}" "${ts_out}"
    diff -u "${legacy_err}" "${ts_err}"
    diff -u "${legacy_exit}" "${ts_exit}"
  '
  assert_success
}

@test "hybrid allowlisted version -h matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    hybrid_out="$(mktemp)"
    hybrid_err="$(mktemp)"
    hybrid_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${hybrid_out}\" \"${hybrid_err}\" \"${hybrid_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version -h >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version -h >"${hybrid_out}" 2>"${hybrid_err}"
    printf "%s\n" "$?" >"${hybrid_exit}"

    diff -u "${legacy_out}" "${hybrid_out}"
    diff -u "${legacy_err}" "${hybrid_err}"
    diff -u "${legacy_exit}" "${hybrid_exit}"
  '
  assert_success
}

@test "hybrid allowlisted version -V matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    hybrid_out="$(mktemp)"
    hybrid_err="$(mktemp)"
    hybrid_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${hybrid_out}\" \"${hybrid_err}\" \"${hybrid_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version -V >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version -V >"${hybrid_out}" 2>"${hybrid_err}"
    printf "%s\n" "$?" >"${hybrid_exit}"

    diff -u "${legacy_out}" "${hybrid_out}"
    diff -u "${legacy_err}" "${hybrid_err}"
    diff -u "${legacy_exit}" "${hybrid_exit}"
  '
  assert_success
}

@test "hybrid allowlisted version --help --unknown-flag matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    hybrid_out="$(mktemp)"
    hybrid_err="$(mktemp)"
    hybrid_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${hybrid_out}\" \"${hybrid_err}\" \"${hybrid_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --help --unknown-flag >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --help --unknown-flag >"${hybrid_out}" 2>"${hybrid_err}"
    printf "%s\n" "$?" >"${hybrid_exit}"

    diff -u "${legacy_out}" "${hybrid_out}"
    diff -u "${legacy_err}" "${hybrid_err}"
    diff -u "${legacy_exit}" "${hybrid_exit}"
  '
  assert_success
}

@test "hybrid allowlisted version --unknown-flag --help matches legacy output and exit" {
  run bash -c '
    set -euo pipefail
    npm run build >/dev/null
    legacy_out="$(mktemp)"
    legacy_err="$(mktemp)"
    legacy_exit="$(mktemp)"
    hybrid_out="$(mktemp)"
    hybrid_err="$(mktemp)"
    hybrid_exit="$(mktemp)"
    trap "rm -f \"${legacy_out}\" \"${legacy_err}\" \"${legacy_exit}\" \"${hybrid_out}\" \"${hybrid_err}\" \"${hybrid_exit}\"" EXIT

    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" version --unknown-flag --help >"${legacy_out}" 2>"${legacy_err}"
    printf "%s\n" "$?" >"${legacy_exit}"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version --unknown-flag --help >"${hybrid_out}" 2>"${hybrid_err}"
    printf "%s\n" "$?" >"${hybrid_exit}"

    diff -u "${legacy_out}" "${hybrid_out}"
    diff -u "${legacy_err}" "${hybrid_err}"
    diff -u "${legacy_exit}" "${hybrid_exit}"
  '
  assert_success
}

@test "hybrid mode allowlisted command falls back when dist cli artifact is missing" {
  run bash -c 'rm -f "${PROJECT_ROOT}/dist/cli.js"; HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_equal "${#lines[@]}" "2"
  assert_line --index 0 "Warning: TS implementation unavailable for command 'version'; falling back to legacy"
  assert_line --index 1 "hermes-fly ${EXPECTED_VERSION}"
}

@test "ts mode allowlisted command falls back when dist cli artifact is missing" {
  run bash -c 'rm -f "${PROJECT_ROOT}/dist/cli.js"; HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version "${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_equal "${#lines[@]}" "2"
  assert_line --index 0 "Warning: TS implementation unavailable for command 'version'; falling back to legacy"
  assert_line --index 1 "hermes-fly ${EXPECTED_VERSION}"
}

@test "hybrid mode allowlisted version --help falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --help >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "ts mode allowlisted version unknown flag falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --unknown-flag >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "ts mode allowlisted version --help falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --help >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "ts mode allowlisted version -h falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version -h >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "ts mode allowlisted version -V falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version -V >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "hybrid mode allowlisted version -h falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version -h >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "hybrid mode allowlisted version --unknown-flag --help falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --unknown-flag --help >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "hybrid mode allowlisted version -V falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version -V >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "hybrid mode allowlisted version --help --unknown-flag falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --help --unknown-flag >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "ts mode allowlisted version --unknown-flag --help falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --unknown-flag --help >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "ts mode allowlisted version --help --unknown-flag falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --help --unknown-flag >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "hybrid mode allowlisted version unknown flag falls back when dist cli artifact is missing" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version --unknown-flag >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "invalid impl mode normalizes to legacy with warning" {
  run bash -c 'HERMES_FLY_IMPL_MODE=invalid "${PROJECT_ROOT}/hermes-fly" version 2>&1'
  assert_success
  assert_equal "${#lines[@]}" "2"
  assert_line --index 0 "Warning: Unknown HERMES_FLY_IMPL_MODE 'invalid', using legacy"
  assert_line --index 1 "hermes-fly ${EXPECTED_VERSION}"
}

@test "default help output is byte-identical to explicit legacy mode" {
  run bash -c '
    default_out="$(mktemp)"
    legacy_out="$(mktemp)"
    trap "rm -f \"${default_out}\" \"${legacy_out}\"" EXIT
    "${PROJECT_ROOT}/hermes-fly" help >"${default_out}"
    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" help >"${legacy_out}"
    cmp -s "${default_out}" "${legacy_out}"
  '
  assert_success
}

@test "default deploy help output is byte-identical to explicit legacy mode" {
  run bash -c '
    default_out="$(mktemp)"
    legacy_out="$(mktemp)"
    trap "rm -f \"${default_out}\" \"${legacy_out}\"" EXIT
    "${PROJECT_ROOT}/hermes-fly" deploy --help >"${default_out}"
    HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" deploy --help >"${legacy_out}"
    cmp -s "${default_out}" "${legacy_out}"
  '
  assert_success
}

@test "hybrid fallback emits one stderr warning line and preserves stdout contract" {
  run bash -c '
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    trap "rm -f \"${out_file}\" \"${err_file}\"" EXIT
    rm -f "${PROJECT_ROOT}/dist/cli.js"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version \
      "${PROJECT_ROOT}/hermes-fly" version >"${out_file}" 2>"${err_file}"
    printf "STDOUT=%s\n" "$(cat "${out_file}")"
    printf "STDERR_LINES=%s\n" "$(wc -l < "${err_file}" | tr -d "[:space:]")"
    printf "STDERR_FIRST=%s\n" "$(head -n 1 "${err_file}")"
  '
  assert_success
  assert_line --index 0 "STDOUT=hermes-fly ${EXPECTED_VERSION}"
  assert_line --index 1 "STDERR_LINES=1"
  assert_line --index 2 "STDERR_FIRST=Warning: TS implementation unavailable for command 'version'; falling back to legacy"
}

@test "hybrid-dispatch fallback tests leave dist artifact available for subsequent tests" {
  run bash -c 'test -f "${PROJECT_ROOT}/dist/cli.js"'
  assert_success
}
