#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
	repo_root="$(cd "$script_dir/.." && pwd)"
fi
cd "$repo_root"

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
echo "[bootstrap] Installing JS dependencies with npm ci..."
npm ci

echo "[bootstrap] Done."
