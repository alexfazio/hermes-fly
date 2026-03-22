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
#!/bin/sh
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
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
if [[ -n "${MOCK_NPM_ENV_FILE:-}" ]]; then
  {
    printf 'BASH_ENV=%s\n' "${BASH_ENV:-}"
    printf 'ENV=%s\n' "${ENV:-}"
    printf 'LANG=%s\n' "${LANG:-}"
    printf 'LC_ALL=%s\n' "${LC_ALL:-}"
  } >> "${MOCK_NPM_ENV_FILE}"
fi
if [[ "${1:-}" == "ci" ]]; then
  mkdir -p "$PWD/node_modules/commander"
  echo '{"name":"commander"}' > "$PWD/node_modules/commander/package.json"
  exit 0
fi
if [[ "${1:-}" == "run" && "${2:-}" == "build" ]]; then
  mkdir -p "$PWD/dist"
  echo 'console.log("hermes-fly test build")' > "$PWD/dist/cli.js"
  echo 'console.log("installer test build")' > "$PWD/dist/install-cli.js"
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

write_noisy_mock_npm() {
  local mock_dir="$1"

  cat > "$mock_dir/npm" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_NPM_ARGS_FILE}"
if [[ "${1:-}" == "ci" ]]; then
  echo "added 110 packages in 902ms"
  mkdir -p "$PWD/node_modules/commander"
  echo '{"name":"commander"}' > "$PWD/node_modules/commander/package.json"
  exit 0
fi
if [[ "${1:-}" == "run" && "${2:-}" == "build" ]]; then
  echo ""
  echo "> build"
  echo "> tsc -p tsconfig.json"
  echo ""
  mkdir -p "$PWD/dist"
  echo 'console.log("hermes-fly test build")' > "$PWD/dist/cli.js"
  echo 'console.log("installer test build")' > "$PWD/dist/install-cli.js"
  exit 0
fi
if [[ "${1:-}" == "prune" && "${2:-}" == "--omit=dev" ]]; then
  echo ""
  echo "up to date in 319ms"
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
if [[ "\${1:-}" == *"/dist/install-cli.js" && "\${2:-}" == "install" ]]; then
  if [[ -n "\${MOCK_INSTALLER_FAILURE_MESSAGE:-}" ]]; then
    echo "\${MOCK_INSTALLER_FAILURE_MESSAGE}" >&2
    exit 1
  fi
  if [[ "\${HERMES_FLY_INSTALLER_SKIP_BANNER:-0}" != "1" ]]; then
    cat <<'OUT'
  🪽 Hermes Fly Installer
  I can't fix Fly.io billing, but I can fix the part between curl and deploy.

OUT
  fi
  cat <<'OUT'
✓ Detected: darwin/arm64

Install plan
[1/3] Preparing environment
[2/3] Installing Hermes Fly
[3/3] Finalizing setup
🪽 Hermes Fly installed successfully (hermes-fly ${version})!
OUT
  exit 0
fi
if [[ "\$*" == *"--version"* ]]; then
  echo "hermes-fly ${version}"
  exit 0
fi
echo "unexpected node invocation: \$*" >&2
exit 1
MOCK
  chmod +x "$mock_dir/node"
}

write_mock_legacy_banner_node() {
  local mock_dir="$1"
  local version="$2"

  cat > "$mock_dir/node" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${MOCK_NODE_ARGS_FILE}"
if [[ "\${1:-}" == *"/dist/install-cli.js" && "\${2:-}" == "install" ]]; then
  if [[ -n "\${MOCK_INSTALLER_FAILURE_MESSAGE:-}" ]]; then
    echo "\${MOCK_INSTALLER_FAILURE_MESSAGE}" >&2
    exit 1
  fi
  cat <<'OUT'
  🪽 Hermes Fly Installer
  I can't fix Fly.io billing, but I can fix the part between curl and deploy.

OUT
  cat <<'OUT'
✓ Detected: darwin/arm64

Install plan
[1/3] Preparing environment
[2/3] Installing Hermes Fly
[3/3] Finalizing setup
🪽 Hermes Fly installed successfully (hermes-fly ${version})!
OUT
  exit 0
fi
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
  printf '%s\n' '--format {ustar|pax|cpio|shar}'
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

@test "resolve_install_layout uses macOS user-local defaults when no overrides exist" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_default_layout"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_default_layout_legacy"
  local expected_home
  mkdir -p "$fake_home"
  expected_home="$fake_home"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_home}/Library/Application Support/hermes-fly"
  assert_output --partial "INSTALL_DIR=${expected_home}/.local/bin"
}

@test "resolve_install_layout ignores inherited HERMES_HOME when HERMES_FLY_HOME is unset" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_inherited_runtime_home"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_inherited_runtime_home_legacy"
  local expected_home
  mkdir -p "$fake_home"
  expected_home="$fake_home"

  run bash -c '
    export HOME="'"$fake_home"'"
    export HERMES_HOME="$HOME/.hermes"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_home}/Library/Application Support/hermes-fly"
  assert_output --partial "INSTALL_DIR=${expected_home}/.local/bin"
}

@test "resolve_install_layout preserves an existing installation on PATH" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_existing_layout"
  local install_home="${TEST_TEMP_DIR}/existing_install/home"
  local install_bin="${TEST_TEMP_DIR}/existing_install/bin"
  local expected_install_home
  mkdir -p "$fake_home" "$install_home/dist" "$install_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("existing install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_install_home}"
  assert_output --partial "INSTALL_DIR=${install_bin}"
}

@test "resolve_install_layout preserves the historical user-local no-sudo install without a marker" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_user_local_legacy"
  local install_home="${fake_home}/.local/lib/hermes-fly"
  local install_bin="${fake_home}/.local/bin"
  local expected_install_home
  mkdir -p "$install_home/dist" "$install_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("existing install")' > "$install_home/dist/cli.js"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_install_home}"
  assert_output --partial "INSTALL_DIR=${install_bin}"
}

