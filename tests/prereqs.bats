#!/usr/bin/env bats
# tests/prereqs.bats — TDD tests for lib/prereqs.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/prereqs.sh"
}

teardown() {
  _common_teardown
}

# --- Smoke test: module loads ---

@test "prereqs_detect_os is callable after sourcing" {
  run prereqs_detect_os
  assert_success
}

# --- Step 2: prereqs_detect_os() Tests ---

@test "detect_os returns Darwin:brew when on macOS with Homebrew" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run prereqs_detect_os
  assert_success
  assert_output "Darwin:brew"
}

@test "detect_os returns Darwin:no-brew when on macOS without Homebrew" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="/usr/bin:/bin"  # exclude mocks
  run prereqs_detect_os
  assert_success
  assert_output "Darwin:no-brew"
}

@test "detect_os returns Linux:apt when on apt-based Linux" {
  export HERMES_FLY_PLATFORM="Linux"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run prereqs_detect_os
  assert_success
  assert_output "Linux:apt"
}

@test "detect_os returns Linux:unsupported when on Linux without apt-get" {
  export HERMES_FLY_PLATFORM="Linux"
  PATH="/usr/bin:/bin"  # exclude mocks
  run prereqs_detect_os
  assert_success
  assert_output "Linux:unsupported"
}

@test "detect_os returns unsupported on unknown platform" {
  export HERMES_FLY_PLATFORM="FreeBSD"
  run prereqs_detect_os
  assert_success
  assert_output "unsupported"
}

@test "detect_os uses HERMES_FLY_PLATFORM override over uname" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="/usr/bin:/bin"
  # Even though platform is set to Darwin, it will check for brew
  run prereqs_detect_os
  assert_success
  assert_output "Darwin:no-brew"
}

# --- Step 3: prereqs_show_guide() Tests ---

@test "show_guide shows tool name in failure header when attempted provided" {
  run prereqs_show_guide "fly" "Darwin:brew" "brew install flyctl" "Connection refused"
  assert_success
  assert_output --partial "Could not install: fly"
}

@test "show_guide shows attempted command" {
  run prereqs_show_guide "git" "Linux:apt" "sudo apt-get install -y git" "Permission denied"
  assert_success
  assert_output --partial "Attempted:"
  assert_output --partial "sudo apt-get install -y git"
}

@test "show_guide shows OS context" {
  run prereqs_show_guide "curl" "Linux:apt" "apt-get install -y curl" "Package not found"
  assert_success
  assert_output --partial "OS detected:"
  assert_output --partial "Linux:apt"
}

@test "show_guide shows fly.io URL for fly tool" {
  run prereqs_show_guide "fly" "Darwin:brew" "brew install flyctl" "error"
  assert_success
  assert_output --partial "fly.io/docs/flyctl/install"
}

@test "show_guide shows git-scm URL for git tool" {
  run prereqs_show_guide "git" "Linux:apt" "" ""
  assert_success
  assert_output --partial "git-scm.com/downloads"
}

@test "show_guide shows curl.se URL for curl tool" {
  run prereqs_show_guide "curl" "Darwin:no-brew" "" ""
  assert_success
  assert_output --partial "curl.se/download.html"
}

@test "show_guide shows re-run instruction" {
  run prereqs_show_guide "fly" "Linux:apt" "curl -L..." "error"
  assert_success
  assert_output --partial "Re-run"
  assert_output --partial "hermes-fly deploy"
}

@test "show_guide works without attempted or error args" {
  run prereqs_show_guide "git" "Darwin:brew"
  assert_success
}

# --- Step 4: prereqs_install_tool() Tests ---

@test "install_tool calls brew for fly on Darwin:brew" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run prereqs_install_tool "fly" "Darwin:brew"
  assert_success
  assert_output --partial "installed"
}

@test "install_tool uses HERMES_FLY_FLYCTL_INSTALL_CMD on Darwin:no-brew" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="/usr/bin:/bin"  # exclude brew mock
  export HOME="$(mktemp -d)"

  # Create a simple mock install script
  local mock_script
  mock_script="$(mktemp)"
  cat > "$mock_script" <<'EOF'
