#!/usr/bin/env bats
# tests/install.bats — TDD tests for scripts/install.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  source "${PROJECT_ROOT}/scripts/install.sh"
}

teardown() {
  _common_teardown
}

write_source_checkout() {
  local dest="$1"

  mkdir -p "$dest/templates" "$dest/data"
  cat > "$dest/hermes-fly" <<'MOCK'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "${SCRIPT_DIR}/dist/cli.js" "$@"
MOCK
  chmod +x "$dest/hermes-fly"

  cat > "$dest/package.json" <<'JSON'
{"name":"hermes-fly","type":"module","dependencies":{"commander":"^12.1.0"},"scripts":{"build":"tsc -p tsconfig.json"}}
JSON
  cat > "$dest/package-lock.json" <<'JSON'
{"name":"hermes-fly","lockfileVersion":3}
JSON
  echo 'tpl' > "$dest/templates/Dockerfile.template"
  echo '{}' > "$dest/data/reasoning-snapshot.json"
}

write_mock_npm() {
  local mock_dir="$1"

  cat > "$mock_dir/npm" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_NPM_ARGS_FILE}"
if [[ "${1:-}" == "ci" ]]; then
  mkdir -p "$PWD/node_modules/commander"
  echo '{"name":"commander"}' > "$PWD/node_modules/commander/package.json"
  exit 0
fi
if [[ "${1:-}" == "run" && "${2:-}" == "build" ]]; then
  mkdir -p "$PWD/dist"
  echo 'console.log("hermes-fly test build")' > "$PWD/dist/cli.js"
  exit 0
fi
if [[ "${1:-}" == "prune" && "${2:-}" == "--omit=dev" ]]; then
  exit 0
fi
echo "unexpected npm invocation: $*" >&2
exit 1
MOCK
  chmod +x "$mock_dir/npm"
}

write_mock_node() {
  local mock_dir="$1"
  local version="$2"

  cat > "$mock_dir/node" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${MOCK_NODE_ARGS_FILE}"
if [[ "\$*" == *"--version"* ]]; then
  echo "hermes-fly ${version}"
  exit 0
fi
echo "unexpected node invocation: \$*" >&2
exit 1
MOCK
  chmod +x "$mock_dir/node"
}

write_mock_release_tar() {
  local mock_dir="$1"

  cat > "$mock_dir/tar" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--no-mac-metadata'
  printf '%s\n' '--no-xattrs'
  printf '%s\n' '--no-acls'
  exit 0
fi

{
  printf 'COPYFILE_DISABLE=%s\n' "${COPYFILE_DISABLE:-}"
  printf 'COPY_EXTENDED_ATTRIBUTES_DISABLE=%s\n' "${COPY_EXTENDED_ATTRIBUTES_DISABLE:-}"
  printf 'ARGS=%s\n' "$*"
} > "${MOCK_TAR_ARGS_FILE}"

archive_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -czf)
      archive_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

: > "$archive_path"
MOCK
  chmod +x "$mock_dir/tar"
}

# --- detect_platform ---

@test "detect_platform returns darwin or linux" {
  run detect_platform
  assert_success
  [[ "$output" == "darwin" ]] || [[ "$output" == "linux" ]]
}

# --- detect_arch ---

@test "detect_arch returns amd64 or arm64" {
  run detect_arch
  assert_success
  [[ "$output" == "amd64" ]] || [[ "$output" == "arm64" ]]
}

# --- verify_checksum ---

@test "verify_checksum returns 0 on match" {
  local test_file="${TEST_TEMP_DIR}/checksum_test"
  echo "hello world" > "$test_file"
  local expected
  if command -v sha256sum >/dev/null 2>&1; then
    expected="$(sha256sum "$test_file" | cut -d' ' -f1)"
  else
    expected="$(shasum -a 256 "$test_file" | cut -d' ' -f1)"
  fi
  run verify_checksum "$test_file" "$expected"
  assert_success
}

