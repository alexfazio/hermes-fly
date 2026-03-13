#!/usr/bin/env bats
# tests/logs-ts-hybrid.bats — Hybrid TS logs parity checks

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

@test "hybrid allowlisted logs -a test-app matches committed parity baseline" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_ROOT="${tmp}" bash -c '"'"'
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
          ./hermes-fly logs -a test-app >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"
        printf "%s\n" "$?" >"${TMP_ROOT}/exit"
      '"'"'
    diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/out"
    diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/err"
    diff -u tests/parity/baseline/logs.exit.snap "${tmp}/exit"'
  assert_success
}

@test "hybrid allowlisted logs uses current-app fallback and matches baseline" {
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
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
          ./hermes-fly logs >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
        printf "%s\n" "$?" >"${TMP_DIR}/exit"
      '"'"'
    diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/out"
    diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/err"
    diff -u tests/parity/baseline/logs.exit.snap "${tmp}/exit"'
  assert_success
}

@test "hybrid allowlisted logs with no app returns error" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_ROOT="${tmp}" bash -c '"'"'
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
          ./hermes-fly logs >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"
        printf "%s\n" "$?" >"${TMP_ROOT}/exit"
      '"'"'
    test "$(cat "${tmp}/exit")" = "1"
    test ! -s "${tmp}/out"
    test "$(cat "${tmp}/err")" = "[error] No app specified. Use -a APP or run '"'"'hermes-fly deploy'"'"' first."'
  assert_success
}

@test "hybrid allowlisted logs with MOCK_FLY_LOGS=fail returns logs failure error" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_ROOT="${tmp}" bash -c '"'"'
        MOCK_FLY_LOGS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
          ./hermes-fly logs -a bad-app >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"
        printf "%s\n" "$?" >"${TMP_ROOT}/exit"
      '"'"'
    test "$(cat "${tmp}/exit")" = "1"
    test ! -s "${tmp}/out"
    test "$(cat "${tmp}/err")" = "[error] Failed to fetch logs for app '"'"'bad-app'"'"'"'
  assert_success
}

@test "hybrid allowlisted logs falls back when dist artifact is missing" {
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
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
          ./hermes-fly logs -a test-app >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
        printf "%s\n" "$?" >"${TMP_DIR}/exit"
      '"'"'
    test "$(cat "${tmp}/exit")" = "0"
    test "$(head -n 1 "${tmp}/err")" = "Warning: TS implementation unavailable for command '"'"'logs'"'"'; falling back to legacy"
    diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/out"
    tail -n +2 "${tmp}/err" > "${tmp}/err.rest"
    diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/err.rest"'
  assert_success
}
