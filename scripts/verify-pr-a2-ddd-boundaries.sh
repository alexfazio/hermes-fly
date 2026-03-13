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

echo "[1/4] verifying required files and skeleton directories..."

required_files=(
  "dependency-cruiser.cjs"
  "src/contexts/deploy/domain/.gitkeep"
  "src/contexts/deploy/application/ports/.gitkeep"
  "src/contexts/deploy/infrastructure/.gitkeep"
  "src/contexts/deploy/presentation/.gitkeep"
  "src/contexts/diagnostics/domain/.gitkeep"
  "src/contexts/diagnostics/application/ports/.gitkeep"
  "src/contexts/diagnostics/infrastructure/.gitkeep"
  "src/contexts/diagnostics/presentation/.gitkeep"
  "src/contexts/messaging/domain/.gitkeep"
  "src/contexts/messaging/application/ports/.gitkeep"
  "src/contexts/messaging/infrastructure/.gitkeep"
  "src/contexts/messaging/presentation/.gitkeep"
  "src/contexts/release/domain/.gitkeep"
  "src/contexts/release/application/ports/.gitkeep"
  "src/contexts/release/infrastructure/.gitkeep"
  "src/contexts/release/presentation/.gitkeep"
  "src/contexts/runtime/domain/.gitkeep"
  "src/contexts/runtime/application/ports/.gitkeep"
  "src/contexts/runtime/infrastructure/.gitkeep"
  "src/contexts/runtime/presentation/.gitkeep"
  "src/shared/core/.gitkeep"
  "src/shared/infra/.gitkeep"
  "scripts/verify-pr-a2-ddd-boundaries.sh"
)

for path in "${required_files[@]}"; do
  test -f "${path}"
done

echo "[2/4] verifying clean boundary rules pass..."
npm run arch:ddd-boundaries

echo "[3/4] verifying negative boundary test fails deterministically..."
tmp_target="src/contexts/runtime/infrastructure/__tmp_boundary_target.ts"
tmp_violation="src/contexts/runtime/domain/__tmp_boundary_violation.ts"
cleanup() {
  rm -f "${tmp_target}" "${tmp_violation}"
}
trap cleanup EXIT

printf "export const x = 1;\n" > "${tmp_target}"
printf "import \"../infrastructure/__tmp_boundary_target\";\nexport const y = 2;\n" > "${tmp_violation}"

if npm run arch:ddd-boundaries >/tmp/pr-a2-negative.out 2>/tmp/pr-a2-negative.err; then
  echo "ERROR: expected arch:ddd-boundaries to fail on injected domain->infrastructure dependency" >&2
  cat /tmp/pr-a2-negative.out >&2 || true
  cat /tmp/pr-a2-negative.err >&2 || true
  exit 1
fi

cleanup
npm run arch:ddd-boundaries

echo "[4/4] running regression safety suites..."
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats

echo "PR-A2 verification passed."