@test "resolve_install_layout falls back to known legacy locations when PATH omits hermes-fly" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_known_location"
  local legacy_root="${TEST_TEMP_DIR}/known_legacy_root"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"
  local expected_install_home expected_install_bin
  mkdir -p "$fake_home" "$legacy_home/dist" "$legacy_bin"
  cat > "$legacy_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$legacy_home/hermes-fly"
  echo 'console.log("existing install")' > "$legacy_home/dist/cli.js"
  ln -sf "$legacy_home/hermes-fly" "$legacy_bin/hermes-fly"
  expected_install_home="$(cd "$legacy_home" && pwd -P)"
  expected_install_bin="$(cd "$legacy_bin" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_install_home}"
  assert_output --partial "INSTALL_DIR=${expected_install_bin}"
}

@test "resolve_install_layout preserves a known managed install when the launcher is missing" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_missing_known_launcher"
  local install_home="${fake_home}/.local/lib/hermes-fly"
  local install_bin="${fake_home}/.local/bin"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_known_launcher_legacy"
  local expected_install_home expected_install_bin
  mkdir -p "$install_home/dist" "$install_bin"
  echo 'console.log("existing install")' > "$install_home/dist/cli.js"
  expected_install_home="$install_home"
  expected_install_bin="$install_bin"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_install_home}"
  assert_output --partial "INSTALL_DIR=${expected_install_bin}"
}

@test "resolve_install_layout uses the legacy system defaults for fresh root installs" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_root_default_layout"
  local legacy_root="${TEST_TEMP_DIR}/root_default_layout_legacy"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"
  mkdir -p "$fake_home"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 0; }
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${legacy_home}"
  assert_output --partial "INSTALL_DIR=${legacy_bin}"
}

@test "resolve_install_layout ignores a relative XDG_DATA_HOME on Linux" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_relative_xdg"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_relative_xdg_legacy"
  local expected_home
  mkdir -p "$fake_home"
  expected_home="$fake_home"

  run bash -c '
    export HOME="'"$fake_home"'"
    export XDG_DATA_HOME="share"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_home}/.local/share/hermes-fly"
  assert_output --partial "INSTALL_DIR=${expected_home}/.local/bin"
}

@test "resolve_install_layout preserves the logical HOME path for fresh user-local defaults" {
  local physical_home="${TEST_TEMP_DIR}/physical_home_logical_defaults"
  local logical_home="${TEST_TEMP_DIR}/logical_home_logical_defaults"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_logical_home_legacy"
  mkdir -p "$physical_home/.local/bin"
  rm -rf "$logical_home"
  ln -s "$physical_home" "$logical_home"

  run bash -c '
    export HOME="'"$logical_home"'"
    export PATH="'"$logical_home"'/.local/bin:/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_install_layout linux
    print_path_guidance_if_needed "$INSTALL_DIR"
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${logical_home}/.local/share/hermes-fly"
  assert_output --partial "INSTALL_DIR=${logical_home}/.local/bin"
  [[ "$output" != *"PATH missing hermes-fly bin dir"* ]]
}

@test "resolve_install_layout does not reuse a user-local existing layout during a root install" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_root_user_local_existing"
  local existing_home="${fake_home}/.local/lib/hermes-fly"
  local existing_bin="${fake_home}/.local/bin"
  local legacy_root="${TEST_TEMP_DIR}/root_user_local_existing_legacy"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"
  mkdir -p "$fake_home" "$existing_home/dist" "$existing_bin"
  cat > "$existing_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$existing_home/hermes-fly"
  echo 'console.log("existing install")' > "$existing_home/dist/cli.js"
  echo '1' > "$existing_home/.hermes-fly-install-managed"
  ln -sf "$existing_home/hermes-fly" "$existing_bin/hermes-fly"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$existing_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 0; }
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${legacy_home}"
  assert_output --partial "INSTALL_DIR=${legacy_bin}"
}

@test "resolve_install_layout still reuses a staged .local prefix during a root install" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_root_staged_local_existing"
  local existing_home="${TEST_TEMP_DIR}/root_staged_local_existing/stage/.local/share/hermes-fly"
  local existing_bin="${TEST_TEMP_DIR}/root_staged_local_existing/stage/.local/bin"
  local expected_existing_home
  mkdir -p "$fake_home" "$existing_home/dist" "$existing_bin"
  cat > "$existing_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$existing_home/hermes-fly"
  echo 'console.log("existing install")' > "$existing_home/dist/cli.js"
  echo '1' > "$existing_home/.hermes-fly-install-managed"
  ln -sf "$existing_home/hermes-fly" "$existing_bin/hermes-fly"
  expected_existing_home="$(cd "$existing_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$existing_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 0; }
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_existing_home}"
  assert_output --partial "INSTALL_DIR=${existing_bin}"
}

@test "resolve_install_layout does not reuse the active XDG_DATA_HOME layout during a root install" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_root_xdg_override_existing"
  local xdg_data_home="${TEST_TEMP_DIR}/root_xdg_override_existing/data-home"
  local existing_home="${xdg_data_home}/hermes-fly"
  local existing_bin="${fake_home}/.local/bin"
  local legacy_root="${TEST_TEMP_DIR}/root_xdg_override_existing_legacy"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"
  mkdir -p "$fake_home" "$existing_home/dist" "$existing_bin"
  cat > "$existing_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$existing_home/hermes-fly"
  echo 'console.log("existing install")' > "$existing_home/dist/cli.js"
  echo '1' > "$existing_home/.hermes-fly-install-managed"
  ln -sf "$existing_home/hermes-fly" "$existing_bin/hermes-fly"

  run bash -c '
    export HOME="'"$fake_home"'"
    export XDG_DATA_HOME="'"$xdg_data_home"'"
    export PATH="'"$existing_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 0; }
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${legacy_home}"
  assert_output --partial "INSTALL_DIR=${legacy_bin}"
}

