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

  # Create a simple mock install script
  local mock_script
  mock_script="$(mktemp)"
  cat > "$mock_script" <<'EOF'
#!/bin/bash
mkdir -p ~/.fly/bin
echo "flyctl installed"
EOF
  chmod +x "$mock_script"

  export HERMES_FLY_FLYCTL_INSTALL_CMD="bash $mock_script"
  run prereqs_install_tool "fly" "Darwin:no-brew"
  assert_success
  assert_output --partial "installed"

  rm -f "$mock_script"
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
  run bash -c "source '${PROJECT_ROOT}/lib/ui.sh'; source '${PROJECT_ROOT}/lib/prereqs.sh'; printf 'n\nn\nn\n' | prereqs_check_and_install 2>&1" || true
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
  run bash -c "source '${PROJECT_ROOT}/lib/ui.sh'; source '${PROJECT_ROOT}/lib/prereqs.sh'; printf 'n\n' | prereqs_check_and_install 2>&1" || true
  assert_output --partial "hermes-fly deploy"
}

@test "check_and_install skips prompts and returns 1 when CI=true" {
  export CI=true
  PATH="/usr/bin:/bin"  # no tools on PATH
  run prereqs_check_and_install
  assert_failure
  assert_output --partial "auto-install disabled"
}

@test "check_and_install skips prompts when HERMES_FLY_NO_AUTO_INSTALL=1" {
  export HERMES_FLY_NO_AUTO_INSTALL=1
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
