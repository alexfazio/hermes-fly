#!/usr/bin/env bash
set -euo pipefail

# hermes-fly installer
# Usage: curl -fsSL https://get.hermes-fly.dev/install.sh | bash

REPO="alexfazio/hermes-fly"
INSTALL_DIR="${HERMES_FLY_INSTALL_DIR:-}"
HERMES_HOME="${HERMES_FLY_HOME:-}"
RELEASE_API_URL="${HERMES_FLY_RELEASE_API_URL:-https://api.github.com/repos/${REPO}/releases/latest}"
SAFE_PROCESS_LOCALE="C"
INSTALL_MARKER_FILENAME=".hermes-fly-install-managed"
LEGACY_INSTALL_HOME="/usr/local/lib/hermes-fly"
LEGACY_BIN_DIR="/usr/local/bin"
# Standalone install.sh must bootstrap the checked installer revision, not a mutable branch tip.
DEFAULT_BOOTSTRAP_INSTALLER_REF="v0.1.100"
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

resolve_home_dir_hint() {
  local home_dir="${HOME:-}" derived_home
  if [[ -n "$home_dir" ]]; then
    printf '%s\n' "$home_dir"
    return 0
  fi

  derived_home="$(CDPATH= cd -- ~ 2>/dev/null && pwd -P)" || return 1
  printf '%s\n' "$derived_home"
}