#!/bin/bash
mkdir -p ~/.fly/bin
echo "#!/bin/bash" > ~/.fly/bin/flyctl
echo "echo 'mock flyctl'" >> ~/.fly/bin/flyctl
chmod +x ~/.fly/bin/flyctl
ln -sf ~/.fly/bin/flyctl ~/.fly/bin/fly
EOF
  chmod +x "$mock_script"

  export HERMES_FLY_FLYCTL_INSTALL_CMD="bash $mock_script"
  run prereqs_install_tool "fly" "Darwin:no-brew"
  assert_success
  assert_output --partial "installed"

  rm -f "$mock_script"
  rm -rf "$HOME"
}

@test "install_tool returns 1 and shows guide when install fails" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  export MOCK_BREW_FAIL=true

  run prereqs_install_tool "fly" "Darwin:brew"
  assert_failure
  assert_output --partial "Could not install"
  assert_output --partial "To install"
}

@test "install_tool adds ~/.fly/bin to PATH after flyctl install" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  # Create mock home with .fly/bin directory
  export HOME="$(mktemp -d)"
  mkdir -p "${HOME}/.fly/bin"

  run bash -c "source '${PROJECT_ROOT}/lib/ui.sh'; source '${PROJECT_ROOT}/lib/prereqs.sh'; prereqs_install_tool 'fly' 'Darwin:brew'; echo \"PATH=\${PATH}\""
  assert_success
  assert_output --partial "${HOME}/.fly/bin"

  rm -rf "$HOME"
}

@test "install_tool calls xcode-select for git on Darwin" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  run prereqs_install_tool "git" "Darwin:brew"
  assert_success
  assert_output --partial "installed"
}

@test "install_tool calls apt-get for git on Linux:apt" {
  export HERMES_FLY_PLATFORM="Linux"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  run prereqs_install_tool "git" "Linux:apt"
  assert_success
  assert_output --partial "installed"
}

@test "install_tool calls apt-get for curl on Linux:apt" {
  export HERMES_FLY_PLATFORM="Linux"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  run prereqs_install_tool "curl" "Linux:apt"
  assert_success
  assert_output --partial "installed"
}

@test "install_tool dumps captured output on install failure" {
  export HERMES_FLY_PLATFORM="Linux"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  export MOCK_APT_FAIL=true
  export MOCK_APT_FAIL_MSG="E: Unable to locate package git"

  run prereqs_install_tool "git" "Linux:apt"
  assert_failure
  assert_output --partial "Unable to locate package"
}

@test "install_tool returns 1 for unsupported platform" {
  export HERMES_FLY_PLATFORM="FreeBSD"

  run prereqs_install_tool "fly" "unsupported"
  assert_failure
}

# --- Step 5: prereqs_check_and_install() Tests ---

@test "check_and_install returns 0 when all tools present" {
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  # fly, git, curl are all mocks on PATH
  run prereqs_check_and_install
  assert_success
}

@test "check_and_install prompts for each missing tool" {
  PATH="/usr/bin:/bin"  # exclude mocks so tools are missing
  run bash -c "export HERMES_FLY_TEST_MODE=1; source '${PROJECT_ROOT}/lib/ui.sh'; source '${PROJECT_ROOT}/lib/prereqs.sh'; printf 'n\nn\nn\n' | prereqs_check_and_install 2>&1" || true
  assert_output --partial "Missing: fly"
}

@test "check_and_install returns 0 after successful install when user says yes" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  # Stub prereqs_install_tool to succeed and add tool to PATH
  export -f prereqs_install_tool
  prereqs_install_tool() {
    local tool="$1"
    # Create a fake tool
    local fake_dir="$(mktemp -d)"
    echo "#!/bin/bash" > "$fake_dir/$tool"
    chmod +x "$fake_dir/$tool"
    export PATH="$fake_dir:${PATH}"
  }

  # Remove one tool
  PATH="/usr/bin:/bin"

  # Create fake HOME
  export HOME="$(mktemp -d)"
  mkdir -p "${HOME}/.fly/bin"

  run bash -c "source '${PROJECT_ROOT}/lib/ui.sh'; source '${PROJECT_ROOT}/lib/prereqs.sh'; printf 'y\ny\ny\n' | prereqs_check_and_install 2>&1" || true

  rm -rf "$HOME"
}

@test "check_and_install shows guide and returns 1 when user says no" {
  PATH="/usr/bin:/bin"  # exclude mocks
  run bash -c "export HERMES_FLY_TEST_MODE=1; source '${PROJECT_ROOT}/lib/ui.sh'; source '${PROJECT_ROOT}/lib/prereqs.sh'; printf 'n\n' | prereqs_check_and_install 2>&1" || true
  assert_output --partial "hermes-fly deploy"
}