@test "resolve_install_layout reuses a marked custom existing layout during a root install" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_root_custom_existing"
  local existing_home="${TEST_TEMP_DIR}/root_custom_existing/home"
  local existing_bin="${TEST_TEMP_DIR}/root_custom_existing/bin"
  local expected_existing_home
  mkdir -p "$fake_home" "$existing_home/dist" "$existing_bin"
  cat > "$existing_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$existing_home/hermes-fly"
  echo 'console.log("existing install")' > "$existing_home/dist/cli.js"
  echo '1' > "$existing_home/.hermes-fly-install-managed"
  ln -sf "$existing_home/hermes-fly" "$existing_bin/hermes-fly"
  expected_existing_home="$(cd "$existing_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$existing_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 0; }
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_existing_home}"
  assert_output --partial "INSTALL_DIR=${existing_bin}"
}

@test "resolve_install_layout keeps scanning after a user-local PATH hit during a root install" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_root_mixed_existing"
  local user_home="${fake_home}/.local/lib/hermes-fly"
  local user_bin="${fake_home}/.local/bin"
  local custom_home="${TEST_TEMP_DIR}/root_mixed_existing/custom-home"
  local custom_bin="${TEST_TEMP_DIR}/root_mixed_existing/custom-bin"
  local expected_custom_home
  mkdir -p "$fake_home" "$user_home/dist" "$user_bin" "$custom_home/dist" "$custom_bin"
  cat > "$user_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$user_home/hermes-fly"
  echo 'console.log("user install")' > "$user_home/dist/cli.js"
  echo '1' > "$user_home/.hermes-fly-install-managed"
  ln -sf "$user_home/hermes-fly" "$user_bin/hermes-fly"
  cat > "$custom_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$custom_home/hermes-fly"
  echo 'console.log("custom install")' > "$custom_home/dist/cli.js"
  echo '1' > "$custom_home/.hermes-fly-install-managed"
  ln -sf "$custom_home/hermes-fly" "$custom_bin/hermes-fly"
  expected_custom_home="$(cd "$custom_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$user_bin"':'"$custom_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 0; }
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_custom_home}"
  assert_output --partial "INSTALL_DIR=${custom_bin}"
}

@test "resolve_install_layout preserves a legacy lib-based system install without dist/cli.js" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_legacy_lib_system"
  local legacy_root="${TEST_TEMP_DIR}/legacy_lib_system_root"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"
  local expected_install_home
  mkdir -p "$fake_home" "$legacy_home/lib" "$legacy_bin"
  cat > "$legacy_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$legacy_home/hermes-fly"
  cat > "$legacy_home/lib/ui.sh" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  ln -sf "$legacy_home/hermes-fly" "$legacy_bin/hermes-fly"
  expected_install_home="$(cd "$legacy_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$legacy_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_install_home}"
  assert_output --partial "INSTALL_DIR=${legacy_bin}"
}

@test "resolve_install_layout falls back to the legacy system defaults when HOME cannot be determined" {
  local legacy_root="${TEST_TEMP_DIR}/legacy_default_no_home"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"

  run bash -c '
    unset HOME
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_home_dir_hint() { return 1; }
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${legacy_home}"
  assert_output --partial "INSTALL_DIR=${legacy_bin}"
}

@test "resolve_install_layout preserves a legacy system install when HOME cannot be determined" {
  local legacy_root="${TEST_TEMP_DIR}/legacy_preserve_no_home"
  local legacy_home="${legacy_root}/lib/hermes-fly"
  local legacy_bin="${legacy_root}/bin"
  local expected_install_home expected_install_bin
  mkdir -p "$legacy_home/dist" "$legacy_bin"
  cat > "$legacy_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$legacy_home/hermes-fly"
  echo 'console.log("existing install")' > "$legacy_home/dist/cli.js"
  ln -sf "$legacy_home/hermes-fly" "$legacy_bin/hermes-fly"
  expected_install_home="$(cd "$legacy_home" && pwd -P)"
  expected_install_bin="$(cd "$legacy_bin" && pwd -P)"

  run bash -c '
    unset HOME
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_home_dir_hint() { return 1; }
    LEGACY_INSTALL_HOME="'"$legacy_home"'"
    LEGACY_BIN_DIR="'"$legacy_bin"'"
    resolve_install_layout linux
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${expected_install_home}"
  assert_output --partial "INSTALL_DIR=${expected_install_bin}"
}

@test "resolve_existing_install_layout ignores repo-like PATH targets without an installer marker" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_repo_layout"
  local repo_home="${TEST_TEMP_DIR}/repo_like_install/home"
  local repo_bin="${TEST_TEMP_DIR}/repo_like_install/bin"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_repo_layout_legacy"
  mkdir -p "$fake_home" "$repo_home/dist" "$repo_home/src" "$repo_bin"
  cat > "$repo_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$repo_home/hermes-fly"
  echo 'console.log("repo build")' > "$repo_home/dist/cli.js"
  echo '{}' > "$repo_home/tsconfig.json"
  ln -sf "$repo_home/hermes-fly" "$repo_bin/hermes-fly"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$repo_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_failure
}

@test "resolve_existing_install_layout falls back to a known managed install after an unmanaged PATH hit" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_shadowed_install"
  local managed_home="${fake_home}/.local/lib/hermes-fly"
  local managed_bin="${fake_home}/.local/bin"
  local repo_home="${TEST_TEMP_DIR}/shadowing_repo_install/home"
  local repo_bin="${TEST_TEMP_DIR}/shadowing_repo_install/bin"
  local expected_install_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_shadowed_install_legacy"
  mkdir -p "$managed_home/dist" "$managed_bin" "$repo_home/dist" "$repo_home/src" "$repo_bin"
  cat > "$managed_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$managed_home/hermes-fly"
  echo 'console.log("managed install")' > "$managed_home/dist/cli.js"
  ln -sf "$managed_home/hermes-fly" "$managed_bin/hermes-fly"
  cat > "$repo_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$repo_home/hermes-fly"
  echo 'console.log("repo build")' > "$repo_home/dist/cli.js"
  echo '{}' > "$repo_home/tsconfig.json"
  ln -sf "$repo_home/hermes-fly" "$repo_bin/hermes-fly"
  expected_install_home="$(cd "$managed_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$repo_bin"':'"$managed_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${managed_bin}"
}