resolve_home_dir_path() {
  local home_dir
  home_dir="$(resolve_home_dir_hint 2>/dev/null || true)"
  if [[ -z "$home_dir" ]]; then
    return 1
  fi
  if [[ "$home_dir" == /* ]]; then
    printf '%s\n' "$home_dir"
    return 0
  fi
  if [[ -d "$home_dir" ]]; then
    (CDPATH= cd -- "$home_dir" && pwd -P)
    return 0
  fi
  printf '%s\n' "$home_dir"
}

is_effective_root_user() {
  local uid_value="${EUID:-}"
  if [[ -n "$uid_value" ]]; then
    [[ "$uid_value" -eq 0 ]]
    return
  fi

  [[ "$(id -u)" -eq 0 ]]
}

canonicalize_existing_dir_path() {
  local dir_path="$1"
  if [[ -d "$dir_path" ]]; then
    (CDPATH= cd -- "$dir_path" && pwd -P)
    return 0
  fi
  printf '%s\n' "$dir_path"
}

canonicalize_existing_path() {
  local target_path="$1" parent_dir
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    parent_dir="$(canonicalize_existing_dir_path "$(dirname -- "$target_path")")" || return 1
    printf '%s/%s\n' "$parent_dir" "$(basename -- "$target_path")"
    return 0
  fi
  printf '%s\n' "$target_path"
}

resolve_search_dir_path() {
  local dir_path="$1"
  if [[ "$dir_path" == /* ]]; then
    printf '%s\n' "$dir_path"
    return 0
  fi
  if [[ -d "$dir_path" ]]; then
    (CDPATH= cd -- "$dir_path" && pwd)
    return 0
  fi
  if [[ "$PWD" == "/" ]]; then
    printf '/%s\n' "$dir_path"
  else
    printf '%s/%s\n' "$PWD" "$dir_path"
  fi
}

resolve_default_install_home() {
  local platform="$1" home_dir data_home
  if is_effective_root_user; then
    canonicalize_existing_path "$LEGACY_INSTALL_HOME"
    return 0
  fi
  home_dir="$(resolve_home_dir_path 2>/dev/null || true)"
  case "$platform" in
    darwin)
      if [[ -n "$home_dir" ]]; then
        printf '%s/Library/Application Support/hermes-fly\n' "$home_dir"
      else
        canonicalize_existing_path "$LEGACY_INSTALL_HOME"
      fi
      ;;
    linux)
      data_home="${XDG_DATA_HOME:-}"
      if [[ -n "$data_home" && "$data_home" == /* ]]; then
        printf '%s/hermes-fly\n' "$data_home"
      elif [[ -n "$home_dir" ]]; then
        printf '%s/.local/share/hermes-fly\n' "$home_dir"
      else
        canonicalize_existing_path "$LEGACY_INSTALL_HOME"
      fi
      ;;
    *)
      echo "Error: Unsupported installer platform for path resolution: $platform" >&2
      return 1
      ;;
  esac
}

resolve_default_bin_dir() {
  local home_dir
  if is_effective_root_user; then
    canonicalize_existing_dir_path "$LEGACY_BIN_DIR"
    return 0
  fi
  home_dir="$(resolve_home_dir_path 2>/dev/null || true)"
  if [[ -n "$home_dir" ]]; then
    printf '%s/.local/bin\n' "$home_dir"
  else
    canonicalize_existing_dir_path "$LEGACY_BIN_DIR"
  fi
}

resolve_path_fix_hint() {
  local shell_path="${1:-}"
  case "$shell_path" in
    *zsh) printf 'zsh: ~/.zshrc, bash: ~/.bashrc\n' ;;
    *bash) printf 'bash: ~/.bashrc, zsh: ~/.zshrc\n' ;;
    *) printf 'shell profile: ~/.profile\n' ;;
  esac
}

path_contains_dir() {
  local path_value="${1:-}" bin_dir="$2" path_entry
  [[ -n "$path_value" ]] || return 1

  while true; do
    case "$path_value" in
      *:*)
        path_entry="${path_value%%:*}"
        path_value="${path_value#*:}"
        ;;
      *)
        path_entry="$path_value"
        path_value=""
        ;;
    esac

    if [[ "$path_entry" == "$bin_dir" ]]; then
      return 0
    fi

    [[ -n "$path_value" ]] || break
  done

  return 1
}

print_path_guidance_if_needed() {
  local bin_dir="$1"
  if path_contains_dir "${PATH:-}" "$bin_dir"; then
    return 0
  fi

  echo "PATH missing hermes-fly bin dir: $bin_dir"
  echo '  This can make hermes-fly show as "command not found" in new terminals.'
  echo "  Fix ($(resolve_path_fix_hint "${SHELL:-}")):"
  echo "    export PATH=\"$bin_dir:\$PATH\""
  echo ""
}

is_known_managed_install_layout() {
  local install_home="$1" bin_dir="$2" candidate_home candidate_bin normalized_install_home normalized_bin_dir normalized_candidate_home normalized_candidate_bin
  normalized_install_home="$(canonicalize_existing_path "$install_home")" || return 1
  normalized_bin_dir="$(canonicalize_existing_dir_path "$bin_dir")" || return 1
  while IFS='|' read -r candidate_home candidate_bin; do
    normalized_candidate_home="$(canonicalize_existing_path "$candidate_home")" || return 1
    normalized_candidate_bin="$(canonicalize_existing_dir_path "$candidate_bin")" || return 1
    if [[ "$normalized_install_home" == "$normalized_candidate_home" && "$normalized_bin_dir" == "$normalized_candidate_bin" ]]; then
      return 0
    fi
  done < <(resolve_known_managed_install_layouts 2>/dev/null || true)

  return 1
}

is_system_managed_install_layout() {
  local install_home="$1" bin_dir="$2" normalized_install_home normalized_bin_dir normalized_system_home normalized_system_bin
  normalized_install_home="$(canonicalize_existing_path "$install_home")" || return 1
  normalized_bin_dir="$(canonicalize_existing_dir_path "$bin_dir")" || return 1
  normalized_system_home="$(canonicalize_existing_path "$LEGACY_INSTALL_HOME")" || return 1
  normalized_system_bin="$(canonicalize_existing_dir_path "$LEGACY_BIN_DIR")" || return 1

  [[ "$normalized_install_home" == "$normalized_system_home" && "$normalized_bin_dir" == "$normalized_system_bin" ]]
}

resolve_current_user_local_install_homes() {
  local home_dir data_home
  home_dir="$(resolve_home_dir_path 2>/dev/null || true)"
  if [[ -n "$home_dir" ]]; then
    printf '%s\n' "$home_dir/Library/Application Support/hermes-fly"
    printf '%s\n' "$home_dir/.local/lib/hermes-fly"
  fi

  data_home="${XDG_DATA_HOME:-}"
  if [[ -n "$data_home" && "$data_home" == /* ]]; then
    printf '%s\n' "$data_home/hermes-fly"
  elif [[ -n "$home_dir" ]]; then
    printf '%s\n' "$home_dir/.local/share/hermes-fly"
  fi
}

is_user_local_managed_install_layout() {
  local install_home="$1" bin_dir="$2" normalized_install_home normalized_bin_dir candidate_home normalized_candidate_home
  normalized_install_home="$(canonicalize_existing_path "$install_home")" || return 1
  normalized_bin_dir="$(canonicalize_existing_dir_path "$bin_dir")" || return 1

  [[ "$normalized_bin_dir" == */.local/bin ]] || return 1

  while IFS= read -r candidate_home; do
    [[ -n "$candidate_home" ]] || continue
    normalized_candidate_home="$(canonicalize_existing_path "$candidate_home" 2>/dev/null || true)"
    [[ -n "$normalized_candidate_home" ]] || continue
    if [[ "$normalized_install_home" == "$normalized_candidate_home" ]]; then
      return 0
    fi
  done < <(resolve_current_user_local_install_homes 2>/dev/null || true)

  return 1
}