@test "verify_checksum returns 1 on mismatch" {
  local test_file="${TEST_TEMP_DIR}/checksum_test"
  echo "hello world" > "$test_file"
  run verify_checksum "$test_file" "0000000000000000000000000000000000000000000000000000000000000000"
  assert_failure
}

# --- install_files ---

@test "install_files copies project files and creates symlink" {
  # Create a fake project layout
  local src="${TEST_TEMP_DIR}/src"
  mkdir -p "$src/templates" "$src/data"
  echo '#!/bin/sh' > "$src/hermes-fly"
  echo 'template' > "$src/templates/Dockerfile.template"
  echo '{"schema_version":"1"}' > "$src/data/reasoning-snapshot.json"

  local dest="${TEST_TEMP_DIR}/hermes-home"
  local bin="${TEST_TEMP_DIR}/bin"
  run install_files "$src" "$dest" "$bin"
  assert_success
  assert [ -f "${dest}/hermes-fly" ]
  assert [ -x "${dest}/hermes-fly" ]
  assert [ -f "${dest}/templates/Dockerfile.template" ]
  assert [ -f "${dest}/data/reasoning-snapshot.json" ]
  assert [ -L "${bin}/hermes-fly" ]
}

@test "install_files copies dist/ for TS runtime" {
  # Create a fake project layout with dist/
  local src="${TEST_TEMP_DIR}/src"
  mkdir -p "$src/dist" "$src/templates" "$src/node_modules/commander"
  echo '#!/usr/bin/env bash' > "$src/hermes-fly"
  chmod +x "$src/hermes-fly"
  echo '// compiled cli' > "$src/dist/cli.js"
  echo '{"name":"commander"}' > "$src/node_modules/commander/package.json"
  echo '{"type":"module"}' > "$src/package.json"
  echo '{"lockfileVersion":3}' > "$src/package-lock.json"

  local dest="${TEST_TEMP_DIR}/hermes-home"
  local bin="${TEST_TEMP_DIR}/bin"
  run install_files "$src" "$dest" "$bin"
  assert_success
  assert [ -f "${dest}/dist/cli.js" ]
  assert [ -f "${dest}/node_modules/commander/package.json" ]
  assert [ -f "${dest}/package.json" ]
  assert [ -f "${dest}/package-lock.json" ]
}

@test "prepare_runtime_artifacts builds dist and runtime dependencies when missing" {
  local src="${TEST_TEMP_DIR}/src"
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args"

  mkdir -p "$mock_dir"
  write_source_checkout "$src"
  write_mock_npm "$mock_dir"

  run bash -c '
    export PATH="'"$mock_dir"':${PATH}"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    prepare_runtime_artifacts "'"$src"'"
  '
  assert_success
  assert_output --partial "Preparing hermes-fly runtime dependencies"
  assert [ -f "${src}/dist/cli.js" ]
  assert [ -f "${src}/node_modules/commander/package.json" ]

  run cat "$npm_args_file"
  assert_success
  assert_output --partial "ci"
  assert_output --partial "run build"
  assert_output --partial "prune --omit=dev"
}

@test "verify_installed_version surfaces launcher failure output" {
  local broken="${TEST_TEMP_DIR}/broken-hermes-fly"
  cat > "$broken" <<'MOCK'
#!/usr/bin/env bash
echo "Error: Cannot find module '/usr/local/lib/hermes-fly/dist/cli.js'" >&2
exit 1
MOCK
  chmod +x "$broken"

  run verify_installed_version "$broken" "v0.1.12"
  assert_failure
  assert_output --partial "Could not determine installed hermes-fly version"
  assert_output --partial "Cannot find module '/usr/local/lib/hermes-fly/dist/cli.js'"
}

