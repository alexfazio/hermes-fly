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
  assert_output --partial 'io.hermes.deploy.channel="stable"'
  assert_output --partial 'io.hermes.compatibility_policy="unknown"'
}

@test "generate_dockerfile with SHA version" {
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "abc123def"
  assert_success
  assert [ -f "$TEST_TEMP_DIR/Dockerfile" ]
  run cat "$TEST_TEMP_DIR/Dockerfile"
  assert_output --partial "HERMES_VERSION=abc123def"
}

@test "generate_dockerfile renders explicit channel and compat policy metadata" {
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "abc123def" "preview" "1.0.0"
  assert_success
  run cat "$TEST_TEMP_DIR/Dockerfile"
  assert_output --partial "ARG HERMES_CHANNEL=preview"
  assert_output --partial "ARG HERMES_COMPAT_POLICY=1.0.0"
  assert_output --partial 'io.hermes.deploy.channel="preview"'
  assert_output --partial 'io.hermes.compatibility_policy="1.0.0"'
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

@test "templates/Dockerfile.template installs hermes-agent from versioned install entrypoint path" {
  local template="${PROJECT_ROOT}/templates/Dockerfile.template"
  run cat "$template"
  assert_output --partial "raw.githubusercontent.com/NousResearch/hermes-agent/\${HERMES_VERSION}/scripts/install.sh"
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

# --- Dockerfile.template volume-safe layout ---

@test "templates/Dockerfile.template moves hermes-agent to /opt/hermes" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_output --partial "/opt/hermes/hermes-agent"
}

@test "templates/Dockerfile.template copies entrypoint.sh" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_output --partial "COPY entrypoint.sh /entrypoint.sh"
}

@test "templates/Dockerfile.template ENTRYPOINT is /entrypoint.sh" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_output --partial '"/entrypoint.sh"'
}

@test "templates/Dockerfile.template moves node to /opt/hermes" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_output --partial "mv /root/.hermes/node"
  assert_output --partial "/opt/hermes/node"
}

@test "templates/Dockerfile.template creates /opt/hermes/defaults" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_output --partial "/opt/hermes/defaults"
}

# --- docker_generate_entrypoint ---

@test "docker_generate_entrypoint copies entrypoint.sh to build dir" {
  run docker_generate_entrypoint "$TEST_TEMP_DIR"
  assert_success
  assert [ -f "$TEST_TEMP_DIR/entrypoint.sh" ]
}

@test "docker_generate_entrypoint fails when template missing" {
  local old_dir="$DOCKER_HELPERS_TEMPLATE_DIR"
  DOCKER_HELPERS_TEMPLATE_DIR="/nonexistent"
  run docker_generate_entrypoint "$TEST_TEMP_DIR"
  DOCKER_HELPERS_TEMPLATE_DIR="$old_dir"
  assert_failure
}

# --- Symlink resilience ---

# --- PR 3: Pinned ref rendering ---

@test "generate_dockerfile with 40-char SHA renders exact ref in ARG and LABEL" {
  local sha="8eefbef91cd715cfe410bba8c13cfab4eb3040df"
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "$sha"
  assert_success
  run cat "$TEST_TEMP_DIR/Dockerfile"
  # ARG line gets the pinned SHA (Docker resolves ${HERMES_VERSION} at build time)
  assert_output --partial "ARG HERMES_VERSION=${sha}"
  # LABEL line
  assert_output --partial "version=\"${sha}\""
  # Must NOT contain "main"
  refute_output --partial "HERMES_VERSION=main"
}

# --- REVIEW_1: M1 — sed-safe ref rendering ---

@test "generate_dockerfile with pipe char in ref renders literally" {
  # M1: refs containing | must not break sed delimiter
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "feature|pipe"
  assert_success
  run cat "$TEST_TEMP_DIR/Dockerfile"
  assert_output --partial "HERMES_VERSION=feature|pipe"
}

@test "generate_dockerfile with ampersand in ref renders literally" {
  # M1: & is a sed backreference; must be escaped for literal output
  run docker_generate_dockerfile "$TEST_TEMP_DIR" "v1.0&hotfix"
  assert_success
  run cat "$TEST_TEMP_DIR/Dockerfile"
  assert_output --partial "HERMES_VERSION=v1.0&hotfix"
}

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
