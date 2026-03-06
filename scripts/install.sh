#!/usr/bin/env bash
set -euo pipefail

# hermes-fly installer
# Usage: curl -fsSL https://get.hermes-fly.dev/install.sh | bash

REPO="alexfazio/hermes-fly"
INSTALL_DIR="${HERMES_FLY_INSTALL_DIR:-/usr/local/bin}"

detect_platform() {
  local os
  os="$(uname -s)"
  case "$os" in
    Darwin) echo "darwin" ;;
    Linux) echo "linux" ;;
    *)
      echo "Error: Unsupported platform: $os" >&2
      return 1
      ;;
  esac
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64 | amd64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *)
      echo "Error: Unsupported architecture: $arch" >&2
      return 1
      ;;
  esac
}

verify_checksum() {
  local file="$1" expected="$2"
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  else
    echo "Warning: No checksum tool found, skipping verification" >&2
    return 0
  fi
  if [[ "$actual" == "$expected" ]]; then
    return 0
  else
    echo "Error: Checksum mismatch" >&2
    echo "  Expected: $expected" >&2
    echo "  Actual:   $actual" >&2
    return 1
  fi
}

install_binary() {
  local source="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  cp "$source" "$dest_dir/hermes-fly"
  chmod +x "$dest_dir/hermes-fly"
  echo "Installed hermes-fly to $dest_dir/hermes-fly"
}

main() {
  echo "Installing hermes-fly..."

  local platform arch
  platform="$(detect_platform)" || exit 1
  arch="$(detect_arch)" || exit 1

  echo "Platform: $platform/$arch"
  echo "Install directory: $INSTALL_DIR"

  # Download from GitHub releases
  local download_url="https://github.com/${REPO}/releases/latest/download/hermes-fly"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  echo "Downloading hermes-fly..."
  if ! curl -fsSL "$download_url" -o "$tmp_dir/hermes-fly"; then
    echo "Error: Download failed" >&2
    exit 1
  fi

  echo "Verifying checksum..."
  if ! curl -fsSL "${download_url}.sha256" -o "$tmp_dir/hermes-fly.sha256"; then
    echo "Error: Checksum download failed" >&2
    exit 1
  fi

  local expected
  expected="$(awk '{print $1}' "$tmp_dir/hermes-fly.sha256")"
  if ! verify_checksum "$tmp_dir/hermes-fly" "$expected"; then
    echo "Checksum verification failed!" >&2
    exit 1
  fi

  install_binary "$tmp_dir/hermes-fly" "$INSTALL_DIR"

  echo ""
  echo "hermes-fly installed successfully!"
  echo "Run 'hermes-fly deploy' to get started."
}

# Only run main if not being sourced (for testing)
# `return` succeeds only when sourced; fails when executed or piped.
(return 0 2>/dev/null) || main "$@"
