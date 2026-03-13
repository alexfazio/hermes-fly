#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

require_bats_binary() {
  local repo_path="$1"
  local bats_bin="${repo_path}/tests/bats/bin/bats"
  if [[ -x "${bats_bin}" ]]; then
    return 0
  fi

  cat >&2 <<EOF
error: test runner not found: ${bats_bin}
Initialize git submodules first:
  git submodule update --init --recursive
Then rerun bootstrap:
  make bootstrap
EOF
  exit 1
}

require_bats_binary "${repo_root}"

echo "[1/4] verifying required files..."
test -f package.json
test -f tsconfig.json
test -f src/cli.ts
test -f src/version.ts
test -f src/legacy/bash-bridge.ts
test -f dist/.gitkeep
test -f tests/hybrid-dispatch.bats

echo "[2/4] verifying default output equals explicit legacy..."
cmp -s <(./hermes-fly --version) <(HERMES_FLY_IMPL_MODE=legacy ./hermes-fly --version)
cmp -s <(./hermes-fly help) <(HERMES_FLY_IMPL_MODE=legacy ./hermes-fly help)
cmp -s <(./hermes-fly deploy --help) <(HERMES_FLY_IMPL_MODE=legacy ./hermes-fly deploy --help)

echo "[3/4] verifying hybrid fallback stderr contract..."
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${stdout_file}" "${stderr_file}"' EXIT

rm -f dist/cli.js
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version >"${stdout_file}" 2>"${stderr_file}"

expected_version="$(sed -n 's/^HERMES_FLY_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' ./hermes-fly | head -1)"
actual_stdout="$(cat "${stdout_file}")"
if [[ "${actual_stdout}" != "hermes-fly ${expected_version}" ]]; then
  echo "ERROR: unexpected stdout from hybrid fallback: ${actual_stdout}" >&2
  exit 1
fi

stderr_lines="$(wc -l < "${stderr_file}" | tr -d '[:space:]')"
if [[ "${stderr_lines}" != "1" ]]; then
  echo "ERROR: expected one fallback warning line on stderr, got ${stderr_lines}" >&2
  exit 1
fi

echo "[4/4] running dispatcher and integration tests..."
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats

echo "PR-A1 verification passed."
