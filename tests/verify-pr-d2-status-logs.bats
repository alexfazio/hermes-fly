#!/usr/bin/env bats
# tests/verify-pr-d2-status-logs.bats — PR-D2 verifier contract checks

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

@test "all required PR-D2 files exist" {
  run bash -c '
    set -euo pipefail
    test -f "${PROJECT_ROOT}/src/contexts/runtime/infrastructure/adapters/current-app-config.ts"
    test -f "${PROJECT_ROOT}/src/commands/resolve-app.ts"
    test -f "${PROJECT_ROOT}/src/contexts/runtime/application/ports/status-reader.port.ts"
    test -f "${PROJECT_ROOT}/src/contexts/runtime/application/use-cases/show-status.ts"
    test -f "${PROJECT_ROOT}/src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts"
    test -f "${PROJECT_ROOT}/src/commands/status.ts"
    test -f "${PROJECT_ROOT}/src/contexts/runtime/application/ports/logs-reader.port.ts"
    test -f "${PROJECT_ROOT}/src/contexts/runtime/application/use-cases/show-logs.ts"
    test -f "${PROJECT_ROOT}/src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts"
    test -f "${PROJECT_ROOT}/src/commands/logs.ts"
    test -f "${PROJECT_ROOT}/tests-ts/runtime/show-status.test.ts"
    test -f "${PROJECT_ROOT}/tests-ts/runtime/show-logs.test.ts"
    test -f "${PROJECT_ROOT}/tests/status-ts-hybrid.bats"
    test -f "${PROJECT_ROOT}/tests/logs-ts-hybrid.bats"
    test -f "${PROJECT_ROOT}/tests/verify-pr-d2-status-logs.bats"
    test -f "${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh exits 0 and prints success message" {
  run bash -c '
    cd "${PROJECT_ROOT}"
    "${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh" 2>&1 | tail -1
  '
  assert_success
  assert_output "PR-D2 status/logs verification passed."
}

@test "verify-pr-d2-status-logs.sh includes status -a test-app diff assertions" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    if ! grep -q "diff -u.*status.stdout.snap" "${script}"; then
      echo "MISSING: diff status.stdout.snap assertion"
      exit 1
    fi
    if ! grep -q "diff -u.*status.stderr.snap" "${script}"; then
      echo "MISSING: diff status.stderr.snap assertion"
      exit 1
    fi
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh includes logs -a test-app diff assertions" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    if ! grep -q "diff -u.*logs.stdout.snap" "${script}"; then
      echo "MISSING: diff logs.stdout.snap assertion"
      exit 1
    fi
    if ! grep -q "diff -u.*logs.stderr.snap" "${script}"; then
      echo "MISSING: diff logs.stderr.snap assertion"
      exit 1
    fi
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh includes missing-app grep checks for status" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    if ! grep -q "No app specified" "${script}"; then
      echo "MISSING: No app specified check for status"
      exit 1
    fi
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh includes missing-app grep checks for logs" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    grep -c "No app specified" "${script}" | grep -q "[2-9]"
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh includes MOCK_FLY_STATUS=fail check" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    if ! grep -q "MOCK_FLY_STATUS=fail" "${script}"; then
      echo "MISSING: MOCK_FLY_STATUS=fail check"
      exit 1
    fi
    if ! grep -q "Failed to get status for app" "${script}"; then
      echo "MISSING: Failed to get status assertion"
      exit 1
    fi
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh includes MOCK_FLY_LOGS=fail check" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    if ! grep -q "MOCK_FLY_LOGS=fail" "${script}"; then
      echo "MISSING: MOCK_FLY_LOGS=fail check"
      exit 1
    fi
    if ! grep -q "Failed to fetch logs for app" "${script}"; then
      echo "MISSING: Failed to fetch logs assertion"
      exit 1
    fi
  '
  assert_success
}

@test "verify-pr-d2-status-logs.sh includes dist-missing fallback checks for status and logs" {
  run bash -c '
    set -euo pipefail
    script="${PROJECT_ROOT}/scripts/verify-pr-d2-status-logs.sh"
    if ! grep -q "TS implementation unavailable for command.*status" "${script}"; then
      echo "MISSING: dist-missing fallback check for status"
      exit 1
    fi
    if ! grep -q "TS implementation unavailable for command.*logs" "${script}"; then
      echo "MISSING: dist-missing fallback check for logs"
      exit 1
    fi
  '
  assert_success
}
