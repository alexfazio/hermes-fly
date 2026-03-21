#!/usr/bin/env bash
set -euo pipefail

# hermes-fly installer
# Usage: curl -fsSL https://get.hermes-fly.dev/install.sh | bash

REPO="alexfazio/hermes-fly"
INSTALL_DIR="${HERMES_FLY_INSTALL_DIR:-/usr/local/bin}"
export HERMES_HOME="${HERMES_FLY_HOME:-/usr/local/lib/hermes-fly}"
RELEASE_API_URL="${HERMES_FLY_RELEASE_API_URL:-https://api.github.com/repos/${REPO}/releases/latest}"
SAFE_PROCESS_LOCALE="C"
# Standalone install.sh must bootstrap the checked installer revision, not a mutable branch tip.
DEFAULT_BOOTSTRAP_INSTALLER_REF="v0.1.102"
INSTALLER_ANSI_RESET=$'\033[0m'
INSTALLER_ANSI_BOLD=$'\033[1m'
INSTALLER_ANSI_ACCENT=$'\033[38;2;255;77;77m'
INSTALLER_ANSI_INFO=$'\033[38;2;136;146;176m'

installer_no_color_requested() {
  [[ "${NO_COLOR+x}" == "x" ]]
}

installer_supports_color() {
  if installer_no_color_requested; then
    return 1
  fi
  if [[ "${TERM:-dumb}" == "dumb" ]]; then
    return 1
  fi
  if [[ ! -t 1 ]]; then
    return 1
  fi
  return 0
}

installer_style() {
  local codes="$1" text="$2"
  if installer_supports_color; then
    printf '%b%s%b' "$codes" "$text" "$INSTALLER_ANSI_RESET"
  else
    printf '%s' "$text"
  fi
}

print_installer_banner() {
  printf '  %s\n' "$(installer_style "${INSTALLER_ANSI_ACCENT}${INSTALLER_ANSI_BOLD}" "🪽 Hermes Fly Installer")"
  printf '  %s\n\n' "$(installer_style "${INSTALLER_ANSI_INFO}" "I can't fix Fly.io billing, but I can fix the part between curl and deploy.")"
}

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

normalize_install_ref() {
  local ref="${1:-}"
  if [[ "$ref" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'v%s\n' "$ref"
  else
    printf '%s\n' "$ref"
  fi
}

is_release_ref() {
  [[ "${1:-}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

resolve_latest_release_tag_via_git() {
  local tag
  tag="$(
    git ls-remote --refs --tags "https://github.com/${REPO}.git" 2>/dev/null \
      | awk '{print $2}' \
      | sed 's#refs/tags/##' \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
      | sort -V \
      | tail -1
  )"
  if [[ -n "$tag" ]]; then
    printf '%s\n' "$tag"
    return 0
  fi

  echo "Error: Could not determine the latest hermes-fly release" >&2
  return 1
}

resolve_latest_release_tag() {
  local response tag
  if command -v curl >/dev/null 2>&1; then
    response="$(curl -fsSL "$RELEASE_API_URL" 2>/dev/null || true)"
    tag="$(printf '%s' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
      return 0
    fi
  fi

  resolve_latest_release_tag_via_git
}

resolve_install_channel() {
  local channel="${HERMES_FLY_CHANNEL:-latest}"
  if [[ -z "$channel" ]]; then
    channel="latest"
  fi

  case "$channel" in
    latest | stable | preview | edge)
      printf '%s\n' "$channel"
      ;;
    *)
      echo "Warning: Unknown HERMES_FLY_CHANNEL '${channel}', falling back to latest" >&2
      printf 'latest\n'
      ;;
  esac
}

resolve_install_ref() {
  local channel="${1:-latest}"
  if [[ -n "${HERMES_FLY_VERSION:-}" ]]; then
    normalize_install_ref "$HERMES_FLY_VERSION"
    return 0
  fi

  case "$channel" in
    latest)
      resolve_latest_release_tag
      ;;
    edge)
      # Edge is explicitly moving/non-reproducible.
      printf 'main\n'
      ;;
    preview)
      # Preview channel follows latest stable release until a dedicated preview stream exists.
      resolve_latest_release_tag
      ;;
    *)
      resolve_latest_release_tag
      ;;
  esac
}

source_archive_url() {
  local install_ref="$1"
  printf 'https://codeload.github.com/%s/tar.gz/%s\n' "$REPO" "$install_ref"
}

require_command() {
  local cmd="$1" purpose="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$purpose" ]]; then
    echo "Error: ${cmd} is required ${purpose}" >&2
  else
    echo "Error: ${cmd} is required" >&2
  fi
  return 1
}