@test "resolve_existing_install_layout falls back to the XDG install home when PATH omits hermes-fly" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_xdg_known_location"
  local xdg_data_home="${fake_home}/.xdg/data"
  local install_home="${xdg_data_home}/hermes-fly"
  local install_bin="${fake_home}/.local/bin"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_xdg_known_location_legacy"
  local expected_install_home expected_install_bin
  mkdir -p "$install_home/dist" "$install_bin"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  expected_install_home="$install_home"
  expected_install_bin="$install_bin"

  run bash -c '
    export HOME="'"$fake_home"'"
    export XDG_DATA_HOME="'"$xdg_data_home"'"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${expected_install_bin}"
}

@test "resolve_existing_install_layout falls back to the known user bin launcher when PATH omits hermes-fly" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_known_bin_launcher"
  local install_home="${TEST_TEMP_DIR}/known_bin_launcher_install/home"
  local install_bin="${fake_home}/.local/bin"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_known_bin_launcher_legacy"
  local expected_install_home expected_install_bin
  mkdir -p "$install_home/dist" "$install_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"
  expected_install_bin="$install_bin"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${expected_install_bin}"
}

@test "resolve_existing_install_layout preserves a known managed install when its launcher is replaced" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_replaced_known_launcher"
  local install_home="${fake_home}/.local/lib/hermes-fly"
  local install_bin="${fake_home}/.local/bin"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_replaced_known_launcher_legacy"
  local expected_install_home expected_install_bin
  mkdir -p "$install_home/dist" "$install_bin"
  cat > "$install_bin/hermes-fly" <<'MOCK'
#!/bin/sh
echo "shadowed launcher"
MOCK
  chmod +x "$install_bin/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  expected_install_home="$install_home"
  expected_install_bin="$install_bin"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${expected_install_bin}"
}

@test "resolve_existing_install_layout preserves a marked custom install later on PATH after an unmanaged hit" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_custom_path_install"
  local install_home="${TEST_TEMP_DIR}/custom_install_home"
  local install_bin="${TEST_TEMP_DIR}/custom_install_bin"
  local repo_home="${TEST_TEMP_DIR}/shadowing_custom_repo_install/home"
  local repo_bin="${TEST_TEMP_DIR}/shadowing_custom_repo_install/bin"
  local expected_install_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_custom_path_legacy"
  mkdir -p "$fake_home" "$install_home/dist" "$install_bin" "$repo_home/dist" "$repo_home/src" "$repo_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  cat > "$repo_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$repo_home/hermes-fly"
  echo 'console.log("repo build")' > "$repo_home/dist/cli.js"
  echo '{}' > "$repo_home/tsconfig.json"
  ln -sf "$repo_home/hermes-fly" "$repo_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$repo_bin"':'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${install_bin}"
}

@test "resolve_existing_install_layout preserves pre-marker custom installs created by older installers" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_pre_marker_custom"
  local install_home="${TEST_TEMP_DIR}/pre_marker_custom_home"
  local install_bin="${TEST_TEMP_DIR}/pre_marker_custom_bin"
  local expected_install_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_pre_marker_custom_legacy"
  mkdir -p "$fake_home" "$install_home/dist" "$install_home/node_modules/commander" "$install_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '{"name":"hermes-fly"}' > "$install_home/package.json"
  echo '{"lockfileVersion":3}' > "$install_home/package-lock.json"
  echo '{"name":"commander"}' > "$install_home/node_modules/commander/package.json"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${install_bin}"
}

@test "resolve_existing_install_layout ignores extra PATH shims when resolving a marked install bin dir" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_path_shim"
  local install_home="${TEST_TEMP_DIR}/shimmed_install_home"
  local install_bin="${TEST_TEMP_DIR}/shimmed_install_bin"
  local shim_bin="${TEST_TEMP_DIR}/shimmed_path_bin"
  local expected_install_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_shim_path_legacy"
  mkdir -p "$fake_home" "$install_home/dist" "$install_bin" "$shim_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  ln -sf "$install_bin/hermes-fly" "$shim_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$shim_bin"':'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${install_bin}"
}

@test "resolve_existing_install_layout preserves a symlinked PATH directory for the managed bin dir" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_symlinked_path_dir"
  local install_home="${TEST_TEMP_DIR}/symlinked_path_install_home"
  local install_bin="${TEST_TEMP_DIR}/symlinked_path_install_bin"
  local path_alias="${TEST_TEMP_DIR}/symlinked_path_alias"
  local expected_install_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_symlinked_path_legacy"
  mkdir -p "$fake_home" "$install_home/dist" "$install_home/node_modules/commander" "$install_bin"
  ln -sf "$install_bin" "$path_alias"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '{"name":"hermes-fly"}' > "$install_home/package.json"
  echo '{"lockfileVersion":3}' > "$install_home/package-lock.json"
  echo '{"name":"commander"}' > "$install_home/node_modules/commander/package.json"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$path_alias"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${path_alias}"
}

@test "resolve_existing_install_layout ignores repo checkouts in known managed legacy locations" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_repo_legacy_layout"
  local install_home="${fake_home}/.local/lib/hermes-fly"
  local install_bin="${fake_home}/.local/bin"
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_repo_legacy_layout"
  mkdir -p "$install_home/dist" "$install_home/src" "$install_bin"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("repo build")' > "$install_home/dist/cli.js"
  echo '{}' > "$install_home/tsconfig.json"
  echo '{"name":"hermes-fly"}' > "$install_home/package.json"
  echo '{"lockfileVersion":3}' > "$install_home/package-lock.json"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_failure
}

