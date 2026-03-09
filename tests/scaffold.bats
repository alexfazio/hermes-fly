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

# --- entrypoint.sh template ---

@test "templates/entrypoint.sh exists" {
  assert [ -f "${PROJECT_ROOT}/templates/entrypoint.sh" ]
}

@test "templates/entrypoint.sh symlinks hermes-agent from /opt/hermes" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_output --partial "ln -sfn /opt/hermes/hermes-agent /root/.hermes/hermes-agent"
}

@test "templates/entrypoint.sh execs hermes from /opt/hermes venv" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_output --partial "exec /opt/hermes/hermes-agent/venv/bin/hermes gateway"
}

@test "templates/entrypoint.sh symlinks node from /opt/hermes" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_output --partial "ln -sfn /opt/hermes/node /root/.hermes/node"
}

@test "templates/entrypoint.sh creates all runtime directories" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_output --partial "cron"
  assert_output --partial "pairing"
  assert_output --partial "whatsapp/session"
}

@test "templates/entrypoint.sh seeds default config files" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_output --partial 'cp /opt/hermes/defaults/$f /root/.hermes/$f'
}

@test "templates/entrypoint.sh seeds skills dir on first deploy" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_output --partial "cp -r /opt/hermes/defaults/skills /root/.hermes/skills"
}

@test "entrypoint.sh bridges Fly secrets into .env on every boot" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "OPENROUTER_API_KEY"
  assert_output --partial "/root/.hermes/.env"
}

@test "entrypoint.sh bridges all messaging and LLM secrets" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "TELEGRAM_BOT_TOKEN"
  assert_output --partial "DISCORD_BOT_TOKEN"
}

@test "entrypoint.sh patches config.yaml model from LLM_MODEL" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "LLM_MODEL"
  assert_output --partial "config.yaml"
  assert_output --partial "sed"
}

@test "entrypoint.sh clears rate limits for approved users" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "_rate_limits.json"
  assert_output --partial "approved.json"
}

@test "entrypoint.sh escapes pipe characters in LLM_MODEL for sed safety" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial '//|/'
}

# --- Entrypoint auto-approve ---

@test "entrypoint.sh pre-seeds telegram-approved.json from TELEGRAM_ALLOWED_USERS" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "telegram-approved.json"
  assert_output --partial "auto-approved"
  assert_output --partial "TELEGRAM_ALLOWED_USERS"
}

@test "entrypoint.sh only pre-seeds on first boot (no overwrite on restart)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "! -f"
  assert_output --partial "telegram-approved.json"
}

@test "entrypoint.sh contains bot description auto-config" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "setMyDescription"
}

@test "entrypoint.sh bot description does not block startup on failure" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "|| true"
  assert_output --partial "Warning"
}

@test "entrypoint.sh bot description uses URL encoding" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "data-urlencode"
}

@test "entrypoint.sh bridges HERMES_APP_NAME GATEWAY_ALLOW_ALL_USERS TELEGRAM_HOME_CHANNEL" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_APP_NAME"
  assert_output --partial "GATEWAY_ALLOW_ALL_USERS"
  assert_output --partial "TELEGRAM_HOME_CHANNEL"
}

@test "entrypoint.sh fetches getMyShortDescription independently" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "getMyShortDescription"
}

@test "entrypoint.sh reconciles short-description independently from long description" {
  # Short description should have its own comparison block, not nested inside long-desc check
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  # Verify independent fetch + comparison for short description
  assert_output --partial '_current_short'
  assert_output --partial '_desired_short'
}

@test "entrypoint.sh warns on short-description update failure" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  # The short-description branch must log a warning on curl failure, matching
  # the pattern used by the long-description branch
  assert_output --partial "failed to update bot short description"
}
