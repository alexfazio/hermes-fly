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

@test "templates/Dockerfile.template contains HERMES_VERSION placeholder" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_success
  assert_output --partial "{{HERMES_VERSION}}"
  assert_output --partial "FROM python:3.11-slim"
  assert_output --partial "ENTRYPOINT"
}

@test "templates/Dockerfile.template runs the Hermes WhatsApp bridge patch script" {
  run cat "${PROJECT_ROOT}/templates/Dockerfile.template"
  assert_success
  assert_output --partial "COPY patch-hermes-gateway.py /tmp/hermes-fly-patch-hermes-gateway.py"
  assert_output --partial "hermes-fly-patch-hermes-gateway.py /opt/hermes/hermes-agent"
  assert_output --partial "COPY patch-whatsapp-bridge.py /tmp/hermes-fly-patch-whatsapp-bridge.py"
  assert_output --partial "scripts/whatsapp-bridge/bridge.js"
  assert_output --partial "hermes-fly-patch-whatsapp-bridge.py"
}

@test "templates/patch-hermes-gateway.py patches typing metadata compatibility" {
  run cat "${PROJECT_ROOT}/templates/patch-hermes-gateway.py"
  assert_success
  assert_output --partial "metadata=None"
  assert_output --partial "await self.send_typing(chat_id, metadata=metadata)"
  assert_output --partial "signal send_typing signature"
}

@test "templates/patch-whatsapp-bridge.py contains self-chat diagnostics markers" {
  run cat "${PROJECT_ROOT}/templates/patch-whatsapp-bridge.py"
  assert_success
  assert_output --partial "messages.upsert.skipped"
  assert_output --partial "messages.upsert.accepted"
  assert_output --partial "messages.poll.drained"
}

@test "templates/fly.toml.template contains all placeholders" {
  run cat "${PROJECT_ROOT}/templates/fly.toml.template"
  assert_success
  assert_output --partial "{{APP_NAME}}"
  assert_output --partial "{{REGION}}"
  assert_output --partial "{{VM_SIZE}}"
  assert_output --partial "{{VOLUME_NAME}}"
}

@test "templates/fly.toml.template does not declare an HTTP service for worker deployments" {
  run cat "${PROJECT_ROOT}/templates/fly.toml.template"
  refute_output --partial "[http_service]"
  refute_output --partial "internal_port = 8080"
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
  assert_output --partial "exec /gateway-supervisor.sh"
}

@test "templates/gateway-supervisor.sh exists and restarts the gateway child on USR1" {
  run cat "${PROJECT_ROOT}/templates/gateway-supervisor.sh"
  assert_success
  assert_output --partial "gateway-supervisor.pid"
  assert_output --partial "trap request_restart USR1"
  assert_output --partial "hermes gateway run --replace"
  assert_output --partial "/root/.hermes/.env"
  assert_output --partial "self-chat-identity.json"
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

@test "entrypoint.sh seeds Hermes auth.json from HERMES_AUTH_JSON_B64 when missing" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_AUTH_JSON_B64"
  assert_output --partial "/root/.hermes/auth.json"
  assert_output --partial "base64"
}

@test "entrypoint.sh seeds Anthropic OAuth credentials from HERMES_ANTHROPIC_OAUTH_JSON_B64 when missing" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_ANTHROPIC_OAUTH_JSON_B64"
  assert_output --partial "/root/.hermes/.anthropic_oauth.json"
  assert_output --partial "base64"
}

@test "entrypoint.sh mirrors Anthropic OAuth credentials into Claude Code format for Hermes CLI detection" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "/root/.claude/.credentials.json"
  assert_output --partial "claudeAiOauth"
  assert_output --partial ".anthropic_oauth.json"
}

@test "entrypoint.sh bridges all messaging and LLM secrets" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "TELEGRAM_BOT_TOKEN"
  assert_output --partial "DISCORD_BOT_TOKEN"
  assert_output --partial "GLM_API_KEY"
  assert_output --partial "GLM_BASE_URL"
}

@test "entrypoint.sh stages WhatsApp until a session exists" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_FLY_WHATSAPP_PENDING"
  assert_output --partial "HERMES_FLY_WHATSAPP_MODE"
  assert_output --partial "HERMES_FLY_WHATSAPP_ALLOWED_USERS"
  assert_output --partial "find /root/.hermes/whatsapp/session -mindepth 1"
}

@test "entrypoint.sh loads persisted WhatsApp self-chat identity from the volume" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "self-chat-identity.json"
  assert_output --partial "HERMES_FLY_WHATSAPP_SELF_CHAT_NUMBER"
  assert_output --partial "export WHATSAPP_ENABLED=true"
  assert_output --partial 'export WHATSAPP_MODE="${WHATSAPP_MODE:-self-chat}"'
  assert_output --partial 'export WHATSAPP_HOME_CONTACT="${HERMES_FLY_WHATSAPP_SELF_CHAT_NUMBER}"'
}