@test "resolve_existing_install_layout skips cyclic launcher symlinks and continues scanning" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_cyclic_launcher"
  local cycle_a_bin="${TEST_TEMP_DIR}/cycle_a_bin"
  local cycle_b_bin="${TEST_TEMP_DIR}/cycle_b_bin"
  local install_home="${TEST_TEMP_DIR}/cyclic_install_home"
  local install_bin="${TEST_TEMP_DIR}/cyclic_install_bin"
  local expected_install_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_cyclic_legacy"
  mkdir -p "$fake_home" "$cycle_a_bin" "$cycle_b_bin" "$install_home/dist" "$install_bin"
  ln -sf "$cycle_b_bin/hermes-fly" "$cycle_a_bin/hermes-fly"
  ln -sf "$cycle_a_bin/hermes-fly" "$cycle_b_bin/hermes-fly"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("managed install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"
  expected_install_home="$(cd "$install_home" && pwd -P)"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$cycle_a_bin"':'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    resolve_existing_install_layout
  '

  assert_success
  assert_output "${expected_install_home}|${install_bin}"
}

@test "resolve_install_layout ignores existing install paths when HERMES_FLY_HOME is overridden" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_partial_override"
  local install_home="${TEST_TEMP_DIR}/existing_override_install/home"
  local install_bin="${TEST_TEMP_DIR}/existing_override_install/bin"
  local expected_home
  mkdir -p "$fake_home" "$install_home/dist" "$install_bin"
  expected_home="$fake_home"
  cat > "$install_home/hermes-fly" <<'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$install_home/hermes-fly"
  echo 'console.log("existing install")' > "$install_home/dist/cli.js"
  echo '1' > "$install_home/.hermes-fly-install-managed"
  ln -sf "$install_home/hermes-fly" "$install_bin/hermes-fly"

  run bash -c '
    export HOME="'"$fake_home"'"
    export HERMES_FLY_HOME="'"${TEST_TEMP_DIR}"'/custom_install_home"
    export PATH="'"$install_bin"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_layout darwin
    printf "HERMES_HOME=%s\n" "$HERMES_HOME"
    printf "INSTALL_DIR=%s\n" "$INSTALL_DIR"
  '

  assert_success
  assert_output --partial "HERMES_HOME=${TEST_TEMP_DIR}/custom_install_home"
  assert_output --partial "INSTALL_DIR=${expected_home}/.local/bin"
}

@test "installer_no_color_requested treats empty NO_COLOR as an opt-out" {
  run bash -c '
    export NO_COLOR=""
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    installer_no_color_requested
  '
  assert_success
}

