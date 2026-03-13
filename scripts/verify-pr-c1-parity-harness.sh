#!/usr/bin/env bash
set -euo pipefail

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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "${HERMES_FLY_PARITY_VERIFY_SKIP_BATS:-0}" != "1" ]]; then
  require_bats_binary "${REPO_ROOT}"
fi

TMP_DIRS=(
  "tests/parity/_tmp_run1"
  "tests/parity/_tmp_run2"
  "tests/parity/_tmp_mutation"
)

cleanup() {
  local d
  for d in "${TMP_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
      rm -r "$d"
    fi
  done
  return 0
}
trap cleanup EXIT
cleanup

required_files=(
  "scripts/parity-capture.sh"
  "scripts/parity-compare.sh"
  "scripts/verify-pr-c1-parity-harness.sh"
  "tests/parity/scenarios/non_destructive_commands.list"
  "tests/parity/baseline/version.stdout.snap"
  "tests/parity/baseline/version.stderr.snap"
  "tests/parity/baseline/version.exit.snap"
  "tests/parity/baseline/help.stdout.snap"
  "tests/parity/baseline/help.stderr.snap"
  "tests/parity/baseline/help.exit.snap"
  "tests/parity/baseline/list.stdout.snap"
  "tests/parity/baseline/list.stderr.snap"
  "tests/parity/baseline/list.exit.snap"
  "tests/parity/baseline/status.stdout.snap"
  "tests/parity/baseline/status.stderr.snap"
  "tests/parity/baseline/status.exit.snap"
  "tests/parity/baseline/logs.stdout.snap"
  "tests/parity/baseline/logs.stderr.snap"
  "tests/parity/baseline/logs.exit.snap"
)

for f in "${required_files[@]}"; do
  test -f "$f"
done

npm run parity:check

bash scripts/parity-capture.sh --out-dir tests/parity/_tmp_run1
bash scripts/parity-capture.sh --out-dir tests/parity/_tmp_run2
diff -ru tests/parity/_tmp_run1 tests/parity/_tmp_run2

mkdir -p tests/parity/_tmp_mutation
cp -R tests/parity/_tmp_run1/. tests/parity/_tmp_mutation/
echo "# mutation" >> tests/parity/_tmp_mutation/version.stdout.snap

set +e
negative_output="$(bash scripts/parity-compare.sh --baseline tests/parity/baseline --candidate tests/parity/_tmp_mutation 2>&1)"
negative_rc=$?
set -e
if [[ "$negative_rc" -eq 0 ]]; then
  echo "Expected parity compare to fail for mutated candidate." >&2
  exit 1
fi
if ! printf '%s\n' "$negative_output" | rg -Fx "Mismatch: version.stdout.snap" >/dev/null; then
  echo "Expected output to contain exact line: Mismatch: version.stdout.snap" >&2
  exit 1
fi

npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
if [[ "${HERMES_FLY_PARITY_VERIFY_SKIP_BATS:-0}" != "1" ]]; then
  tests/bats/bin/bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats
fi

echo "PR-C1 verification passed."
