#!/usr/bin/env bats
# tests/status-ts-hybrid.bats — Hybrid TS status parity checks

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

teardown() {
  if [[ ! -f "${PROJECT_ROOT}/dist/cli.js" ]]; then
    (cd "${PROJECT_ROOT}" && npm run build >/dev/null)
  fi
  _common_teardown
}

@test "hybrid allowlisted status -a test-app matches committed parity baseline" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_ROOT="${tmp}" bash -c '"'"'
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
          ./hermes-fly status -a test-app >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"
        printf "%s\n" "$?" >"${TMP_ROOT}/exit"
      '"'"'
    diff -u tests/parity/baseline/status.stdout.snap "${tmp}/out"
    diff -u tests/parity/baseline/status.stderr.snap "${tmp}/err"
    diff -u tests/parity/baseline/status.exit.snap "${tmp}/exit"'
  assert_success
}

@test "hybrid allowlisted status uses current-app fallback and matches baseline" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_DIR="${tmp}" bash -c '"'"'
        source ./lib/config.sh
        config_save_app "test-app" "ord"
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
          ./hermes-fly status >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
        printf "%s\n" "$?" >"${TMP_DIR}/exit"
      '"'"'
    diff -u tests/parity/baseline/status.stdout.snap "${tmp}/out"
    diff -u tests/parity/baseline/status.stderr.snap "${tmp}/err"
    diff -u tests/parity/baseline/status.exit.snap "${tmp}/exit"'
  assert_success
}

@test "hybrid allowlisted status with no app returns error" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_ROOT="${tmp}" bash -c '"'"'
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
          ./hermes-fly status >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"
        printf "%s\n" "$?" >"${TMP_ROOT}/exit"
      '"'"'
    test "$(cat "${tmp}/exit")" = "1"
    test ! -s "${tmp}/out"
    test "$(cat "${tmp}/err")" = "[error] No app specified. Use -a APP or run '"'"'hermes-fly deploy'"'"' first."'
  assert_success
}

@test "hybrid allowlisted status with MOCK_FLY_STATUS=fail returns fly failure error" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_ROOT="${tmp}" bash -c '"'"'
        MOCK_FLY_STATUS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
          ./hermes-fly status -a bad-app >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"
        printf "%s\n" "$?" >"${TMP_ROOT}/exit"
      '"'"'
    test "$(cat "${tmp}/exit")" = "1"
    test ! -s "${tmp}/out"
    test "$(cat "${tmp}/err")" = "[error] Failed to get status for app '"'"'bad-app'"'"': Error: app not found"'
  assert_success
}

@test "hybrid allowlisted status falls back when dist artifact is missing" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_DIR="${tmp}" bash -c '"'"'
        source ./lib/config.sh
        config_save_app "test-app" "ord"
        rm -f dist/cli.js
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
          ./hermes-fly status -a test-app >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
        printf "%s\n" "$?" >"${TMP_DIR}/exit"
      '"'"'
    test "$(cat "${tmp}/exit")" = "0"
    test "$(head -n 1 "${tmp}/err")" = "Warning: TS implementation unavailable for command '"'"'status'"'"'; falling back to legacy"
    diff -u tests/parity/baseline/status.stdout.snap "${tmp}/out"
    tail -n +2 "${tmp}/err" > "${tmp}/err.rest"
    diff -u tests/parity/baseline/status.stderr.snap "${tmp}/err.rest"'
  assert_success
}