@test "_needs_sudo allows nested user-local install paths when the writable ancestor exists" {
  local fake_home="${TEST_TEMP_DIR}/fake_home_nested_permissions"
  mkdir -p "$fake_home"

  run bash -c '
    export HOME="'"$fake_home"'"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    _needs_sudo "$HOME/Library/Application Support/hermes-fly"
  '

  assert_failure
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
  local npm_env_file="${TEST_TEMP_DIR}/npm_env"
  local bash_env_file="${TEST_TEMP_DIR}/noop_bash_env"

  mkdir -p "$mock_dir"
  write_source_checkout "$src"
  write_mock_npm "$mock_dir"
  : > "$bash_env_file"

  run bash -c '
    export PATH="'"$mock_dir"':${PATH}"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_NPM_ENV_FILE="'"$npm_env_file"'"
    export BASH_ENV="'"$bash_env_file"'"
    export ENV="'"$bash_env_file"'"
    export LANG="broken-locale"
    export LC_ALL="broken-locale"
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

  run cat "$npm_env_file"
  assert_success
  assert_output --partial "BASH_ENV="
  assert_output --partial "ENV="
  assert_output --partial "LANG=C"
  assert_output --partial "LC_ALL=C"
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

@test "installed launcher ignores BASH_ENV and executes via a POSIX shell" {
  local src="${TEST_TEMP_DIR}/src"
  local dest="${TEST_TEMP_DIR}/hermes-home"
  local bin="${TEST_TEMP_DIR}/bin"
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  local node_args_file="${TEST_TEMP_DIR}/node_args"
  local bash_env_file="${TEST_TEMP_DIR}/bash_env"

  mkdir -p "$src/dist" "$src/templates" "$src/node_modules/commander" "$mock_dir"
  cp "${PROJECT_ROOT}/hermes-fly" "$src/hermes-fly"
  chmod +x "$src/hermes-fly"
  echo '// compiled cli' > "$src/dist/cli.js"
  echo '{"name":"commander"}' > "$src/node_modules/commander/package.json"
  echo '{"type":"module"}' > "$src/package.json"
  echo '{"lockfileVersion":3}' > "$src/package-lock.json"
  echo 'tpl' > "$src/templates/Dockerfile.template"

  write_mock_node "$mock_dir" "9.9.9"
  printf 'echo BASH_ENV_LOADED >&2\n' > "$bash_env_file"

  run bash -c '
    export PATH="'"$mock_dir"':${PATH}"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    install_files "'"$src"'" "'"$dest"'" "'"$bin"'"
    BASH_ENV="'"$bash_env_file"'" "'"$bin"'/hermes-fly" --version 2>&1
  '
  assert_success
  assert_output --partial "hermes-fly 9.9.9"
  refute_output --partial "BASH_ENV_LOADED"
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
  [[ "$output" == *"--format ustar"* ]] || [[ "$output" == *"ARGS="* ]]
}

# --- release resolution ---

@test "resolve_install_channel defaults to latest" {
  run bash -c '
    unset HERMES_FLY_CHANNEL
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel
  '
  assert_success
  assert_output "latest"
}

@test "resolve_install_channel accepts stable preview edge and latest" {
  run bash -c '
    export HERMES_FLY_CHANNEL="latest"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel
  '
  assert_success
  assert_output "latest"

  run bash -c '
    export HERMES_FLY_CHANNEL="stable"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel
  '
  assert_success
  assert_output "stable"

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

@test "resolve_install_channel unknown value falls back to latest with warning" {
  run bash -c '
    export HERMES_FLY_CHANNEL="nightly"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_channel 2>&1
  '
  assert_success
  assert_output --partial "latest"
  assert_output --partial "Warning"
}

@test "resolve_install_ref uses latest GitHub release for latest channel" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{"tag_name":"v0.1.12"}\n'
MOCK
  chmod +x "$mock_dir/curl"

  run bash -c '
    unset HERMES_FLY_VERSION
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_ref latest
  '
  assert_success
  assert_output "v0.1.12"
}

@test "resolve_install_ref uses latest GitHub release for stable channel" {
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
    resolve_install_ref stable
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

@test "main bootstraps the Commander installer CLI without leaking npm build chatter" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args"
  : > "$npm_args_file"
  write_mock_node "$mock_dir" "0.1.12"
  write_noisy_mock_npm "$mock_dir"

  run bash -c '
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_success
  assert_output --partial "🪽 Hermes Fly Installer"
  assert_output --partial "[1/3] Preparing environment"
  assert_output --partial "Hermes Fly installed successfully (hermes-fly 0.1.12)!"
  refute_output --partial "added 110 packages"
  refute_output --partial "> build"
  refute_output --partial "up to date in 319ms"
  [[ "$(printf '%s' "$output" | grep -o "🪽 Hermes Fly Installer" | wc -l | tr -d ' ')" == "1" ]]

  run cat "$node_args_file"
  assert_success
  assert_output --partial "dist/install-cli.js install"

  run cat "$npm_args_file"
  assert_success
  assert_output --partial "ci --no-audit --no-fund"
  assert_output --partial "run build"
  assert_output --partial "prune --omit=dev --no-audit --no-fund"
}

@test "bootstrap_installer_cli downloads the checked installer release when not running from a local checkout" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_bootstrap_ref"
  local script_dir="${TEST_TEMP_DIR}/standalone_script"
  local script_copy="${script_dir}/install.sh"
  local node_args_file="${TEST_TEMP_DIR}/node_args_bootstrap_ref"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_bootstrap_ref"
  local url_file="${TEST_TEMP_DIR}/bootstrap_urls"
  local archive_parent="${TEST_TEMP_DIR}/bootstrap_archive_parent"
  local archive_root="${archive_parent}/hermes-fly-bootstrap"
  local archive_file="${TEST_TEMP_DIR}/bootstrap_source.tar.gz"
  local fake_home="${TEST_TEMP_DIR}/fake_home_bootstrap_ref"
  local expected_home
  local isolated_legacy_root="${TEST_TEMP_DIR}/missing_bootstrap_ref_legacy"
  local bootstrap_ref

  mkdir -p "$mock_dir" "$script_dir" "$archive_root" "$fake_home"
  expected_home="$fake_home"
  cp "${PROJECT_ROOT}/scripts/install.sh" "$script_copy"
  chmod +x "$script_copy"
  write_source_checkout "$archive_root"
  bootstrap_ref="v$(sed -n 's/.*HERMES_FLY_TS_VERSION = \"\\([^\"]*\\)\".*/\\1/p' "${PROJECT_ROOT}/src/version.ts" | head -1)"
  tar -czf "$archive_file" -C "$archive_parent" "$(basename "$archive_root")"

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
printf '%s\n' "$url" >> "${MOCK_CURL_URL_FILE}"
if [[ "$url" == "https://codeload.github.com/alexfazio/hermes-fly/tar.gz/"* ]]; then
  cat "${MOCK_BOOTSTRAP_ARCHIVE_FILE}" > "$out"
  exit 0
fi
echo "unexpected curl url: $url" >&2
exit 1
MOCK
  chmod +x "$mock_dir/curl"
  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  run bash -c '
    export HOME="'"$fake_home"'"
    export PATH="'"$mock_dir"':/usr/bin:/bin"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_CURL_URL_FILE="'"$url_file"'"
    export MOCK_BOOTSTRAP_REF="'"$bootstrap_ref"'"
    export MOCK_BOOTSTRAP_ARCHIVE_FILE="'"$archive_file"'"
    source "'"$script_copy"'"
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    bootstrap_installer_cli
  '
  assert_success

  run cat "$url_file"
  assert_success
  assert_output --partial "https://codeload.github.com/alexfazio/hermes-fly/tar.gz/${bootstrap_ref}"
  refute_output --partial "/main"

  run cat "$node_args_file"
  assert_success
  assert_output --partial "dist/install-cli.js install --install-home ${expected_home}/Library/Application Support/hermes-fly --bin-dir ${expected_home}/.local/bin"
}

@test "bootstrap_installer_cli forwards HERMES_FLY_HOME into Commander install arguments" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_bootstrap_home"
  local script_dir="${TEST_TEMP_DIR}/standalone_script_home"
  local script_copy="${script_dir}/install.sh"
  local node_args_file="${TEST_TEMP_DIR}/node_args_bootstrap_home"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_bootstrap_home"
  local url_file="${TEST_TEMP_DIR}/bootstrap_urls_home"
  local archive_parent="${TEST_TEMP_DIR}/bootstrap_archive_parent_home"
  local archive_root="${archive_parent}/hermes-fly-bootstrap"
  local archive_file="${TEST_TEMP_DIR}/bootstrap_source_home.tar.gz"
  local fake_home="${TEST_TEMP_DIR}/fake_home_bootstrap_home"
  local expected_home
  local bootstrap_ref

  mkdir -p "$mock_dir" "$script_dir" "$archive_root" "$fake_home"
  expected_home="$fake_home"
  cp "${PROJECT_ROOT}/scripts/install.sh" "$script_copy"
  chmod +x "$script_copy"
  write_source_checkout "$archive_root"
  bootstrap_ref="v$(sed -n 's/.*HERMES_FLY_TS_VERSION = \"\\([^\"]*\\)\".*/\\1/p' "${PROJECT_ROOT}/src/version.ts" | head -1)"
  tar -czf "$archive_file" -C "$archive_parent" "$(basename "$archive_root")"

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
printf '%s\n' "$url" >> "${MOCK_CURL_URL_FILE}"
if [[ "$url" == "https://codeload.github.com/alexfazio/hermes-fly/tar.gz/"* ]]; then
  cat "${MOCK_BOOTSTRAP_ARCHIVE_FILE}" > "$out"
  exit 0