@test "check_and_install skips prompts and returns 1 when CI=true" {
  export CI=true
  export HERMES_FLY_TEST_MODE=1
  PATH="/usr/bin:/bin"  # no tools on PATH
  run prereqs_check_and_install
  assert_failure
  assert_output --partial "auto-install disabled"
}

@test "check_and_install skips prompts when HERMES_FLY_NO_AUTO_INSTALL=1" {
  export HERMES_FLY_NO_AUTO_INSTALL=1
  export HERMES_FLY_TEST_MODE=1
  PATH="/usr/bin:/bin"  # no tools on PATH
  run prereqs_check_and_install
  assert_failure
  assert_output --partial "auto-install disabled"
}

@test "check_and_install succeeds with CI=true when all tools present" {
  export CI=true
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run prereqs_check_and_install
  assert_success
}

# --- STEP 2-3: _prereqs_check_tool_available() Tests ---

@test "_prereqs_check_tool_available returns 0 when fly binary found via command -v" {
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run _prereqs_check_tool_available "fly"
  assert_success
}

@test "_prereqs_check_tool_available returns 1 when fly exists but is not callable" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  local fake_home
  fake_home="$(mktemp -d)"
  cat > "$fake_dir/fly" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "version" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$fake_dir/fly"

  export HERMES_FLY_TEST_MODE=1
  export HOME="$fake_home"
  PATH="$fake_dir:/usr/bin:/bin"
  run _prereqs_check_tool_available "fly"
  assert_failure

  rm -rf "$fake_dir"
  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 0 when flyctl found and fly sibling symlink exists" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"
  ln -s "$fake_dir/flyctl" "$fake_dir/fly"

  export HERMES_FLY_TEST_MODE=1
  PATH="$fake_dir:/usr/bin:/bin"
  run _prereqs_check_tool_available "fly"
  assert_success

  rm -rf "$fake_dir"
}

@test "_prereqs_check_tool_available returns 1 when flyctl found but no fly symlink exists" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"

  export HERMES_FLY_TEST_MODE=1
  PATH="$fake_dir:/usr/bin:/bin"
  run _prereqs_check_tool_available "fly"
  assert_failure

  rm -rf "$fake_dir"
}

@test "_prereqs_check_tool_available restores PATH when flyctl fallback fails" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"

  run bash -c "
    export HERMES_FLY_TEST_MODE=1
    PATH='$fake_dir:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    before=\"\$PATH\"
    _prereqs_check_tool_available 'fly' >/dev/null 2>&1
    rc=\$?
    after=\"\$PATH\"
    echo \"rc=\$rc\"
    echo \"before=\$before\"
    echo \"after=\$after\"
  "
  assert_success
  assert_line "rc=1"
  assert_line "before=$fake_dir:/usr/bin:/bin"
  assert_line "after=$fake_dir:/usr/bin:/bin"

  rm -rf "$fake_dir"
}

@test "_prereqs_check_tool_available adds flyctl directory to PATH when flyctl found" {
  local fake_dir
  fake_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$fake_dir/flyctl"
  chmod +x "$fake_dir/flyctl"
  ln -s "$fake_dir/flyctl" "$fake_dir/fly"

  run bash -c "
    export HERMES_FLY_TEST_MODE=1
    PATH='$fake_dir:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
    echo \"\$PATH\" | grep -c '$fake_dir'
  "
  assert_success

  rm -rf "$fake_dir"
}

@test "_prereqs_check_tool_available returns 0 and exports PATH when ~/.fly/bin/fly file found" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
    echo \"PATH_CONTAINS_FLY_BIN=\$(echo \$PATH | grep -c '.fly/bin' || true)\"
  "
  assert_success
  assert_output --partial "PATH_CONTAINS_FLY_BIN=1"

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 0 and exports PATH when ~/.fly/bin/flyctl file found with fly symlink" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/flyctl"
  chmod +x "$fake_home/.fly/bin/flyctl"
  ln -s "$fake_home/.fly/bin/flyctl" "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
    echo \"PATH_CONTAINS_FLY_BIN=\$(echo \$PATH | grep -c '.fly/bin' || true)\"
  "
  assert_success
  assert_output --partial "PATH_CONTAINS_FLY_BIN=1"

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 1 when no fly/flyctl/~/.fly/bin path exists" {
  local fake_home
  fake_home="$(mktemp -d)"
  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
  "
  assert_failure

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available handles git with standard command check" {
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run _prereqs_check_tool_available "git"
  assert_success
}

