#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/package-release-asset.sh vX.Y.Z [out_dir]

Builds a portable hermes-fly release archive containing:
  - hermes-fly launcher
  - dist/
  - package.json
  - package-lock.json
  - production node_modules/
  - templates/
  - data/
EOF
}

repo_root() {
  if [[ -n "${HERMES_FLY_PACKAGE_SOURCE_DIR:-}" ]]; then
    printf '%s\n' "$HERMES_FLY_PACKAGE_SOURCE_DIR"
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

tar_supports_flag() {
  local flag="$1"
  tar --help 2>&1 | grep -F -q -- "$flag"
}

create_portable_tarball() {
  local source_dir="$1" archive_path="$2"
  local -a extra_flags=()

  if tar_supports_flag "--format"; then
    extra_flags+=(--format ustar)
  fi
  if tar_supports_flag "--no-mac-metadata"; then
    extra_flags+=(--no-mac-metadata)
  fi
  if tar_supports_flag "--no-xattrs"; then
    extra_flags+=(--no-xattrs)
  fi
  if tar_supports_flag "--no-acls"; then
    extra_flags+=(--no-acls)
  fi

  if [[ ${#extra_flags[@]} -gt 0 ]]; then
    COPYFILE_DISABLE=1 \
    COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
      tar "${extra_flags[@]}" -czf "$archive_path" -C "$source_dir" .
  else
    COPYFILE_DISABLE=1 \
    COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
      tar -czf "$archive_path" -C "$source_dir" .
  fi
}

package_release_asset() {
  local tag="${1:-}" out_dir="${2:-}"
  if [[ -z "$tag" ]]; then
    usage >&2
    return 1
  fi
  if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: tag must use semver format (e.g. v0.1.26): ${tag}" >&2
    return 1
  fi

  local src_root
  src_root="$(repo_root)"
  if [[ -z "$out_dir" ]]; then
    out_dir="${HERMES_FLY_PACKAGE_OUT_DIR:-$src_root/dist-release}"
  fi

  local stage_dir
  stage_dir="$(mktemp -d)"
  trap 'rm -rf "${stage_dir:-}"' RETURN

  if [[ ! -f "$src_root/hermes-fly" || ! -f "$src_root/package.json" || ! -f "$src_root/package-lock.json" ]]; then
    echo "Error: package source tree is missing required release files" >&2
    return 1
  fi
  if [[ ! -f "$src_root/dist/cli.js" ]]; then
    echo "Error: dist/cli.js is missing. Run npm run build before packaging." >&2
    return 1
  fi

  mkdir -p "$out_dir"
  cp "$src_root/hermes-fly" "$stage_dir/"
  cp "$src_root/package.json" "$src_root/package-lock.json" "$stage_dir/"
  cp -R "$src_root/dist" "$stage_dir/"
  if [[ -d "$src_root/templates" ]]; then
    cp -R "$src_root/templates" "$stage_dir/"
  fi
  if [[ -d "$src_root/data" ]]; then
    cp -R "$src_root/data" "$stage_dir/"
  fi

  (
    cd "$stage_dir"
    npm ci --omit=dev >/dev/null
  )

  local archive_path="${out_dir}/hermes-fly-${tag}.tar.gz"
  create_portable_tarball "$stage_dir" "$archive_path"
  printf '%s\n' "$archive_path"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  package_release_asset "${1:-}" "${2:-}"
fi
