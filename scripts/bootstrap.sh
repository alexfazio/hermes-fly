#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
	repo_root="$(cd "$script_dir/.." && pwd)"
fi
cd "$repo_root"

sync_submodules() {
  if [[ ! -f tests/bats/bin/bats || \
    ! -f tests/test_helper/bats-support/load.bash || \
    ! -f tests/test_helper/bats-assert/load.bash ]]; then
    if ! command -v git >/dev/null 2>&1; then
      echo "error: missing vendored test dependencies and git is required to initialize submodules" >&2
      echo "Run git clone --recurse-submodules for a full checkout, then rerun bootstrap." >&2
      exit 1
    fi

    if ! git -C "$repo_root" submodule update --init --recursive; then
      echo "error: failed to initialize git submodules" >&2
      exit 1
    fi
  fi

  if [[ ! -f tests/bats/bin/bats || \
    ! -f tests/test_helper/bats-support/load.bash || \
    ! -f tests/test_helper/bats-assert/load.bash ]]; then
    echo "error: required test submodule files still missing after initialization" >&2
    exit 1
  fi
}

if ! command -v node >/dev/null 2>&1; then
	echo "error: node is required but was not found in PATH" >&2
	exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
	echo "error: npm is required but was not found in PATH" >&2
	exit 1
fi

if [[ ! -f package-lock.json ]]; then
	echo "error: package-lock.json not found at $repo_root" >&2
	exit 1
fi

echo "[bootstrap] Detected repository root: $repo_root"
echo "[bootstrap] Ensuring git-based test fixtures are initialized..."
sync_submodules
echo "[bootstrap] Installing JS dependencies with npm ci..."
npm ci

echo "[bootstrap] Done."