@test "package_release_asset creates a portable tarball without macOS metadata" {
  local src="${TEST_TEMP_DIR}/release_src"
  local out="${TEST_TEMP_DIR}/out"
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args"
  local tar_args_file="${TEST_TEMP_DIR}/tar_args"

  mkdir -p "$src/dist" "$src/templates" "$src/data" "$mock_dir"
  cat > "$src/hermes-fly" <<'MOCK'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "${SCRIPT_DIR}/dist/cli.js" "$@"
MOCK
  chmod +x "$src/hermes-fly"
  echo '// compiled cli' > "$src/dist/cli.js"
  echo '{"type":"module"}' > "$src/package.json"
  echo '{"lockfileVersion":3}' > "$src/package-lock.json"
  echo 'tpl' > "$src/templates/Dockerfile.template"
  echo '{}' > "$src/data/reasoning-snapshot.json"

  write_mock_npm "$mock_dir"
  write_mock_release_tar "$mock_dir"

  run bash -c '
    export PATH="'"$mock_dir"':${PATH}"
    export HERMES_FLY_PACKAGE_SOURCE_DIR="'"$src"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_TAR_ARGS_FILE="'"$tar_args_file"'"
    bash "'"${PROJECT_ROOT}"'/scripts/package-release-asset.sh" v0.1.26 "'"$out"'"
  '
  assert_success
  assert_output --partial "${out}/hermes-fly-v0.1.26.tar.gz"
  assert [ -f "${out}/hermes-fly-v0.1.26.tar.gz" ]

  run cat "$npm_args_file"
  assert_success
  assert_output --partial "ci --omit=dev"

  run cat "$tar_args_file"
  assert_success
  assert_output --partial "COPYFILE_DISABLE=1"
  assert_output --partial "COPY_EXTENDED_ATTRIBUTES_DISABLE=1"
}

# --- release resolution ---

@test "resolve_install_channel defaults to stable" {
  run bash -c '
    unset HERMES_FLY_CHANNEL
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel
  '
  assert_success
  assert_output "stable"
}

@test "resolve_install_channel accepts preview and edge" {
  run bash -c '
    export HERMES_FLY_CHANNEL="preview"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel
  '
  assert_success
  assert_output "preview"

  run bash -c '
    export HERMES_FLY_CHANNEL="edge"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel
  '
  assert_success
  assert_output "edge"
}

@test "resolve_install_channel unknown value falls back to stable with warning" {
  run bash -c '
    export HERMES_FLY_CHANNEL="nightly"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel 2>&1
  '
  assert_success
  assert_output --partial "stable"
  assert_output --partial "Warning"
}

@test "resolve_install_ref uses latest GitHub release by default" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{"tag_name":"v0.1.12"}\n'
MOCK
  chmod +x "$mock_dir/curl"

  run bash -c '
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_ref
  '
  assert_success
  assert_output "v0.1.12"
}

@test "resolve_install_ref returns main for edge channel by default" {
  run bash -c '
    unset HERMES_FLY_VERSION
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_ref edge
  '
  assert_success
  assert_output "main"
}

@test "resolve_install_ref normalizes HERMES_FLY_VERSION override without v prefix" {
  run bash -c '
    export HERMES_FLY_VERSION="0.1.12"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_ref
  '
  assert_success
  assert_output "v0.1.12"
}

@test "resolve_install_ref explicit HERMES_FLY_VERSION override wins over edge channel" {
  run bash -c '
    export HERMES_FLY_VERSION="0.9.1"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_ref edge
  '
  assert_success
  assert_output "v0.9.1"
}

# --- main() install flow ---

@test "install main prefers packaged release asset when available" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args"
  local git_marker="${TEST_TEMP_DIR}/git_called"
  local asset_root="${TEST_TEMP_DIR}/asset_root"
  local asset_file="${TEST_TEMP_DIR}/hermes-fly-v0.1.12.tar.gz"

  mkdir -p "$asset_root/dist" "$asset_root/node_modules/commander" "$asset_root/templates" "$asset_root/data"
  cat > "$asset_root/hermes-fly" <<'MOCK'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "${SCRIPT_DIR}/dist/cli.js" "$@"