existing_install_layout_reusable_for_current_mode() {
  local install_home="$1" bin_dir="$2"
  if is_effective_root_user && is_user_local_managed_install_layout "$install_home" "$bin_dir"; then
    return 1
  fi
  return 0
}

resolve_known_managed_install_layouts() {
  local home_dir legacy_install_home legacy_bin_dir user_bin_dir user_install_home data_home
  home_dir="$(resolve_home_dir_path 2>/dev/null || true)"
  legacy_install_home="$(canonicalize_existing_path "$LEGACY_INSTALL_HOME")" || return 1
  legacy_bin_dir="$(canonicalize_existing_dir_path "$LEGACY_BIN_DIR")" || return 1
  if [[ -n "$home_dir" ]]; then
    user_bin_dir="$home_dir/.local/bin"
    user_install_home="$home_dir/Library/Application Support/hermes-fly"
    printf '%s|%s\n' "$user_install_home" "$user_bin_dir"

    data_home="${XDG_DATA_HOME:-}"
    if [[ -n "$data_home" && "$data_home" == /* ]]; then
      user_install_home="$data_home/hermes-fly"
    else
      user_install_home="$home_dir/.local/share/hermes-fly"
    fi
    printf '%s|%s\n' "$user_install_home" "$user_bin_dir"
    printf '%s|%s\n' "$home_dir/.local/lib/hermes-fly" "$user_bin_dir"
  fi
  printf '%s|%s\n' "$legacy_install_home" "$legacy_bin_dir"
}

is_repo_checkout_install_layout() {
  local install_home="$1"
  if [[ -f "$install_home/package.json" && -f "$install_home/package-lock.json" && -f "$install_home/tsconfig.json" && -d "$install_home/src" ]]; then
    return 0
  fi
  [[ -f "$install_home/README.md" ]] || return 1
  [[ -f "$install_home/scripts/install.sh" ]] || return 1
  [[ -d "$install_home/tests" ]] || return 1
  return 0
}

is_legacy_lib_install_layout() {
  local install_home="$1"
  [[ -f "$install_home/lib/ui.sh" ]]
}

is_pre_marker_runtime_install_layout() {
  local install_home="$1"
  [[ -f "$install_home/package.json" ]] || return 1
  [[ -f "$install_home/package-lock.json" ]] || return 1
  [[ -f "$install_home/node_modules/commander/package.json" ]] || return 1
  return 0
}

resolve_existing_install_layout_from_candidate() {
  local install_home="$1" bin_dir="$2"

  [[ -n "$install_home" && -n "$bin_dir" ]] || return 1

  is_repo_checkout_install_layout "$install_home" && return 1

  if [[ -f "$install_home/dist/cli.js" ]]; then
    if [[ -f "$install_home/$INSTALL_MARKER_FILENAME" ]] || is_known_managed_install_layout "$install_home" "$bin_dir"; then
      printf '%s|%s\n' "$install_home" "$bin_dir"
      return 0
    fi
    is_pre_marker_runtime_install_layout "$install_home" || return 1
    printf '%s|%s\n' "$install_home" "$bin_dir"
    return 0
  fi

  is_legacy_lib_install_layout "$install_home" || return 1
  is_known_managed_install_layout "$install_home" "$bin_dir" || return 1
  printf '%s|%s\n' "$install_home" "$bin_dir"
}

resolve_existing_install_layout_from_launcher() {
  local bin_path="$1" resolved dir resolved_dir install_home bin_dir launcher_path symlink_hops=0 max_symlink_hops=40

  if [[ -z "$bin_path" ]]; then
    return 1
  fi
  case "$bin_path" in
    /*) ;;
    *) return 1 ;;
  esac
  if [[ ! -e "$bin_path" && ! -L "$bin_path" ]]; then
    return 1
  fi

  resolved="$bin_path"
  launcher_path="$bin_path"
  while [[ -L "$resolved" ]]; do
    symlink_hops=$((symlink_hops + 1))
    if [[ "$symlink_hops" -gt "$max_symlink_hops" ]]; then
      return 1
    fi
    launcher_path="$resolved"
    dir="$(CDPATH= cd -- "$(dirname -- "$resolved")" && pwd -P)" || return 1
    resolved="$(readlink "$resolved")" || return 1
    case "$resolved" in
      /*) ;;
      *) resolved="${dir}/${resolved}" ;;
    esac
  done
  resolved_dir="$(CDPATH= cd -- "$(dirname -- "$resolved")" && pwd -P)" || return 1
  resolved="${resolved_dir}/$(basename -- "$resolved")"
  [[ -f "$resolved" ]] || return 1
  [[ "$launcher_path" != "$resolved" ]] || return 1

  install_home="$(CDPATH= cd -- "$(dirname -- "$resolved")" && pwd -P)" || return 1
  bin_dir="$(resolve_search_dir_path "$(dirname -- "$launcher_path")")" || return 1
  [[ "$resolved" == "$install_home/hermes-fly" ]] || return 1
  resolve_existing_install_layout_from_candidate "$install_home" "$bin_dir"
}

list_path_install_launchers() {
  local remaining_path="${PATH:-}" path_entry path_dir launcher_path
  if [[ -z "$remaining_path" ]]; then
    remaining_path="."
  fi

  while true; do
    case "$remaining_path" in
      *:*)
        path_entry="${remaining_path%%:*}"
        remaining_path="${remaining_path#*:}"
        ;;
      *)
        path_entry="$remaining_path"
        remaining_path=""
        ;;
    esac

    if [[ -z "$path_entry" ]]; then
      path_entry="."
    fi

    path_dir="$(resolve_search_dir_path "$path_entry" 2>/dev/null || printf '%s\n' "$path_entry")"
    launcher_path="${path_dir}/hermes-fly"
    if [[ -e "$launcher_path" || -L "$launcher_path" ]]; then
      printf '%s\n' "$launcher_path"
    fi

    if [[ -z "$remaining_path" ]]; then
      break
    fi
  done
}

resolve_existing_install_layout() {
  local bin_path resolved_layout install_home bin_dir
  while IFS= read -r bin_path; do
    [[ -n "$bin_path" ]] || continue
    resolved_layout="$(resolve_existing_install_layout_from_launcher "$bin_path" 2>/dev/null || true)"
    if [[ -n "$resolved_layout" ]]; then
      install_home="${resolved_layout%%|*}"
      bin_dir="${resolved_layout#*|}"
      if existing_install_layout_reusable_for_current_mode "$install_home" "$bin_dir"; then
        printf '%s\n' "$resolved_layout"
        return 0
      fi
    fi
  done < <(list_path_install_launchers 2>/dev/null || true)

  while IFS='|' read -r install_home bin_dir; do
    [[ -n "$install_home" && -n "$bin_dir" ]] || continue
    resolved_layout="$(resolve_existing_install_layout_from_launcher "$bin_dir/hermes-fly" 2>/dev/null || true)"
    if [[ -n "$resolved_layout" ]]; then
      install_home="${resolved_layout%%|*}"
      bin_dir="${resolved_layout#*|}"
      if existing_install_layout_reusable_for_current_mode "$install_home" "$bin_dir"; then
        printf '%s\n' "$resolved_layout"
        return 0
      fi
    fi
    resolved_layout="$(resolve_existing_install_layout_from_candidate "$install_home" "$bin_dir" 2>/dev/null || true)"
    if [[ -n "$resolved_layout" ]]; then
      install_home="${resolved_layout%%|*}"
      bin_dir="${resolved_layout#*|}"
      if existing_install_layout_reusable_for_current_mode "$install_home" "$bin_dir"; then
        printf '%s\n' "$resolved_layout"
        return 0
      fi
    fi
  done < <(resolve_known_managed_install_layouts 2>/dev/null || true)

  return 1
}

resolve_install_layout() {
  local platform="$1" existing_layout="" existing_home="" existing_bin="" has_install_override=0
  if [[ -n "${HERMES_HOME:-}" || -n "${INSTALL_DIR:-}" || -n "${HERMES_FLY_HOME:-}" || -n "${HERMES_FLY_INSTALL_DIR:-}" ]]; then
    has_install_override=1
  fi
  if [[ "$has_install_override" -eq 0 && ( -z "${HERMES_HOME:-}" || -z "${INSTALL_DIR:-}" ) ]]; then
    existing_layout="$(resolve_existing_install_layout 2>/dev/null || true)"
    if [[ -n "$existing_layout" ]]; then
      existing_home="${existing_layout%%|*}"
      existing_bin="${existing_layout#*|}"
    fi
  fi

  if [[ -z "${HERMES_HOME:-}" ]]; then
    if [[ -n "$existing_home" ]]; then
      HERMES_HOME="$existing_home"
    else
      HERMES_HOME="$(resolve_default_install_home "$platform")" || return 1
    fi
  fi
  if [[ -z "${INSTALL_DIR:-}" ]]; then
    if [[ -n "$existing_bin" ]]; then
      INSTALL_DIR="$existing_bin"
    else
      INSTALL_DIR="$(resolve_default_bin_dir)" || return 1
    fi
  fi

  export HERMES_HOME
  export HERMES_FLY_HOME="${HERMES_FLY_HOME:-$HERMES_HOME}"
  export HERMES_FLY_INSTALL_DIR="${HERMES_FLY_INSTALL_DIR:-$INSTALL_DIR}"
}

resolve_bootstrap_install_layout() {
  local platform="${HERMES_FLY_PLATFORM_OVERRIDE:-}"
  local install_home="${HERMES_HOME:-}"
  local bin_dir="${INSTALL_DIR:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform)
        if [[ $# -lt 2 ]]; then
          break
        fi
        platform="$2"
        shift 2
        ;;
      --platform=*)
        platform="${1#*=}"
        shift
        ;;
      --install-home)
        if [[ $# -lt 2 ]]; then
          break
        fi
        install_home="$2"
        shift 2
        ;;
      --install-home=*)
        install_home="${1#*=}"
        shift
        ;;
      --bin-dir)
        if [[ $# -lt 2 ]]; then
          break
        fi
        bin_dir="$2"
        shift 2
        ;;
      --bin-dir=*)
        bin_dir="${1#*=}"
        shift
        ;;
      --)
        break
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -z "$platform" ]]; then
    platform="$(detect_platform)" || return 1
  fi

  HERMES_HOME="$install_home"
  INSTALL_DIR="$bin_dir"
  resolve_install_layout "$platform"
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
  local dir="$1" probe_dir parent_dir
  probe_dir="$dir"
  while [[ ! -e "$probe_dir" ]]; do
    parent_dir="$(dirname "$probe_dir")"
    if [[ "$parent_dir" == "$probe_dir" ]]; then
      break
    fi
    probe_dir="$parent_dir"
  done

  if [[ ! -w "$probe_dir" ]]; then
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
  local marker_dir marker_path

  # Detect if sudo is needed for either directory
  _USE_SUDO=0
  if _needs_sudo "$dest_dir" || _needs_sudo "$bin_dir"; then
    echo "Need elevated permissions to install to $dest_dir"
    if command -v sudo >/dev/null 2>&1; then
      _USE_SUDO=1
    else
      local suggestion_platform suggestion_home suggestion_bin
      suggestion_platform="${HERMES_FLY_PLATFORM_OVERRIDE:-}"
      if [[ -z "$suggestion_platform" ]]; then
        suggestion_platform="$(detect_platform)" || return 1
      fi
      suggestion_home="$(resolve_default_install_home "$suggestion_platform")" || return 1
      suggestion_bin="$(resolve_default_bin_dir)" || return 1
      echo "Error: Cannot write to $dest_dir and sudo is not available" >&2
      printf 'Try: HERMES_FLY_INSTALL_DIR="%s" HERMES_FLY_HOME="%s" bash install.sh\n' "$suggestion_bin" "$suggestion_home" >&2
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
  marker_dir="$(mktemp -d)"
  marker_path="${marker_dir}/${INSTALL_MARKER_FILENAME}"
  printf '{"install_ref":"%s"}\n' "${HERMES_FLY_VERSION:-unknown}" > "$marker_path"
  _run cp "$marker_path" "$dest_dir/$INSTALL_MARKER_FILENAME"
  rm -rf "$marker_dir"

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
  local installer_args=()
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
  resolve_bootstrap_install_layout "$@" || return 1
  installer_args=(install --install-home "$HERMES_HOME" --bin-dir "$INSTALL_DIR")

  if [[ "$use_shell_banner" -eq 1 ]]; then
    HERMES_FLY_INSTALLER_SKIP_BANNER=1 node "$bootstrap_dir/dist/install-cli.js" "${installer_args[@]}" "$@"
  else
    node "$bootstrap_dir/dist/install-cli.js" "${installer_args[@]}" "$@"
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
  resolve_install_layout "$platform" || exit 1

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

  print_path_guidance_if_needed "$INSTALL_DIR"

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
