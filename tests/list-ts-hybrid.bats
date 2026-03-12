#!/usr/bin/env bats
# tests/list-ts-hybrid.bats — Hybrid TS list parity checks

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

teardown() {
  _common_teardown
}

@test "hybrid allowlisted list empty config matches legacy empty-state contract" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list >"${tmp}/out" 2>"${tmp}/err"
    test "$(cat "${tmp}/out")" = "No deployed agents found. Run: hermes-fly deploy"
    test ! -s "${tmp}/err"'
  assert_success
}

@test "hybrid allowlisted list seeded scenario matches committed parity baseline" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_DIR="${tmp}" bash -c '\''
        source ./lib/config.sh
        config_save_app "test-app" "ord"
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
        printf "%s\n" "$?" >"${TMP_DIR}/exit"
      '\''
    diff -u tests/parity/baseline/list.stdout.snap "${tmp}/out"
    diff -u tests/parity/baseline/list.stderr.snap "${tmp}/err"
    diff -u tests/parity/baseline/list.exit.snap "${tmp}/exit"'
  assert_success
}

@test "hybrid allowlisted list falls back safely when dist artifact is missing" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_DIR="${tmp}" bash -c '\''
        source ./lib/config.sh
        config_save_app "test-app" "ord"
        rm -f dist/cli.js
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
      '\''
    first_line="$(head -n 1 "${tmp}/err")"
    test "${first_line}" = "Warning: TS implementation unavailable for command '\''list'\''; falling back to legacy"
    diff -u tests/parity/baseline/list.stdout.snap "${tmp}/out"'
  assert_success
}

@test "legacy and allowlisted TS list --help outputs are byte-identical" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_DIR="${tmp}" bash -c '\''
        source ./lib/config.sh
        config_save_app "test-app" "ord"
        HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --help >"${TMP_DIR}/legacy-help.out" 2>"${TMP_DIR}/legacy-help.err"
        printf "%s\n" "$?" >"${TMP_DIR}/legacy-help.exit"
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --help >"${TMP_DIR}/ts-help.out" 2>"${TMP_DIR}/ts-help.err"
        printf "%s\n" "$?" >"${TMP_DIR}/ts-help.exit"
      '\''
    diff -u "${tmp}/legacy-help.out" "${tmp}/ts-help.out"
    diff -u "${tmp}/legacy-help.err" "${tmp}/ts-help.err"
    diff -u "${tmp}/legacy-help.exit" "${tmp}/ts-help.exit"'
  assert_success
}

@test "legacy and allowlisted TS list unknown-flag outputs are byte-identical" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/config" "${tmp}/logs"
    PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
      TMP_DIR="${tmp}" bash -c '\''
        source ./lib/config.sh
        config_save_app "test-app" "ord"
        HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --unknown-flag >"${TMP_DIR}/legacy-unknown.out" 2>"${TMP_DIR}/legacy-unknown.err"
        printf "%s\n" "$?" >"${TMP_DIR}/legacy-unknown.exit"
        HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --unknown-flag >"${TMP_DIR}/ts-unknown.out" 2>"${TMP_DIR}/ts-unknown.err"
        printf "%s\n" "$?" >"${TMP_DIR}/ts-unknown.exit"
      '\''
    diff -u "${tmp}/legacy-unknown.out" "${tmp}/ts-unknown.out"
    diff -u "${tmp}/legacy-unknown.err" "${tmp}/ts-unknown.err"
    diff -u "${tmp}/legacy-unknown.exit" "${tmp}/ts-unknown.exit"'
  assert_success
}

@test "legacy list with HOME unset does not emit config warning" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/.hermes-fly"
    printf "%s\n" \
      "apps:" \
      "  - name: should-not-be-read-from-relative-path" \
      "    region: ord" >"${tmp}/.hermes-fly/config.yaml"
    (
      cd "${tmp}"
      env -u HOME -u HERMES_FLY_CONFIG_DIR HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" list >legacy.out 2>legacy.err
      test "$(cat legacy.out)" = "No deployed agents found. Run: hermes-fly deploy"
      test ! -s legacy.err
    )'
  assert_success
}

@test "legacy and allowlisted TS list parity holds when HOME is unset" {
  run bash -c 'set -euo pipefail
    cd "${PROJECT_ROOT}"
    npm run build >/dev/null
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT
    mkdir -p "${tmp}/.hermes-fly"
    printf "%s\n" \
      "apps:" \
      "  - name: should-not-be-read-from-relative-path" \
      "    region: ord" >"${tmp}/.hermes-fly/config.yaml"
    (
      cd "${tmp}"
      env -u HOME -u HERMES_FLY_CONFIG_DIR HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" list >legacy.out 2>legacy.err
      printf "%s\n" "$?" >legacy.exit
      env -u HOME -u HERMES_FLY_CONFIG_DIR HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list "${PROJECT_ROOT}/hermes-fly" list >ts.out 2>ts.err
      printf "%s\n" "$?" >ts.exit
      diff -u legacy.out ts.out
      diff -u legacy.err ts.err
      diff -u legacy.exit ts.exit
    )'
  assert_success
}