fi
echo "unexpected curl url: $url" >&2
exit 1
MOCK
  chmod +x "$mock_dir/curl"
  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  run bash -c '
    export HOME="'"$fake_home"'"
    export HERMES_FLY_HOME="'"${TEST_TEMP_DIR}"'/custom_bootstrap_home"
    export PATH="'"$mock_dir"':${PATH}"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_CURL_URL_FILE="'"$url_file"'"
    export MOCK_BOOTSTRAP_REF="'"$bootstrap_ref"'"
    export MOCK_BOOTSTRAP_ARCHIVE_FILE="'"$archive_file"'"
    source "'"$script_copy"'"
    bootstrap_installer_cli
  '
  assert_success

  run cat "$node_args_file"
  assert_success
  assert_output --partial "dist/install-cli.js install --install-home ${TEST_TEMP_DIR}/custom_bootstrap_home --bin-dir ${expected_home}/.local/bin"
}

@test "main avoids a duplicate banner when the downloaded bootstrap installer still prints its own banner" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_standalone_banner"
  local script_dir="${TEST_TEMP_DIR}/standalone_script_banner"
  local script_copy="${script_dir}/install.sh"
  local node_args_file="${TEST_TEMP_DIR}/node_args_standalone_banner"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_standalone_banner"
  local url_file="${TEST_TEMP_DIR}/bootstrap_urls_standalone_banner"
  local archive_parent="${TEST_TEMP_DIR}/bootstrap_archive_parent_banner"
  local archive_root="${archive_parent}/hermes-fly-bootstrap"
  local archive_file="${TEST_TEMP_DIR}/bootstrap_source_banner.tar.gz"
  local bootstrap_ref

  mkdir -p "$mock_dir" "$script_dir" "$archive_root"
  cp "${PROJECT_ROOT}/scripts/install.sh" "$script_copy"
  chmod +x "$script_copy"
  write_source_checkout "$archive_root"
  bootstrap_ref="v$(sed -n 's/.*HERMES_FLY_TS_VERSION = \"\\([^\"]*\\)\".*/\\1/p' "${PROJECT_ROOT}/src/version.ts" | head -1)"
  tar -czf "$archive_file" -C "$archive_parent" "$(basename "$archive_root")"

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
printf '%s\n' "$url" >> "${MOCK_CURL_URL_FILE}"
if [[ "$url" == "https://codeload.github.com/alexfazio/hermes-fly/tar.gz/"* ]]; then
  cat "${MOCK_BOOTSTRAP_ARCHIVE_FILE}" > "$out"
  exit 0
fi
echo "unexpected curl url: $url" >&2
exit 1
MOCK
  chmod +x "$mock_dir/curl"
  write_mock_legacy_banner_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  run bash -c '
    export PATH="'"$mock_dir"':${PATH}"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_CURL_URL_FILE="'"$url_file"'"
    export MOCK_BOOTSTRAP_REF="'"$bootstrap_ref"'"
    export MOCK_BOOTSTRAP_ARCHIVE_FILE="'"$archive_file"'"
    source "'"$script_copy"'"
    main
  '
  assert_success
  assert_output --partial "🪽 Hermes Fly Installer"
  [[ "$(printf '%s' "$output" | grep -o "🪽 Hermes Fly Installer" | wc -l | tr -d ' ')" == "1" ]]
}

@test "main falls back to the legacy installer flow when Commander bootstrap fails" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args_fallback"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_fallback"
  local asset_root="${TEST_TEMP_DIR}/asset_root"
  local asset_file="${TEST_TEMP_DIR}/hermes-fly-v0.1.12.tar.gz"
  : > "$npm_args_file"

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
  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  local install_home="${TEST_TEMP_DIR}/hermes_home"
  local install_bin="${TEST_TEMP_DIR}/install_bin"
  run bash -c '
    export HERMES_FLY_CHANNEL="latest"
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_RELEASE_ASSET_FILE="'"$asset_file"'"
    export MOCK_INSTALLER_FAILURE_MESSAGE="Installer error: bootstrap failure"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_success
  assert_output --partial "Installing hermes-fly..."
  assert_output --partial "Downloading hermes-fly release asset"
  assert_output --partial "hermes-fly installed successfully!"
}