@test "_prereqs_check_tool_available handles curl with standard command check" {
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  run _prereqs_check_tool_available "curl"
  assert_success
}

@test "_prereqs_check_tool_available skips PATH export and returns 1 when CI=true" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  export CI=true
  PATH="/usr/bin:/bin"

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
  "
  # CI=true skips PATH export, so fly is not callable even though file exists
  assert_failure

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 1 when ~/.fly/bin/fly exists but is NOT executable (fallback path)" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  # Explicitly do NOT chmod +x — file is non-executable

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks to force fallback detection

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
  "
  assert_failure

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 1 when ~/.fly/bin/flyctl exists but is NOT executable (fallback path)" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/flyctl"
  # Explicitly do NOT chmod +x — file is non-executable

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks to force fallback detection

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
  "
  assert_failure

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 0 when ~/.fly/bin/fly exists AND IS executable (fallback path regression)" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks to force fallback detection

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
    echo \"PATH_CONTAINS_FLY_BIN=\$(echo \$PATH | grep -c '.fly/bin' || true)\"
  "
  assert_success
  assert_output --partial "PATH_CONTAINS_FLY_BIN=1"

  rm -rf "$fake_home"
}

# --- STEP 3: Updated prereqs_check_and_install() Tests ---

@test "check_and_install does not prompt to install fly when ~/.fly/bin/fly detected in second run" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="/usr/bin:/bin"  # exclude mocks so only ~/.fly/bin/fly is found

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    prereqs_check_and_install 2>&1
  "
  assert_success
  # Should not see "Missing: fly" prompt
  refute_output --partial "Missing: fly"

  rm -rf "$fake_home"
}

@test "check_and_install uses helper function to detect fly tool" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"
  PATH="/usr/bin:/bin"  # exclude mocks

  # Add git and curl mocks
  local mock_dir
  mock_dir="$(mktemp -d)"
  echo "#!/bin/bash" > "$mock_dir/git"
  chmod +x "$mock_dir/git"
  echo "#!/bin/bash" > "$mock_dir/curl"
  chmod +x "$mock_dir/curl"

  PATH="$mock_dir:${PATH}"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    prereqs_check_and_install 2>&1
  "
  assert_success

  rm -rf "$fake_home" "$mock_dir"
}

# --- STEP 4: _prereqs_detect_shell() Tests ---

@test "_prereqs_detect_shell returns zsh from SHELL=/bin/zsh even when BASH_VERSION is set" {
  run bash -c "
    export SHELL='/bin/zsh'
    export BASH_VERSION='5.1.16'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_detect_shell
  "
  assert_success
  assert_output "zsh"
}

@test "_prereqs_detect_shell returns fish from SHELL=/usr/local/bin/fish via basename extraction" {
  run bash -c "
    export SHELL='/usr/local/bin/fish'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_detect_shell
  "
  assert_success
  assert_output "fish"
}

@test "_prereqs_detect_shell returns zsh from ZSH_VERSION when SHELL env var is unset" {
  run bash -c "
    unset SHELL
    export ZSH_VERSION='5.8'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_detect_shell
  "
  assert_success
  assert_output "zsh"
}

@test "_prereqs_detect_shell returns bash from BASH_VERSION when SHELL unset and ZSH_VERSION unset" {
  run bash -c "
    unset SHELL ZSH_VERSION
    export BASH_VERSION='5.1.16'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_detect_shell
  "
  assert_success
  assert_output "bash"
}

@test "_prereqs_detect_shell returns sh when no detection variables present" {
  run bash -c "
    unset ZSH_VERSION BASH_VERSION SHELL
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_detect_shell
  "
  assert_success
  assert_output "sh"
}

# --- STEP 5: _prereqs_get_shell_config() Tests ---

@test "_prereqs_get_shell_config returns expanded HOME/.zshrc for zsh shell" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_get_shell_config 'zsh'
  "
  assert_success
  assert_output "${HOME}/.zshrc"
}

