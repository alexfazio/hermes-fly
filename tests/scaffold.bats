#!/usr/bin/env bats
# tests/scaffold.bats — Verify project scaffolding

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

teardown() {
  _common_teardown
}

@test "common-setup loads and sets PROJECT_ROOT" {
  [[ -n "${PROJECT_ROOT}" ]]
  [[ -d "${PROJECT_ROOT}/lib" ]]
  [[ -d "${PROJECT_ROOT}/templates" ]]
}

@test "mock fly is on PATH and responds to auth whoami" {
  run fly auth whoami
  assert_success
  assert_output "test-user@example.com"
}

@test "mock fly returns failure when MOCK_FLY_AUTH=fail" {
  export MOCK_FLY_AUTH=fail
  run fly auth whoami
  assert_failure
  assert_output --partial "not logged in"
}

@test "lib/ui.sh exits 1 when executed directly" {
  run bash "${PROJECT_ROOT}/lib/ui.sh"
  assert_failure
  assert_output --partial "source this file"
}

@test "lib/fly-helpers.sh exits 1 when executed directly" {
  run bash "${PROJECT_ROOT}/lib/fly-helpers.sh"
  assert_failure
  assert_output --partial "source this file"
}

@test "lib/docker-helpers.sh exits 1 when executed directly" {
  run bash "${PROJECT_ROOT}/lib/docker-helpers.sh"
  assert_failure
  assert_output --partial "source this file"
}

@test "lib/config.sh exits 1 when executed directly" {
  run bash "${PROJECT_ROOT}/lib/config.sh"
  assert_failure
  assert_output --partial "source this file"
}

@test "lib/deploy.sh exits 1 when executed directly" {
  run bash "${PROJECT_ROOT}/lib/deploy.sh"
  assert_failure
  assert_output --partial "source this file"
}

@test "templates/Dockerfile.template contains HERMES_VERSION placeholder" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_success
  assert_output --partial "{{HERMES_VERSION}}"
  assert_output --partial "FROM python:3.11-slim"
  assert_output --partial "ENTRYPOINT"
}

@test "templates/fly.toml.template contains all placeholders" {
  run cat "${PROJECT_ROOT}/templates/fly.toml.template"
  assert_success
  assert_output --partial "{{APP_NAME}}"
  assert_output --partial "{{REGION}}"
  assert_output --partial "{{VM_SIZE}}"
  assert_output --partial "{{VOLUME_NAME}}"
}

@test "templates/fly.toml.template has http_service with auto_stop off" {
  run cat "${PROJECT_ROOT}/templates/fly.toml.template"
  assert_output --partial "[http_service]"
  assert_output --partial 'auto_stop_machines = "off"'
  assert_output --partial "min_machines_running = 1"
}