MOCK
  chmod +x "$asset_root/hermes-fly"
  echo '// packaged cli' > "$asset_root/dist/cli.js"
  echo '{"name":"commander"}' > "$asset_root/node_modules/commander/package.json"
  echo '{"type":"module"}' > "$asset_root/package.json"
  echo '{"lockfileVersion":3}' > "$asset_root/package-lock.json"
  echo 'tpl' > "$asset_root/templates/Dockerfile.template"
  echo '{}' > "$asset_root/data/reasoning-snapshot.json"
  tar -czf "$asset_file" -C "$asset_root" .

  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
out=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
if [[ "$url" == *"/releases/latest" ]]; then
  printf '{"tag_name":"v0.1.12"}\n'
  exit 0
fi
if [[ "$url" == *"/releases/tags/v0.1.12" ]]; then
  printf '{"browser_download_url":"https://example.invalid/hermes-fly-v0.1.12.tar.gz"}\n'
  exit 0
fi
if [[ "$url" == "https://example.invalid/hermes-fly-v0.1.12.tar.gz" ]]; then
  cat "${MOCK_RELEASE_ASSET_FILE}" > "$out"
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/curl"

  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${MOCK_GIT_MARKER_FILE}"
exit 99
MOCK
  chmod +x "$mock_dir/git"
  write_mock_node "$mock_dir" "0.1.12"

  local install_home="${TEST_TEMP_DIR}/hermes_home"
  local install_bin="${TEST_TEMP_DIR}/install_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_GIT_MARKER_FILE="'"$git_marker"'"
    export MOCK_RELEASE_ASSET_FILE="'"$asset_file"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_success
  assert_output --partial "hermes-fly installed successfully"
  assert_output --partial "Downloading hermes-fly release asset"
  assert_output --partial "hermes-fly 0.1.12"
  assert [ -f "${install_home}/hermes-fly" ]
  assert [ -f "${install_home}/dist/cli.js" ]
  assert [ -f "${install_home}/node_modules/commander/package.json" ]
  assert [ -L "${install_bin}/hermes-fly" ]
  run test ! -f "$git_marker"
  assert_success
}

@test "install main falls back to source clone and build when packaged asset is unavailable" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local git_args_file="${TEST_TEMP_DIR}/git_args"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args"
  local node_args_file="${TEST_TEMP_DIR}/node_args"

  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
url="${@: -1}"
if [[ "$url" == *"/releases/latest" ]]; then
  printf '{"tag_name":"v0.1.12"}\n'
  exit 0
fi
if [[ "$url" == *"/releases/tags/v0.1.12" ]]; then
  printf '{"assets":[]}\n'
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/curl"

  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  printf '%s\n' "$*" > "${MOCK_GIT_ARGS_FILE}"
  dest="${@: -1}"
  mkdir -p "$dest"
  cat > "$dest/hermes-fly" <<'INNER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "${SCRIPT_DIR}/dist/cli.js" "$@"
INNER
  chmod +x "$dest/hermes-fly"
  mkdir -p "$dest/templates" "$dest/data"
  cat > "$dest/package.json" <<'INNER'
{"name":"hermes-fly","type":"module","dependencies":{"commander":"^12.1.0"},"scripts":{"build":"tsc -p tsconfig.json"}}
INNER
  cat > "$dest/package-lock.json" <<'INNER'
{"name":"hermes-fly","lockfileVersion":3}
INNER
  echo 'tpl' > "$dest/templates/Dockerfile.template"
  echo '{}' > "$dest/data/reasoning-snapshot.json"
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/git"
  write_mock_npm "$mock_dir"
  write_mock_node "$mock_dir" "0.1.12"

  local install_home="${TEST_TEMP_DIR}/hermes_home"
  local install_bin="${TEST_TEMP_DIR}/install_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_GIT_ARGS_FILE="'"$git_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_success
  assert_output --partial "Preparing hermes-fly runtime dependencies"
  assert [ -f "${install_home}/dist/cli.js" ]
  assert [ -f "${install_home}/node_modules/commander/package.json" ]
  run cat "$git_args_file"
  assert_success
  assert_output --partial "--branch v0.1.12"
  run cat "$npm_args_file"
  assert_success
  assert_output --partial "ci"
  assert_output --partial "run build"
  assert_output --partial "prune --omit=dev"
}

