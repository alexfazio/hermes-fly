#!/usr/bin/env bash
set -euo pipefail

# hermes-fly installer
# Usage: curl -fsSL https://get.hermes-fly.dev/install.sh | bash

REPO="alexfazio/hermes-fly"
INSTALL_DIR="${HERMES_FLY_INSTALL_DIR:-/usr/local/bin}"
export HERMES_HOME="${HERMES_FLY_HOME:-/usr/local/lib/hermes-fly}"

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

_needs_sudo() {
  local dir="$1"
  if [[ -d "$dir" && ! -w "$dir" ]]; then
    return 0
  elif [[ ! -d "$dir" && ! -w "$(dirname "$dir")" ]]; then
    return 0
  fi
  return 1
}

_run() {
  if [[ "${_USE_SUDO:-0}" -eq 1 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

install_files() {
  local src_dir="$1" dest_dir="$2" bin_dir="$3"

  # Detect if sudo is needed for either directory
  _USE_SUDO=0
  if _needs_sudo "$dest_dir" || _needs_sudo "$bin_dir"; then
    echo "Need elevated permissions to install to $dest_dir"
    if command -v sudo >/dev/null 2>&1; then
      _USE_SUDO=1
    else
      echo "Error: Cannot write to $dest_dir and sudo is not available" >&2
      echo "Try: HERMES_FLY_INSTALL_DIR=~/.local/bin HERMES_FLY_HOME=~/.local/lib/hermes-fly bash install.sh" >&2
      return 1
    fi
  fi

  # Install project files to HERMES_HOME
  _run mkdir -p "$dest_dir"
  _run cp "$src_dir/hermes-fly" "$dest_dir/"
  _run chmod +x "$dest_dir/hermes-fly"
  _run cp -r "$src_dir/lib" "$dest_dir/"
  _run cp -r "$src_dir/templates" "$dest_dir/"

  # Symlink into PATH
  _run mkdir -p "$bin_dir"
  _run ln -sf "$dest_dir/hermes-fly" "$bin_dir/hermes-fly"

  echo "Installed hermes-fly to $dest_dir"
  echo "Symlinked $bin_dir/hermes-fly -> $dest_dir/hermes-fly"
}

main() {
  echo "Installing hermes-fly..."

  local platform arch
  platform="$(detect_platform)" || exit 1
  arch="$(detect_arch)" || exit 1

  echo "Platform: $platform/$arch"
  echo "Install to: $HERMES_HOME"
  echo "Symlink in: $INSTALL_DIR"

  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required for installation" >&2
    exit 1
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  echo "Downloading hermes-fly..."
  if ! git clone --depth 1 "https://github.com/${REPO}.git" "$tmp_dir/hermes-fly" 2>/dev/null; then
    echo "Error: Download failed" >&2
    exit 1
  fi

  install_files "$tmp_dir/hermes-fly" "$HERMES_HOME" "$INSTALL_DIR"

  # Show installed version
  local version
  version="$("$INSTALL_DIR/hermes-fly" --version 2>/dev/null || echo "hermes-fly (unknown version)")"

  echo ""
  echo "hermes-fly installed successfully!"
  echo "  $version"
  echo "Run 'hermes-fly deploy' to get started."
}

# Only run main if not being sourced (for testing)
# `return` succeeds only when sourced; fails when executed or piped.
(return 0 2>/dev/null) || main "$@"