run_with_sanitized_env() {
  env -u BASH_ENV -u ENV LANG="$SAFE_PROCESS_LOCALE" LC_ALL="$SAFE_PROCESS_LOCALE" "$@"
}

run_prepare_runtime_step() {
  local log_file="${1:-}"
  shift
  if [[ -n "$log_file" ]]; then
    "$@" >>"$log_file" 2>&1
  else
    "$@"
  fi
}

show_prepare_runtime_failure_log() {
  local log_file="${1:-}"
  if [[ -n "$log_file" && -s "$log_file" ]]; then
    tail -n 80 "$log_file" >&2 || true
  fi
}

release_asset_name() {
  local install_ref="$1"
  printf 'hermes-fly-%s.tar.gz\n' "$install_ref"
}

release_metadata_url() {
  local install_ref="$1"
  printf 'https://api.github.com/repos/%s/releases/tags/%s\n' "$REPO" "$install_ref"
}

resolve_release_asset_url() {
  local install_ref="${1:-}" response asset_name

  if ! is_release_ref "$install_ref"; then
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  asset_name="$(release_asset_name "$install_ref")"
  response="$(curl -fsSL "$(release_metadata_url "$install_ref")" 2>/dev/null || true)"
  if [[ -z "$response" ]]; then
    return 1
  fi

  printf '%s\n' "$response" \
    | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -F "/${asset_name}" \
    | head -1
}

download_release_asset() {
  local asset_url="$1" extract_dir="$2" archive_path

  require_command tar "to extract hermes-fly release assets" || return 1
  mkdir -p "$extract_dir"
  archive_path="${extract_dir}/$(basename "$asset_url")"

  if ! curl -fsSL "$asset_url" -o "$archive_path"; then
    echo "Error: Failed to download release asset: ${asset_url}" >&2
    return 1
  fi

  if ! tar -xzf "$archive_path" -C "$extract_dir"; then
    echo "Error: Failed to extract release asset: ${archive_path}" >&2
    return 1
  fi

  if [[ -f "$extract_dir/hermes-fly" ]]; then
    return 0
  fi

  echo "Error: Release asset did not contain hermes-fly launcher" >&2
  return 1
}

prepare_runtime_artifacts() {
  local src_dir="$1"
  local prepare_log=""

  if [[ -f "$src_dir/dist/cli.js" && -f "$src_dir/node_modules/commander/package.json" ]]; then
    return 0
  fi

  require_command node "to build hermes-fly from source" || return 1
  require_command npm "to build hermes-fly from source" || return 1

  if [[ ! -f "$src_dir/package.json" || ! -f "$src_dir/package-lock.json" ]]; then
    echo "Error: package.json and package-lock.json are required to build hermes-fly from source" >&2
    return 1
  fi

  if [[ "${HERMES_FLY_INSTALLER_QUIET:-0}" != "1" ]]; then
    echo "Preparing hermes-fly runtime dependencies..."
  else
    prepare_log="$(mktemp)"
  fi
  if ! (
    cd "$src_dir"
    run_prepare_runtime_step "$prepare_log" run_with_sanitized_env npm ci --no-audit --no-fund
    run_prepare_runtime_step "$prepare_log" run_with_sanitized_env npm run build
    run_prepare_runtime_step "$prepare_log" run_with_sanitized_env npm prune --omit=dev --no-audit --no-fund
  ); then
    show_prepare_runtime_failure_log "$prepare_log"
    if [[ -n "$prepare_log" ]]; then
      rm -f "$prepare_log"
    fi
    echo "Error: Failed to prepare hermes-fly runtime artifacts" >&2
    return 1
  fi
  if [[ -n "$prepare_log" ]]; then
    rm -f "$prepare_log"
  fi

  if [[ ! -f "$src_dir/dist/cli.js" ]]; then
    echo "Error: Build completed without dist/cli.js" >&2
    return 1
  fi
  if [[ ! -f "$src_dir/node_modules/commander/package.json" ]]; then
    echo "Error: Runtime dependency commander was not installed" >&2
    return 1
  fi

  return 0
}