@test "install main uses main branch and builds runtime when HERMES_FLY_CHANNEL=edge" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local git_args_file="${TEST_TEMP_DIR}/git_args_edge"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_edge"
  local node_args_file="${TEST_TEMP_DIR}/node_args_edge"

  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  printf '%s\n' "$*" > "${MOCK_GIT_ARGS_FILE}"
  dest="${@: -1}"
  mkdir -p "$dest"
  cat > "$dest/hermes-fly" <<'INNER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "${SCRIPT_DIR}/dist/cli.js" "$@"
INNER
  chmod +x "$dest/hermes-fly"
  mkdir -p "$dest/templates" "$dest/data"
  cat > "$dest/package.json" <<'INNER'
{"name":"hermes-fly","type":"module","dependencies":{"commander":"^12.1.0"},"scripts":{"build":"tsc -p tsconfig.json"}}
INNER
  cat > "$dest/package-lock.json" <<'INNER'
{"name":"hermes-fly","lockfileVersion":3}
INNER
  echo 'tpl' > "$dest/templates/Dockerfile.template"
  echo '{}' > "$dest/data/reasoning-snapshot.json"
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/git"
  write_mock_npm "$mock_dir"
  write_mock_node "$mock_dir" "0.0.0-dev"

  local install_home="${TEST_TEMP_DIR}/hermes_home_edge"
  local install_bin="${TEST_TEMP_DIR}/install_bin_edge"
  run bash -c '
    export HERMES_FLY_CHANNEL="edge"
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_GIT_ARGS_FILE="'"$git_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_success
  assert_output --partial "Channel: edge"
  run cat "$git_args_file"
  assert_success
  assert_output --partial "--branch main"
}

@test "install main fails when installed version does not match requested release" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local git_args_file="${TEST_TEMP_DIR}/git_args_mismatch"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_mismatch"
  local node_args_file="${TEST_TEMP_DIR}/node_args_mismatch"

  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
url="${@: -1}"
if [[ "$url" == *"/releases/latest" ]]; then
  printf '{"tag_name":"v0.1.12"}\n'
  exit 0
fi
if [[ "$url" == *"/releases/tags/v0.1.12" ]]; then
  printf '{"assets":[]}\n'
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/curl"

  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  printf '%s\n' "$*" > "${MOCK_GIT_ARGS_FILE}"
  dest="${@: -1}"
  mkdir -p "$dest"
  cat > "$dest/hermes-fly" <<'INNER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "${SCRIPT_DIR}/dist/cli.js" "$@"
INNER
  chmod +x "$dest/hermes-fly"
  mkdir -p "$dest/templates" "$dest/data"
  cat > "$dest/package.json" <<'INNER'
{"name":"hermes-fly","type":"module","dependencies":{"commander":"^12.1.0"},"scripts":{"build":"tsc -p tsconfig.json"}}
INNER
  cat > "$dest/package-lock.json" <<'INNER'
{"name":"hermes-fly","lockfileVersion":3}
INNER
  echo 'tpl' > "$dest/templates/Dockerfile.template"
  echo '{}' > "$dest/data/reasoning-snapshot.json"
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/git"
  write_mock_npm "$mock_dir"
  write_mock_node "$mock_dir" "0.1.11"

  local install_home="${TEST_TEMP_DIR}/hermes_home_mismatch"
  local install_bin="${TEST_TEMP_DIR}/install_bin_mismatch"
  run bash -c '
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_GIT_ARGS_FILE="'"$git_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_failure
  assert_output --partial "Installed version mismatch"
}