@test "entrypoint.sh patches config.yaml model from LLM_MODEL" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "LLM_MODEL"
  assert_output --partial "config.yaml"
  assert_output --partial "python3"
}

@test "entrypoint.sh patches config.yaml provider from HERMES_LLM_PROVIDER" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_LLM_PROVIDER"
  assert_output --partial "provider"
  assert_output --partial "config.yaml"
}

@test "entrypoint.sh clears rate limits for approved users" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "_rate_limits.json"
  assert_output --partial "approved.json"
}

@test "entrypoint.sh updates config.yaml through a Python patch script" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "def upsert"
  assert_output --partial "model_provider"
}

# --- Entrypoint auto-approve ---

@test "entrypoint.sh pre-seeds telegram-approved.json from TELEGRAM_ALLOWED_USERS" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "telegram-approved.json"
  assert_output --partial "auto-approved"
  assert_output --partial "TELEGRAM_ALLOWED_USERS"
}

@test "entrypoint.sh pre-seeds whatsapp-approved.json from the detected self-chat identity" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "whatsapp-approved.json"
  assert_output --partial "self_lid"
  assert_output --partial "auto-approved"
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

# --- Reasoning effort env bridge (AC-06) ---

@test "entrypoint.sh bridges HERMES_REASONING_EFFORT into .env (AC-06)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_REASONING_EFFORT"
}

@test "entrypoint.sh bridges STT provider and model into .env for runtime bootstrap" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_STT_PROVIDER"
  assert_output --partial "HERMES_STT_MODEL"
}

@test "entrypoint.sh bridges HERMES_ZAI_THINKING into .env for runtime bootstrap" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_ZAI_THINKING"
}

@test "sitecustomize.py disables Z.AI thinking when configured" {
  run cat "${PROJECT_ROOT}/templates/sitecustomize.py"
  assert_success
  assert_output --partial "HERMES_ZAI_THINKING"
  assert_output --partial "thinking"
  assert_output --partial "disabled"
  assert_output --partial "run_agent"
}

@test "entrypoint.sh patches config.yaml stt settings from deploy secrets" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "stt_provider"
  assert_output --partial "stt_model"
  assert_output --partial "upsert_top_level_section(lines, 'stt'"
}

# --- PR-04: Runtime provenance manifest ---

@test "entrypoint.sh writes deploy-manifest.json on boot (PR-04)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "deploy-manifest.json"
}

@test "entrypoint.sh manifest write includes hermes_fly_version key (PR-04)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_FLY_VERSION"
}

@test "entrypoint.sh manifest write includes hermes_agent_ref key (PR-04)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_AGENT_REF"
}

@test "entrypoint.sh manifest write includes deploy_channel key (PR-04)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "deploy_channel"
}

@test "entrypoint.sh manifest write is idempotent across restarts — no first-boot guard (PR-04)" {
  # Idempotent: manifest must be written on every boot, not just first boot.
  # Verify deploy-manifest.json write is NOT guarded by [[ ! -f ... ]].
  run grep -c "! -f.*deploy-manifest.json" "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_failure
}

@test "entrypoint.sh manifest write includes reasoning_effort key (PR-04)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "HERMES_REASONING_EFFORT"
}

# --- REVIEW_1: schema alignment + safe serialization ---

@test "entrypoint.sh manifest uses compatibility_policy_version key (REVIEW_1)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "compatibility_policy_version"
}

@test "entrypoint.sh manifest does NOT contain bare compat_policy_version key (REVIEW_1)" {
  # The old short key must be gone; only the full name is valid
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  refute_output --partial '"compat_policy_version"'
}

@test "entrypoint.sh manifest includes llm_provider field (REVIEW_1)" {
  run cat "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "llm_provider"
}

@test "entrypoint.sh manifest write uses python3 json.dump for safe serialization (REVIEW_1)" {
  # The manifest writer must use python3 + json.dump (not printf) to safely encode
  # arbitrary string values including quotes and backslashes.
  # The manifest comment must be immediately followed by a python3 heredoc, not a printf block.
  run grep -A 3 "Write deploy provenance manifest" "${PROJECT_ROOT}/templates/entrypoint.sh"
  assert_success
  assert_output --partial "python3"
}

@test "hermes-fly deploy --help mentions --channel (PR-05)" {
  run bash "${PROJECT_ROOT}/hermes-fly" deploy --help
  assert_success
  assert_output --partial "--channel"
}
