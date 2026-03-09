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
  mkdir -p "$src/lib" "$src/templates"
  echo '#!/bin/sh' > "$src/hermes-fly"
  echo 'ui code' > "$src/lib/ui.sh"
  echo 'template' > "$src/templates/Dockerfile.template"

  local dest="${TEST_TEMP_DIR}/hermes-home"
  local bin="${TEST_TEMP_DIR}/bin"
  run install_files "$src" "$dest" "$bin"
  assert_success
  assert [ -f "${dest}/hermes-fly" ]
  assert [ -x "${dest}/hermes-fly" ]
  assert [ -f "${dest}/lib/ui.sh" ]
  assert [ -f "${dest}/templates/Dockerfile.template" ]
  assert [ -L "${bin}/hermes-fly" ]
}

# --- release resolution ---

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

@test "resolve_install_ref normalizes HERMES_FLY_VERSION override without v prefix" {
  run bash -c '
    export HERMES_FLY_VERSION="0.1.12"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    resolve_install_ref
  '
  assert_success
  assert_output "v0.1.12"
}

# --- main() with git clone ---

@test "install main clones latest release tag and installs matching version" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"
  local git_args_file="${TEST_TEMP_DIR}/git_args"

  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{"tag_name":"v0.1.12"}\n'
MOCK
  chmod +x "$mock_dir/curl"

  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  printf '%s\n' "$*" > "${MOCK_GIT_ARGS_FILE}"
  dest="${@: -1}"
  mkdir -p "$dest/lib" "$dest/templates"
  printf '#!/bin/sh\necho "hermes-fly 0.1.12"\n' > "$dest/hermes-fly"
  echo 'ui' > "$dest/lib/ui.sh"
  echo 'tpl' > "$dest/templates/Dockerfile.template"
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/git"

  local install_home="${TEST_TEMP_DIR}/hermes_home"
  local install_bin="${TEST_TEMP_DIR}/install_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export MOCK_GIT_ARGS_FILE="'"$git_args_file"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_success
  assert_output --partial "hermes-fly installed successfully"
  assert_output --partial "hermes-fly 0.1.12"
  assert [ -f "${install_home}/hermes-fly" ]
  assert [ -f "${install_home}/lib/ui.sh" ]
  assert [ -L "${install_bin}/hermes-fly" ]
  run cat "$git_args_file"
  assert_success
  assert_output --partial "--branch v0.1.12"
}

@test "install main fails when installed version does not match requested release" {
  local mock_dir="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{"tag_name":"v0.1.12"}\n'
MOCK
  chmod +x "$mock_dir/curl"

  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest/lib" "$dest/templates"
  printf '#!/bin/sh\necho "hermes-fly 0.1.11"\n' > "$dest/hermes-fly"
  echo 'ui' > "$dest/lib/ui.sh"
  echo 'tpl' > "$dest/templates/Dockerfile.template"
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_dir/git"

  local install_home="${TEST_TEMP_DIR}/hermes_home"
  local install_bin="${TEST_TEMP_DIR}/install_bin"
  run bash -c '
    export HERMES_FLY_HOME="'"$install_home"'"
    export HERMES_FLY_INSTALL_DIR="'"$install_bin"'"
    export PATH="'"$mock_dir"':${PATH}"
    source "'"${PROJECT_ROOT}"'/scripts/install.sh"
    main
  '
  assert_failure
  assert_output --partial "Installed version mismatch"
}