@test "_prereqs_get_shell_config returns expanded HOME/.bashrc for bash shell" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_get_shell_config 'bash'
  "
  assert_success
  assert_output "${HOME}/.bashrc"
}

@test "_prereqs_get_shell_config returns expanded HOME/.config/fish/config.fish for fish shell" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_get_shell_config 'fish'
  "
  assert_success
  assert_output "${HOME}/.config/fish/config.fish"
}

@test "_prereqs_get_shell_config returns exit code 1 for unknown shell" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_get_shell_config 'unknown'
  "
  assert_failure
}

# --- STEP 6: _prereqs_reload_shell_config() Tests ---

@test "_prereqs_reload_shell_config does not terminate process when config has exit 42" {
  local fake_home
  fake_home="$(mktemp -d)"
  echo "exit 42" > "$fake_home/.bashrc"

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/bash'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
    echo 'process_survived'
  "
  assert_success
  assert_output --partial "process_survived"

  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config extracts and applies export PATH line from config" {
  local fake_home
  fake_home="$(mktemp -d)"
  cat > "$fake_home/.bashrc" <<'CONF'
# some comment
alias ll='ls -la'
export PATH=/custom/new/path:$PATH
my_function() { echo hello; }
CONF

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/bash'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
    echo \"\$PATH\" | grep -c '/custom/new/path'
  "
  assert_success
  assert_output "1"

  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config returns 0 when config has no export PATH line" {
  local fake_home
  fake_home="$(mktemp -d)"
  echo "# just a comment" > "$fake_home/.bashrc"

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/bash'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
  "
  assert_success

  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config does not import functions or aliases from config" {
  local fake_home
  fake_home="$(mktemp -d)"
  cat > "$fake_home/.bashrc" <<'CONF'
my_test_func() { echo "imported"; }
alias my_test_alias='echo imported'
export PATH=/some/path:$PATH
CONF

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/bash'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
    if declare -f my_test_func >/dev/null 2>&1; then
      echo 'FUNCTION_IMPORTED'
    else
      echo 'NO_FUNCTION'
    fi
  "
  assert_success
  assert_output "NO_FUNCTION"

  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config returns 0 when config file exists and sources successfully" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home"
  echo "# bashrc" > "$fake_home/.bashrc"

  export HOME="$fake_home"
  export SHELL="/bin/bash"

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
  "
  assert_success

  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config returns 1 when shell has no known config file" {
  run bash -c "
    unset BASH_VERSION ZSH_VERSION
    export SHELL='/usr/bin/unknown_shell'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
  "
  assert_failure
}

@test "_prereqs_reload_shell_config returns 1 when config file does not exist on filesystem" {
  local fake_home
  fake_home="$(mktemp -d)"
  # Don't create config file

  export HOME="$fake_home"
  export SHELL="/bin/bash"

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
  "
  assert_failure

  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config returns 1 when config file is unreadable" {
  local fake_home
  fake_home="$(mktemp -d)"
  echo "export PATH=/tmp/test:\$PATH" > "$fake_home/.bashrc"
  chmod 000 "$fake_home/.bashrc"

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/bash'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config
  "
  assert_failure

  chmod 600 "$fake_home/.bashrc"
  rm -rf "$fake_home"
}

@test "_prereqs_reload_shell_config gracefully handles CI environments where shell config missing" {
  local fake_home
  fake_home="$(mktemp -d)"
  # Don't create config file

  export HOME="$fake_home"
  export SHELL="/bin/bash"
  export CI=true

  run bash -c "
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_reload_shell_config 2>&1
  "
  # Should fail gracefully (exit 1)
  assert_failure

  rm -rf "$fake_home"
}

# --- STEP 7: Updated prereqs_install_tool() Tests ---

@test "_prereqs_check_tool_available twice does not duplicate ~/.fly/bin in PATH" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  run bash -c "
    export HOME='$fake_home'
    PATH='/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
    _prereqs_check_tool_available 'fly'
    echo \"\$PATH\" | tr ':' '\n' | grep -c '.fly/bin'
  "
  assert_success
  assert_output "1"

  rm -rf "$fake_home"
}