@test "legacy fallback prints PATH guidance when a user-local install dir is not on PATH" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_path_hint"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args_fallback_path_hint"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_fallback_path_hint"
  local asset_root="${TEST_TEMP_DIR}/asset_root_path_hint"
  local asset_file="${TEST_TEMP_DIR}/hermes-fly-v0.1.12-path-hint.tar.gz"
  local fake_home="${TEST_TEMP_DIR}/fallback_path_hint_home"
  local isolated_legacy_root="${TEST_TEMP_DIR}/fallback_path_hint_legacy"
  local expected_home expected_install_home expected_install_bin
  mkdir -p "$fake_home"
  expected_home="$fake_home"
  expected_install_home="${expected_home}/Library/Application Support/hermes-fly"
  expected_install_bin="${expected_home}/.local/bin"
  : > "$npm_args_file"

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
  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  run bash -c '
    export HOME="'"$fake_home"'"
    export SHELL="/bin/zsh"
    unset HERMES_FLY_HOME
    unset HERMES_FLY_INSTALL_DIR
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_RELEASE_ASSET_FILE="'"$asset_file"'"
    export MOCK_INSTALLER_FAILURE_MESSAGE="Installer error: bootstrap failure"
    export PATH="'"$mock_dir"':/usr/bin:/bin"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    is_effective_root_user() { return 1; }
    LEGACY_INSTALL_HOME="'"$isolated_legacy_root"'/lib/hermes-fly"
    LEGACY_BIN_DIR="'"$isolated_legacy_root"'/bin"
    main
  '

  assert_success
  assert_output --partial "Install to: ${expected_install_home}"
  assert_output --partial "Symlink in: ${expected_install_bin}"
  assert_output --partial "PATH missing hermes-fly bin dir: ${expected_install_bin}"
  assert_output --partial "Fix (zsh: ~/.zshrc, bash: ~/.bashrc):"
  assert_output --partial "export PATH=\"${expected_install_bin}:\$PATH\""
  assert_output --partial "hermes-fly installed successfully!"
}

@test "legacy fallback preserves installer arguments when Commander bootstrap fails" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_args"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args_fallback_args"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_fallback_args"
  local asset_root="${TEST_TEMP_DIR}/asset_root_args"
  local asset_file="${TEST_TEMP_DIR}/hermes-fly-v0.1.12-args.tar.gz"
  : > "$npm_args_file"

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
  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  local install_home="${TEST_TEMP_DIR}/custom_hermes_home"
  local install_bin="${TEST_TEMP_DIR}/custom_install_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"${TEST_TEMP_DIR}"'/ignored_home"
    export HERMES_FLY_INSTALL_DIR="'"${TEST_TEMP_DIR}"'/ignored_bin"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_RELEASE_ASSET_FILE="'"$asset_file"'"
    export MOCK_INSTALLER_FAILURE_MESSAGE="Installer error: bootstrap failure"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main --channel edge --version 0.1.12 --install-home "'"$install_home"'" --bin-dir "'"$install_bin"'"
  '
  assert_success
  assert_output --partial "Channel: edge"
  assert_output --partial "Install to: ${install_home}"
  assert_output --partial "Symlink in: ${install_bin}"
  assert_output --partial "Release: v0.1.12"
  assert [ -f "${install_home}/hermes-fly" ]
  assert [ -L "${install_bin}/hermes-fly" ]
}

@test "legacy fallback accepts supported installer arguments in --option=value form" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_equals"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args_fallback_equals"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_fallback_equals"
  local asset_root="${TEST_TEMP_DIR}/asset_root_equals"
  local asset_file="${TEST_TEMP_DIR}/hermes-fly-v0.1.12-equals.tar.gz"
  : > "$npm_args_file"

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
  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  local install_home="${TEST_TEMP_DIR}/equals_hermes_home"
  local install_bin="${TEST_TEMP_DIR}/equals_install_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"${TEST_TEMP_DIR}"'/ignored_equals_home"
    export HERMES_FLY_INSTALL_DIR="'"${TEST_TEMP_DIR}"'/ignored_equals_bin"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_RELEASE_ASSET_FILE="'"$asset_file"'"
    export MOCK_INSTALLER_FAILURE_MESSAGE="Installer error: bootstrap failure"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main --channel=edge --version=0.1.12 --install-home="'"$install_home"'" --bin-dir="'"$install_bin"'"
  '
  assert_success
  assert_output --partial "Channel: edge"
  assert_output --partial "Install to: ${install_home}"
  assert_output --partial "Symlink in: ${install_bin}"
  assert_output --partial "Release: v0.1.12"
  assert [ -f "${install_home}/hermes-fly" ]
  assert [ -L "${install_bin}/hermes-fly" ]
}

@test "legacy fallback fails fast on unsupported installer options" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin_bad_flag"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args_bad_flag"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_bad_flag"
  : > "$npm_args_file"

  write_mock_node "$mock_dir" "0.1.12"
  write_mock_npm "$mock_dir"

  local install_home="${TEST_TEMP_DIR}/bad_flag_home"
  local install_bin="${TEST_TEMP_DIR}/bad_flag_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_INSTALLER_FAILURE_MESSAGE="Installer error: unknown option --bogus"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main --bogus
  '
  assert_failure
  assert_output --partial "Installer error: unknown option --bogus"
  assert_output --partial "Unsupported installer option for legacy fallback: --bogus"
  refute_output --partial "Installing hermes-fly..."
  assert [ ! -e "${install_home}/hermes-fly" ]
  assert [ ! -e "${install_bin}/hermes-fly" ]
}

@test "legacy fallback still surfaces version mismatch when installed version differs" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local node_args_file="${TEST_TEMP_DIR}/node_args_mismatch"
  local npm_args_file="${TEST_TEMP_DIR}/npm_args_mismatch"
  local asset_root="${TEST_TEMP_DIR}/asset_root_mismatch"
  local asset_file="${TEST_TEMP_DIR}/hermes-fly-v0.1.12-mismatch.tar.gz"
  : > "$npm_args_file"

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

  write_mock_node "$mock_dir" "0.1.11"
  write_mock_npm "$mock_dir"

  local install_home="${TEST_TEMP_DIR}/hermes_home_mismatch"
  local install_bin="${TEST_TEMP_DIR}/install_bin_mismatch"
  run bash -c '
    export HERMES_FLY_CHANNEL="stable"
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_NODE_ARGS_FILE="'"$node_args_file"'"
    export MOCK_NPM_ARGS_FILE="'"$npm_args_file"'"
    export MOCK_RELEASE_ASSET_FILE="'"$asset_file"'"
    export MOCK_INSTALLER_FAILURE_MESSAGE="Installer error: bootstrap failure"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_failure
  assert_output --partial "Installed version mismatch"
}
