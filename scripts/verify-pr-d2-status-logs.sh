#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

required_files=(
  "src/contexts/runtime/infrastructure/adapters/current-app-config.ts"
  "src/commands/resolve-app.ts"
  "src/contexts/runtime/application/ports/status-reader.port.ts"
  "src/contexts/runtime/application/use-cases/show-status.ts"
  "src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts"
  "src/commands/status.ts"
  "src/contexts/runtime/application/ports/logs-reader.port.ts"
  "src/contexts/runtime/application/use-cases/show-logs.ts"
  "src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts"
  "src/commands/logs.ts"
  "tests-ts/runtime/show-status.test.ts"
  "tests-ts/runtime/show-logs.test.ts"
  "tests/status-ts-hybrid.bats"
  "tests/logs-ts-hybrid.bats"
  "tests/verify-pr-d2-status-logs.bats"
  "scripts/verify-pr-d2-status-logs.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "${file}" ]]; then
    printf "Missing required file: %s\n" "${file}" >&2
    exit 1
  fi
done

npm run build
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
npm run test:runtime-status-logs

tests/bats/bin/bats \
  tests/status-ts-hybrid.bats \
  tests/logs-ts-hybrid.bats \
  tests/status.bats \
  tests/logs.bats \
  tests/hybrid-dispatch.bats

npm run build

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/config" "${tmp}/logs" "${tmp}/noapp-config"

# status -a test-app parity baseline
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
      ./hermes-fly status -a test-app >"${TMP_DIR}/status.out" 2>"${TMP_DIR}/status.err"
    printf "%s\n" "$?" >"${TMP_DIR}/status.exit"
  '

diff -u tests/parity/baseline/status.stdout.snap "${tmp}/status.out"
diff -u tests/parity/baseline/status.stderr.snap "${tmp}/status.err"
diff -u tests/parity/baseline/status.exit.snap "${tmp}/status.exit"

# logs -a test-app parity baseline
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
      ./hermes-fly logs -a test-app >"${TMP_DIR}/logs.out" 2>"${TMP_DIR}/logs.err"
    printf "%s\n" "$?" >"${TMP_DIR}/logs.exit"
  '

diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/logs.out"
diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/logs.err"
diff -u tests/parity/baseline/logs.exit.snap "${tmp}/logs.exit"

# status current-app fallback
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    source ./lib/config.sh
    config_save_app "test-app" "ord"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
      ./hermes-fly status >"${TMP_DIR}/cur-status.out" 2>"${TMP_DIR}/cur-status.err"
    printf "%s\n" "$?" >"${TMP_DIR}/cur-status.exit"
  '

diff -u tests/parity/baseline/status.stdout.snap "${tmp}/cur-status.out"
diff -u tests/parity/baseline/status.stderr.snap "${tmp}/cur-status.err"
diff -u tests/parity/baseline/status.exit.snap "${tmp}/cur-status.exit"

# logs current-app fallback
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    source ./lib/config.sh
    config_save_app "test-app" "ord"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
      ./hermes-fly logs >"${TMP_DIR}/cur-logs.out" 2>"${TMP_DIR}/cur-logs.err"
    printf "%s\n" "$?" >"${TMP_DIR}/cur-logs.exit"
  '

diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/cur-logs.out"
diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/cur-logs.err"
diff -u tests/parity/baseline/logs.exit.snap "${tmp}/cur-logs.exit"

# status: No app specified
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/noapp-config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
      ./hermes-fly status >"${TMP_DIR}/noapp-status.out" 2>"${TMP_DIR}/noapp-status.err"
    printf "%s\n" "$?" >"${TMP_DIR}/noapp-status.exit"
  '

if [[ "$(cat "${tmp}/noapp-status.exit")" != "1" ]]; then
  printf "Unexpected no-app status exit: %s\n" "$(cat "${tmp}/noapp-status.exit")" >&2
  exit 1
fi
if [[ -s "${tmp}/noapp-status.out" ]]; then
  printf "Unexpected no-app status stdout: %s\n" "$(cat "${tmp}/noapp-status.out")" >&2
  exit 1
fi
if [[ "$(cat "${tmp}/noapp-status.err")" != "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first." ]]; then
  printf "Unexpected no-app status stderr: %s\n" "$(cat "${tmp}/noapp-status.err")" >&2
  exit 1
fi

# logs: No app specified
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/noapp-config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
      ./hermes-fly logs >"${TMP_DIR}/noapp-logs.out" 2>"${TMP_DIR}/noapp-logs.err"
    printf "%s\n" "$?" >"${TMP_DIR}/noapp-logs.exit"
  '

if [[ "$(cat "${tmp}/noapp-logs.exit")" != "1" ]]; then
  printf "Unexpected no-app logs exit: %s\n" "$(cat "${tmp}/noapp-logs.exit")" >&2
  exit 1
fi
if [[ -s "${tmp}/noapp-logs.out" ]]; then
  printf "Unexpected no-app logs stdout: %s\n" "$(cat "${tmp}/noapp-logs.out")" >&2
  exit 1
fi
if [[ "$(cat "${tmp}/noapp-logs.err")" != "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first." ]]; then
  printf "Unexpected no-app logs stderr: %s\n" "$(cat "${tmp}/noapp-logs.err")" >&2
  exit 1
fi

# MOCK_FLY_STATUS=fail
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    MOCK_FLY_STATUS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
      ./hermes-fly status -a bad-app >"${TMP_DIR}/fail-status.out" 2>"${TMP_DIR}/fail-status.err"
    printf "%s\n" "$?" >"${TMP_DIR}/fail-status.exit"
  '

if [[ "$(cat "${tmp}/fail-status.exit")" != "1" ]]; then
  printf "Unexpected MOCK_FLY_STATUS=fail exit: %s\n" "$(cat "${tmp}/fail-status.exit")" >&2
  exit 1
fi
if [[ -s "${tmp}/fail-status.out" ]]; then
  printf "Unexpected MOCK_FLY_STATUS=fail stdout: %s\n" "$(cat "${tmp}/fail-status.out")" >&2
  exit 1
fi
if ! grep -q "Failed to get status for app" "${tmp}/fail-status.err"; then
  printf "Missing 'Failed to get status for app' in stderr: %s\n" "$(cat "${tmp}/fail-status.err")" >&2
  exit 1
fi

# MOCK_FLY_LOGS=fail
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    MOCK_FLY_LOGS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
      ./hermes-fly logs -a bad-app >"${TMP_DIR}/fail-logs.out" 2>"${TMP_DIR}/fail-logs.err"
    printf "%s\n" "$?" >"${TMP_DIR}/fail-logs.exit"
  '

if [[ "$(cat "${tmp}/fail-logs.exit")" != "1" ]]; then
  printf "Unexpected MOCK_FLY_LOGS=fail exit: %s\n" "$(cat "${tmp}/fail-logs.exit")" >&2
  exit 1
fi
if [[ -s "${tmp}/fail-logs.out" ]]; then
  printf "Unexpected MOCK_FLY_LOGS=fail stdout: %s\n" "$(cat "${tmp}/fail-logs.out")" >&2
  exit 1
fi
if ! grep -q "Failed to fetch logs for app" "${tmp}/fail-logs.err"; then
  printf "Missing 'Failed to fetch logs for app' in stderr: %s\n" "$(cat "${tmp}/fail-logs.err")" >&2
  exit 1
fi

# dist-missing fallback: status
(
  set -euo pipefail
  dist_missing_tmp="$(mktemp -d)"
  dist_backup="${dist_missing_tmp}/cli.js.bak"
  trap 'if [[ -f "${dist_backup}" ]]; then mv "${dist_backup}" dist/cli.js; fi; rm -rf "${dist_missing_tmp}"' EXIT
  mv dist/cli.js "${dist_backup}"
  mkdir -p "${dist_missing_tmp}/config" "${dist_missing_tmp}/logs"

  PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${dist_missing_tmp}/config" HERMES_FLY_LOG_DIR="${dist_missing_tmp}/logs" \
    TMP_DIR="${dist_missing_tmp}" bash -c '
      source ./lib/config.sh
      config_save_app "test-app" "ord"
      HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
        ./hermes-fly status -a test-app >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
      printf "%s\n" "$?" >"${TMP_DIR}/exit"
    '

  if [[ "$(cat "${dist_missing_tmp}/exit")" != "0" ]]; then
    printf "Unexpected dist-missing status exit: %s\n" "$(cat "${dist_missing_tmp}/exit")" >&2
    exit 1
  fi
  if [[ "$(head -n 1 "${dist_missing_tmp}/err")" != "Warning: TS implementation unavailable for command 'status'; falling back to legacy" ]]; then
    printf "Unexpected dist-missing status warning: %s\n" "$(head -n 1 "${dist_missing_tmp}/err")" >&2
    exit 1
  fi
  diff -u tests/parity/baseline/status.stdout.snap "${dist_missing_tmp}/out"
  tail -n +2 "${dist_missing_tmp}/err" > "${dist_missing_tmp}/err.rest"
  diff -u tests/parity/baseline/status.stderr.snap "${dist_missing_tmp}/err.rest"
)

npm run build

# dist-missing fallback: logs
(
  set -euo pipefail
  dist_missing_tmp="$(mktemp -d)"
  dist_backup="${dist_missing_tmp}/cli.js.bak"
  trap 'if [[ -f "${dist_backup}" ]]; then mv "${dist_backup}" dist/cli.js; fi; rm -rf "${dist_missing_tmp}"' EXIT
  mv dist/cli.js "${dist_backup}"
  mkdir -p "${dist_missing_tmp}/config" "${dist_missing_tmp}/logs"

  PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${dist_missing_tmp}/config" HERMES_FLY_LOG_DIR="${dist_missing_tmp}/logs" \
    TMP_DIR="${dist_missing_tmp}" bash -c '
      source ./lib/config.sh
      config_save_app "test-app" "ord"
      HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
        ./hermes-fly logs -a test-app >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
      printf "%s\n" "$?" >"${TMP_DIR}/exit"
    '

  if [[ "$(cat "${dist_missing_tmp}/exit")" != "0" ]]; then
    printf "Unexpected dist-missing logs exit: %s\n" "$(cat "${dist_missing_tmp}/exit")" >&2
    exit 1
  fi
  if [[ "$(head -n 1 "${dist_missing_tmp}/err")" != "Warning: TS implementation unavailable for command 'logs'; falling back to legacy" ]]; then
    printf "Unexpected dist-missing logs warning: %s\n" "$(head -n 1 "${dist_missing_tmp}/err")" >&2
    exit 1
  fi
  diff -u tests/parity/baseline/logs.stdout.snap "${dist_missing_tmp}/out"
  tail -n +2 "${dist_missing_tmp}/err" > "${dist_missing_tmp}/err.rest"
  diff -u tests/parity/baseline/logs.stderr.snap "${dist_missing_tmp}/err.rest"
)

npm run build

npm run verify:pr-d1-list-command

printf 'PR-D2 status/logs verification passed.\n'
