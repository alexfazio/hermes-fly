#!/usr/bin/env bats
# tests/docker-helpers.bats — TDD tests for lib/docker-helpers.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  source "${PROJECT_ROOT}/lib/docker-helpers.sh"
}

teardown() { _common_teardown; }

# --- docker_generate_dockerfile ---

@test "generate_dockerfile creates file with version substituted" {
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "main"
  assert_success
  assert [ -f "$TEST_TEMP_DIR/Dockerfile" ]
  run cat "$TEST_TEMP_DIR/Dockerfile"
  assert_output --partial "HERMES_VERSION=main"
}

@test "generate_dockerfile with SHA version" {
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "abc123def"
  assert_success
  assert [ -f "$TEST_TEMP_DIR/Dockerfile" ]
  run cat "$TEST_TEMP_DIR/Dockerfile"
  assert_output --partial "HERMES_VERSION=abc123def"
}

# --- docker_generate_fly_toml ---

@test "generate_fly_toml substitutes all fields" {
  run docker_generate_fly_toml "$TEST_TEMP_DIR" "my-app" "ord" "shared-cpu-1x" "512mb" "hermes_data" "5gb"
  assert_success
  assert [ -f "$TEST_TEMP_DIR/fly.toml" ]
  run cat "$TEST_TEMP_DIR/fly.toml"
  assert_output --partial 'app = "my-app"'
  assert_output --partial 'primary_region = "ord"'
  assert_output --partial 'size = "shared-cpu-1x"'
  assert_output --partial 'memory = "512mb"'
  assert_output --partial 'source = "hermes_data"'
  assert_output --partial 'initial_size = "5gb"'
}

# --- Dockerfile template includes required system packages ---

@test "templates/Dockerfile.template contains all required system packages" {
  local template="${PROJECT_ROOT}/templates/Dockerfile.template"
  run cat "$template"
  assert_output --partial "git"
  assert_output --partial "curl"
  assert_output --partial "xz-utils"
}

@test "templates/Dockerfile.template adds ~/.local/bin to PATH" {
  local template="${PROJECT_ROOT}/templates/Dockerfile.template"
  run cat "$template"
  assert_output --partial '/root/.local/bin'
}

@test "templates/Dockerfile.template passes --skip-setup to installer" {
  local template="${PROJECT_ROOT}/templates/Dockerfile.template"
  run cat "$template"
  assert_output --partial "--skip-setup"
}

# --- docker_validate_dockerfile ---

@test "validate_dockerfile returns 0 for valid file" {
  docker_generate_dockerfile "$TEST_TEMP_DIR" "main"
  run docker_validate_dockerfile "$TEST_TEMP_DIR/Dockerfile"
  assert_success
}

@test "validate_dockerfile returns 1 for file missing FROM" {
  cat > "$TEST_TEMP_DIR/Dockerfile" <<'EOF'
LABEL maintainer="hermes"
ENTRYPOINT ["hermes", "gateway"]
EOF
  run docker_validate_dockerfile "$TEST_TEMP_DIR/Dockerfile"
  assert_failure
}

@test "validate_dockerfile returns 1 for nonexistent file" {
  run docker_validate_dockerfile "/nonexistent"
  assert_failure
}

# --- docker_get_build_dir ---

@test "get_build_dir creates and returns temp directory" {
  run docker_get_build_dir
  assert_success
  assert [ -d "$output" ]
  # cleanup
  rm -rf "$output"
}

# --- Symlink resilience ---

@test "docker_generate_dockerfile works when lib is symlinked" {
  # Create symlink to docker-helpers.sh in temp dir
  ln -s "${PROJECT_ROOT}/lib/docker-helpers.sh" "${TEST_TEMP_DIR}/docker-helpers-link.sh"

  local build_dir="${TEST_TEMP_DIR}/build"

  # Source via symlink in subshell to test BASH_SOURCE resolution
  run bash -c '
    source "'"${TEST_TEMP_DIR}/docker-helpers-link.sh"'"
    docker_generate_dockerfile "'"${build_dir}"'" "v1.0.0" 2>/dev/null
    cat "'"${build_dir}/Dockerfile"'" 2>/dev/null
  '
  assert_success
  assert_output --partial "v1.0.0"
}