@test "prereqs_install_tool does not add ~/.fly/bin to PATH when already present" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  run bash -c "
    export HOME='$fake_home'
    export PATH='${BATS_TEST_DIRNAME}/mocks:$fake_home/.fly/bin:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    prereqs_install_tool 'fly' 'Darwin:brew'
    echo \"\$PATH\" | tr ':' '\n' | grep -c '.fly/bin'
  "
  assert_success
  assert_output --partial "1"

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available first call correctly adds ~/.fly/bin when absent" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  run bash -c "
    export HOME='$fake_home'
    PATH='/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
    echo \"\$PATH\" | tr ':' '\n' | grep -c '.fly/bin'
  "
  assert_success
  assert_output "1"

  rm -rf "$fake_home"
}

@test "install_tool shows source ~/.zshrc in failure message when SHELL is zsh" {
  local fake_home
  fake_home="$(mktemp -d)"

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/zsh'
    export HERMES_FLY_TEST_MODE=1
    PATH='${BATS_TEST_DIRNAME}/mocks:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    # Force post-install verification to fail
    _prereqs_check_tool_available() { return 1; }
    prereqs_install_tool 'fly' 'Darwin:brew' 2>&1
  "
  assert_failure
  assert_output --partial '.zshrc'

  rm -rf "$fake_home"
}

@test "install_tool shows source ~/.bashrc in failure message when SHELL is bash" {
  local fake_home
  fake_home="$(mktemp -d)"

  run bash -c "
    export HOME='$fake_home'
    export SHELL='/bin/bash'
    export HERMES_FLY_TEST_MODE=1
    PATH='${BATS_TEST_DIRNAME}/mocks:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    # Force post-install verification to fail
    _prereqs_check_tool_available() { return 1; }
    prereqs_install_tool 'fly' 'Darwin:brew' 2>&1
  "
  assert_failure
  assert_output --partial '.bashrc'

  rm -rf "$fake_home"
}

@test "install_tool falls back to restart your terminal for unknown shell" {
  local fake_home
  fake_home="$(mktemp -d)"

  run bash -c "
    export HOME='$fake_home'
    unset SHELL ZSH_VERSION BASH_VERSION
    export HERMES_FLY_TEST_MODE=1
    PATH='${BATS_TEST_DIRNAME}/mocks:/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    # Force post-install verification to fail
    _prereqs_check_tool_available() { return 1; }
    prereqs_install_tool 'fly' 'Darwin:brew' 2>&1
  "
  assert_failure
  assert_output --partial 'restart your terminal'

  rm -rf "$fake_home"
}

@test "install_tool post-install verification succeeds when file exists and callable" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  export HOME="$fake_home"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    prereqs_install_tool 'fly' 'Darwin:brew'
  "
  assert_success
  assert_output --partial "installed"

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 1 when only ~/.fly/bin/flyctl exists (flyctl-only, no fly symlink)" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/flyctl"
  chmod +x "$fake_home/.fly/bin/flyctl"
  # No fly symlink — only flyctl exists

  run bash -c "
    export HOME='$fake_home'
    export HERMES_FLY_TEST_MODE=0
    PATH='/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
  "
  assert_failure  # Should return 1: file exists but fly is not callable

  rm -rf "$fake_home"
}

@test "_prereqs_check_tool_available returns 1 when CI=true and fly only in ~/.fly/bin (PATH not exported)" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"

  run bash -c "
    export HOME='$fake_home'
    export CI=true
    export HERMES_FLY_TEST_MODE=0
    PATH='/usr/bin:/bin'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    _prereqs_check_tool_available 'fly'
  "
  assert_failure  # Should return 1: CI=true skips PATH export, so fly not callable

  rm -rf "$fake_home"
}

@test "install_tool does NOT call _prereqs_reload_shell_config on success" {
  export HERMES_FLY_PLATFORM="Darwin"
  PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.fly/bin"
  echo "#!/bin/bash" > "$fake_home/.fly/bin/fly"
  chmod +x "$fake_home/.fly/bin/fly"
  echo "# bashrc" > "$fake_home/.bashrc"

  export HOME="$fake_home"
  export SHELL="/bin/bash"

  run bash -c "
    source '${PROJECT_ROOT}/lib/ui.sh'
    source '${PROJECT_ROOT}/lib/prereqs.sh'
    # Override _prereqs_reload_shell_config to detect if called
    _prereqs_reload_shell_config() { echo 'RELOAD_CALLED'; }
    prereqs_install_tool 'fly' 'Darwin:brew'
  "
  assert_success
  refute_output --partial "RELOAD_CALLED"

  rm -rf "$fake_home"
}
