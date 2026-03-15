#!/usr/bin/env bash
# scripts/verify-pr-full-commander.sh
# Full Commander.js cutover verification script.
# Prints deterministic category lines: [HAPPY] PASS, [EDGE] PASS, [FAILURE] PASS, [REGRESSION] PASS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOCKS_PATH="${PROJECT_ROOT}/tests/mocks"
HERMES_FLY="${PROJECT_ROOT}/hermes-fly"
NODE_CLI="${PROJECT_ROOT}/dist/cli.js"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass_category() {
  echo "[$1] PASS"
}

# ============================================================
# [HAPPY] Happy-path coverage
# ============================================================
happy_checks() {
  # help shows all 9 commands
  output="$(PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" help 2>&1)"
  for cmd in deploy resume list status logs doctor destroy help version; do
    echo "$output" | grep -q "$cmd" || fail "help missing command: $cmd"
  done

  # version outputs version
  output="$(PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" version 2>&1)"
  echo "$output" | grep -q "hermes-fly" || fail "version missing hermes-fly"

  # list works
  PATH="${MOCKS_PATH}:${PATH}" \
    HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR:-${HOME}/.hermes-fly}" \
    node "${NODE_CLI}" list >/dev/null 2>&1 || fail "list command failed"

  # status with -a works
  PATH="${MOCKS_PATH}:${PATH}" \
    HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR:-${HOME}/.hermes-fly}" \
    node "${NODE_CLI}" status -a test-app >/dev/null 2>&1 || fail "status -a failed"

  # resume with -a works
  output="$(PATH="${MOCKS_PATH}:${PATH}" \
    HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR:-${HOME}/.hermes-fly}" \
    node "${NODE_CLI}" resume -a test-app 2>&1)"
  echo "$output" | grep -q "Resuming" || fail "resume missing Resuming message"

  pass_category "HAPPY"
}

# ============================================================
# [EDGE] Edge-case coverage
# ============================================================
edge_checks() {
  # no args shows help (exit 0)
  PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" >/dev/null 2>&1 || fail "no-args should exit 0"

  # --version flag
  output="$(PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" --version 2>&1)"
  echo "$output" | grep -q "hermes-fly" || fail "--version missing output"

  # --help flag works
  PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" --help >/dev/null 2>&1 || fail "--help failed"

  # deploy --help shows Deployment Wizard
  output="$(PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" deploy --help 2>&1)"
  echo "$output" | grep -q "Deployment Wizard" || fail "deploy --help missing Deployment Wizard"
  echo "$output" | grep -q "\-\-no-auto-install" || fail "deploy --help missing --no-auto-install"
  echo "$output" | grep -q "\-\-channel" || fail "deploy --help missing --channel"

  pass_category "EDGE"
}

# ============================================================
# [FAILURE] Failure/error-path coverage
# ============================================================
failure_checks() {
  # unknown command exits 1
  if PATH="${MOCKS_PATH}:${PATH}" node "${NODE_CLI}" unknowncmd >/dev/null 2>&1; then
    fail "unknown command should exit 1"
  fi

  # doctor with no app exits 1
  tmp="$(mktemp -d)"
  trap "rm -rf ${tmp}" EXIT
  mkdir -p "${tmp}/config"
  if PATH="${MOCKS_PATH}:${PATH}" \
    HERMES_FLY_CONFIG_DIR="${tmp}/config" \
    node "${NODE_CLI}" doctor >/dev/null 2>&1; then
    fail "doctor with no app should exit 1"
  fi

  # doctor with stopped machine exits 1
  if PATH="${MOCKS_PATH}:${PATH}" \
    MOCK_FLY_MACHINE_STATE=stopped \
    HERMES_FLY_CONFIG_DIR="${HERMES_FLY_CONFIG_DIR:-${HOME}/.hermes-fly}" \
    node "${NODE_CLI}" doctor -a test-app >/dev/null 2>&1; then
    fail "doctor with stopped machine should exit 1"
  fi

  pass_category "FAILURE"
}

# ============================================================
# [REGRESSION] Regression/safety coverage
# ============================================================
regression_checks() {
  # hermes-fly must not source lib/*.sh
  if grep -n "^source.*lib/" "${HERMES_FLY}" 2>/dev/null | grep -q .; then
    fail "hermes-fly sources lib/*.sh at startup"
  fi

  # hermes-fly must not reference HERMES_FLY_IMPL_MODE
  if grep -q "HERMES_FLY_IMPL_MODE" "${HERMES_FLY}" 2>/dev/null; then
    fail "hermes-fly references HERMES_FLY_IMPL_MODE"
  fi

  # src/ must not reference cmd_ legacy functions
  if grep -rn "cmd_deploy\b\|cmd_doctor\b\|cmd_destroy\b" "${PROJECT_ROOT}/src/" 2>/dev/null | grep -q .; then
    fail "src/ references legacy cmd_ functions"
  fi

  # hermes-fly invokes node dist/cli.js
  grep -q "node.*dist/cli.js" "${HERMES_FLY}" || fail "hermes-fly does not invoke node dist/cli.js"

  # release-guard reads from src/version.ts
  grep -q "src/version.ts" "${PROJECT_ROOT}/scripts/release-guard.sh" || \
    fail "release-guard.sh does not reference src/version.ts"

  pass_category "REGRESSION"
}

# ============================================================
# Run all checks
# ============================================================
npm run build --prefix "${PROJECT_ROOT}" >/dev/null 2>&1 || true

happy_checks
edge_checks
failure_checks
regression_checks

echo ""
echo "Full Commander transition verification passed."