download_source_tree() {
  local install_ref="$1" dest_dir="$2"

  if [[ "${HERMES_FLY_INSTALLER_QUIET:-0}" != "1" ]]; then
    echo "Downloading hermes-fly source..."
  fi
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    local archive_path extract_root source_root
    archive_path="${dest_dir}.tar.gz"
    extract_root="${dest_dir}.extract"
    rm -rf "$dest_dir" "$extract_root"
    mkdir -p "$dest_dir" "$extract_root"
    if curl -fsSL "$(source_archive_url "$install_ref")" -o "$archive_path" \
      && tar -xzf "$archive_path" -C "$extract_root"; then
      source_root="$(find "$extract_root" -mindepth 1 -maxdepth 1 -type d | head -1)"
      if [[ -n "$source_root" && -d "$source_root" ]]; then
        cp -R "$source_root"/. "$dest_dir"/
        return 0
      fi
    fi
    rm -rf "$extract_root" "$archive_path" "$dest_dir"
  fi

  require_command git "to download hermes-fly source" || return 1
  if ! git clone --depth 1 --branch "$install_ref" --single-branch \
    "https://github.com/${REPO}.git" "$dest_dir" 2>/dev/null; then
    echo "Error: Download failed" >&2
    return 1
  fi

  return 0
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

verify_installed_version() {
  local binary_path="$1" install_ref="$2"
  local version_output actual expected

  if ! is_release_ref "$install_ref"; then
    return 0
  fi

  version_output="$("$binary_path" --version 2>&1 || true)"
  actual="$(printf '%s' "$version_output" | sed -n 's/.*hermes-fly[[:space:]]\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)"
  expected="${install_ref#v}"

  if [[ -z "$actual" ]]; then
    echo "Error: Could not determine installed hermes-fly version" >&2
    if [[ -n "$version_output" ]]; then
      printf '%s\n' "$version_output" >&2
    fi
    return 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "Error: Installed version mismatch" >&2
    echo "  Requested release: ${install_ref}" >&2
    echo "  Installed version: ${actual}" >&2
    return 1
  fi

  return 0
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
  _run rm -rf "$dest_dir/dist" "$dest_dir/node_modules" "$dest_dir/templates" "$dest_dir/data"
  _run rm -f "$dest_dir/hermes-fly" "$dest_dir/package.json" "$dest_dir/package-lock.json"
  _run cp "$src_dir/hermes-fly" "$dest_dir/"
  _run chmod +x "$dest_dir/hermes-fly"
  if [[ -d "$src_dir/templates" ]]; then
    _run cp -r "$src_dir/templates" "$dest_dir/"
  fi
  if [[ -d "$src_dir/data" ]]; then
    _run cp -r "$src_dir/data" "$dest_dir/"
  fi
  # TS runtime artifacts
  if [[ -d "$src_dir/dist" ]]; then
    _run cp -r "$src_dir/dist" "$dest_dir/"
  fi
  if [[ -f "$src_dir/package.json" ]]; then
    _run cp "$src_dir/package.json" "$dest_dir/"
  fi
  if [[ -f "$src_dir/package-lock.json" ]]; then
    _run cp "$src_dir/package-lock.json" "$dest_dir/"
  fi
  if [[ -d "$src_dir/node_modules" ]]; then
    _run cp -r "$src_dir/node_modules" "$dest_dir/"
  fi

  # Symlink into PATH
  _run mkdir -p "$bin_dir"
  _run ln -sf "$dest_dir/hermes-fly" "$bin_dir/hermes-fly"

  echo "Installed hermes-fly to $dest_dir"
  echo "Symlinked $bin_dir/hermes-fly -> $dest_dir/hermes-fly"
}

resolve_local_repo_root() {
  local script_source="${BASH_SOURCE[0]:-}"
  if [[ -z "$script_source" || ! -f "$script_source" ]]; then
    return 1
  fi

  local repo_root
  repo_root="$(cd "$(dirname "$script_source")/.." && pwd)"
  if [[ -f "$repo_root/package.json" && -f "$repo_root/package-lock.json" && -f "$repo_root/tsconfig.json" && -d "$repo_root/src" ]]; then
    printf '%s\n' "$repo_root"
    return 0
  fi

  return 1
}

read_repo_version_ref() {
  local repo_root="$1"
  local version_file="$repo_root/src/version.ts"
  local version

  if [[ ! -f "$version_file" ]]; then
    return 1
  fi

  version="$(sed -n 's/.*HERMES_FLY_TS_VERSION = "\([^"]*\)".*/\1/p' "$version_file" | head -1)"
  if [[ -z "$version" ]]; then
    return 1
  fi

  normalize_install_ref "$version"
}

resolve_bootstrap_installer_ref() {
  local repo_root

  if [[ -n "${HERMES_FLY_INSTALLER_REF:-}" ]]; then
    normalize_install_ref "$HERMES_FLY_INSTALLER_REF"
    return 0
  fi

  if repo_root="$(resolve_local_repo_root)" && read_repo_version_ref "$repo_root" >/dev/null 2>&1; then
    read_repo_version_ref "$repo_root"
    return 0
  fi

  printf '%s\n' "$DEFAULT_BOOTSTRAP_INSTALLER_REF"
}

stage_local_bootstrap_source() {
  local repo_root="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  cp "$repo_root/package.json" "$repo_root/package-lock.json" "$repo_root/tsconfig.json" "$dest_dir/"
  cp -R "$repo_root/src" "$dest_dir/"
}

bootstrap_source_supports_skip_banner() {
  local source_dir="$1"
  local marker_file="$source_dir/src/contexts/installer/application/use-cases/run-install-session.ts"

  if [[ ! -f "$marker_file" ]]; then
    return 1
  fi

  grep -q 'HERMES_FLY_INSTALLER_SKIP_BANNER' "$marker_file"
}

bootstrap_installer_cli() {
  require_command node "to run hermes-fly" || return 1
  require_command npm "to prepare the installer runtime" || return 1

  local tmp_dir bootstrap_dir local_repo_root installer_ref
  local use_shell_banner=0
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' RETURN
  bootstrap_dir="$tmp_dir/bootstrap"

  if local_repo_root="$(resolve_local_repo_root)"; then
    stage_local_bootstrap_source "$local_repo_root" "$bootstrap_dir"
  else
    installer_ref="$(resolve_bootstrap_installer_ref)" || return 1
    HERMES_FLY_INSTALLER_QUIET=1 download_source_tree "$installer_ref" "$bootstrap_dir" || return 1
  fi

  if bootstrap_source_supports_skip_banner "$bootstrap_dir"; then
    use_shell_banner=1
    print_installer_banner
  fi

  HERMES_FLY_INSTALLER_QUIET=1 prepare_runtime_artifacts "$bootstrap_dir" || return 1

  if [[ "$use_shell_banner" -eq 1 ]]; then
    HERMES_FLY_INSTALLER_SKIP_BANNER=1 node "$bootstrap_dir/dist/install-cli.js" install "$@"
  else
    node "$bootstrap_dir/dist/install-cli.js" install "$@"
  fi
}

legacy_main() {
  echo "Installing hermes-fly..."

  local platform arch install_ref install_channel source_dir asset_url
  platform="${HERMES_FLY_PLATFORM_OVERRIDE:-}"
  if [[ -z "$platform" ]]; then
    platform="$(detect_platform)" || exit 1
  fi

  arch="${HERMES_FLY_ARCH_OVERRIDE:-}"
  if [[ -z "$arch" ]]; then
    arch="$(detect_arch)" || exit 1
  fi

  install_channel="$(resolve_install_channel)" || exit 1
  if [[ -n "${HERMES_FLY_INSTALL_REF_OVERRIDE:-}" ]]; then
    install_ref="$(normalize_install_ref "$HERMES_FLY_INSTALL_REF_OVERRIDE")" || exit 1
  else
    install_ref="$(resolve_install_ref "$install_channel")" || exit 1
  fi

  require_command node "to run hermes-fly" || exit 1

  echo "Platform: $platform/$arch"
  echo "Channel: $install_channel"
  echo "Install to: $HERMES_HOME"
  echo "Symlink in: $INSTALL_DIR"
  echo "Release: $install_ref"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  if [[ -n "${HERMES_FLY_INSTALL_SOURCE_DIR_OVERRIDE:-}" ]]; then
    source_dir="${HERMES_FLY_INSTALL_SOURCE_DIR_OVERRIDE}"
  else
    source_dir="$tmp_dir/hermes-fly"
    asset_url=""
    if asset_url="$(resolve_release_asset_url "$install_ref")"; then
      echo "Downloading hermes-fly release asset..."
      download_release_asset "$asset_url" "$source_dir" || exit 1
    else
      download_source_tree "$install_ref" "$source_dir" || exit 1
    fi
  fi

  if [[ ! -f "$source_dir/dist/cli.js" || ! -f "$source_dir/node_modules/commander/package.json" ]]; then
    prepare_runtime_artifacts "$source_dir" || exit 1
  fi

  install_files "$source_dir" "$HERMES_HOME" "$INSTALL_DIR"

  # Show installed version
  local version
  verify_installed_version "$INSTALL_DIR/hermes-fly" "$install_ref" || exit 1
  version="$("$INSTALL_DIR/hermes-fly" --version 2>/dev/null || echo "hermes-fly (unknown version)")"

  echo ""
  echo "hermes-fly installed successfully!"
  echo "  $version"
  echo "Run 'hermes-fly deploy' to get started."
}

assign_legacy_fallback_override() {
  local option="$1" value="$2"

  if [[ -z "$value" ]]; then
    echo "Error: Missing value for installer option: $option" >&2
    return 1
  fi

  case "$option" in
    --channel | --version | --install-home | --bin-dir | --ref | --source-dir | --platform | --arch)
      return 0
      ;;
    *)
      echo "Error: Unsupported installer option for legacy fallback: $option" >&2
      return 1
      ;;
  esac
}

prepare_legacy_fallback_args() {
  local channel_override=""
  local version_override=""
  local install_home_override=""
  local bin_dir_override=""
  local ref_override=""
  local source_dir_override=""
  local platform_override=""
  local arch_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel | --version | --install-home | --bin-dir | --ref | --source-dir | --platform | --arch)
        if [[ $# -lt 2 ]]; then
          echo "Error: Missing value for installer option: $1" >&2
          return 1
        fi
        assign_legacy_fallback_override "$1" "$2" || return 1
        case "$1" in
          --channel) channel_override="$2" ;;
          --version) version_override="$2" ;;
          --install-home) install_home_override="$2" ;;
          --bin-dir) bin_dir_override="$2" ;;
          --ref) ref_override="$2" ;;
          --source-dir) source_dir_override="$2" ;;
          --platform) platform_override="$2" ;;
          --arch) arch_override="$2" ;;
        esac
        shift 2
        ;;
      --channel=* | --version=* | --install-home=* | --bin-dir=* | --ref=* | --source-dir=* | --platform=* | --arch=*)
        local option="${1%%=*}"
        local value="${1#*=}"
        assign_legacy_fallback_override "$option" "$value" || return 1
        case "$option" in
          --channel) channel_override="$value" ;;
          --version) version_override="$value" ;;
          --install-home) install_home_override="$value" ;;
          --bin-dir) bin_dir_override="$value" ;;
          --ref) ref_override="$value" ;;
          --source-dir) source_dir_override="$value" ;;
          --platform) platform_override="$value" ;;
          --arch) arch_override="$value" ;;
        esac
        shift
        ;;
      --method)
        echo "Error: Unsupported installer option for legacy fallback: $1" >&2
        return 1
        ;;
      --*=*)
        echo "Error: Unsupported installer option for legacy fallback: ${1%%=*}" >&2
        return 1
        ;;
      -h | --help)
        echo "Error: Unsupported installer option for legacy fallback: $1" >&2
        return 1
        ;;
      --)
        shift
        if [[ $# -gt 0 ]]; then
          echo "Error: Unsupported installer arguments for legacy fallback: $*" >&2
          return 1
        fi
        break
        ;;
      -*)
        echo "Error: Unsupported installer option for legacy fallback: $1" >&2
        return 1
        ;;
      *)
        echo "Error: Unsupported installer argument for legacy fallback: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -n "$channel_override" ]]; then
    export HERMES_FLY_CHANNEL="$channel_override"
  fi
  if [[ -n "$install_home_override" ]]; then
    export HERMES_FLY_HOME="$install_home_override"
    export HERMES_HOME="$install_home_override"
  fi
  if [[ -n "$bin_dir_override" ]]; then
    export HERMES_FLY_INSTALL_DIR="$bin_dir_override"
    INSTALL_DIR="$bin_dir_override"
  fi
  if [[ -n "$source_dir_override" ]]; then
    export HERMES_FLY_INSTALL_SOURCE_DIR_OVERRIDE="$source_dir_override"
  fi
  if [[ -n "$platform_override" ]]; then
    export HERMES_FLY_PLATFORM_OVERRIDE="$platform_override"
  fi
  if [[ -n "$arch_override" ]]; then
    export HERMES_FLY_ARCH_OVERRIDE="$arch_override"
  fi
  if [[ -n "$ref_override" ]]; then
    export HERMES_FLY_INSTALL_REF_OVERRIDE="$ref_override"
    unset HERMES_FLY_VERSION
  elif [[ -n "$version_override" ]]; then
    export HERMES_FLY_VERSION="$version_override"
    unset HERMES_FLY_INSTALL_REF_OVERRIDE
  fi
}

main() {
  if bootstrap_installer_cli "$@"; then
    return 0
  fi

  prepare_legacy_fallback_args "$@" || return 1
  legacy_main
}

# Only run main if not being sourced (for testing)
# `return` succeeds only when sourced; fails when executed or piped.
(return 0 2>/dev/null) || main "$@"
