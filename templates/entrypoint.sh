#!/bin/bash
set -euo pipefail
# Code symlinks (resolves Python shebang paths + ~/.local/bin node symlinks)
ln -sfn /opt/hermes/hermes-agent /root/.hermes/hermes-agent
ln -sfn /opt/hermes/node /root/.hermes/node
# All runtime data directories
mkdir -p /root/.hermes/{cron,sessions,logs,pairing,hooks,image_cache,audio_cache,memories,whatsapp/session}
# Seed default config files on first deploy (never overwrite user customizations)
for f in .env config.yaml SOUL.md; do
  if [[ ! -f /root/.hermes/$f ]] && [[ -f /opt/hermes/defaults/$f ]]; then
    cp /opt/hermes/defaults/$f /root/.hermes/$f
  fi
done
if [[ ! -d /root/.hermes/skills ]] && [[ -d /opt/hermes/defaults/skills ]]; then
  cp -r /opt/hermes/defaults/skills /root/.hermes/skills
fi
# Seed Hermes auth state on first deploy when an OAuth-backed provider is configured.
if [[ -n "${HERMES_AUTH_JSON_B64:-}" ]] && [[ ! -f /root/.hermes/auth.json ]]; then
  umask 077
  printf '%s' "${HERMES_AUTH_JSON_B64}" | base64 -d > /root/.hermes/auth.json
  chmod 600 /root/.hermes/auth.json
fi
if [[ -n "${HERMES_ANTHROPIC_OAUTH_JSON_B64:-}" ]] && [[ ! -f /root/.hermes/.anthropic_oauth.json ]]; then
  umask 077
  printf '%s' "${HERMES_ANTHROPIC_OAUTH_JSON_B64}" | base64 -d > /root/.hermes/.anthropic_oauth.json
  chmod 600 /root/.hermes/.anthropic_oauth.json
fi
# Bridge Fly secrets into /root/.hermes/.env on every boot (not just first deploy)
for var in OPENROUTER_API_KEY LLM_MODEL LLM_BASE_URL LLM_API_KEY NOUS_API_KEY \
  HERMES_REASONING_EFFORT \
  HERMES_STT_PROVIDER HERMES_STT_MODEL \
  TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS DISCORD_BOT_TOKEN DISCORD_ALLOWED_USERS \
  HERMES_APP_NAME GATEWAY_ALLOW_ALL_USERS TELEGRAM_HOME_CHANNEL; do
  val="${!var:-}"
  if [[ -n "$val" ]]; then
    sed -i "/^${var}=/d" /root/.hermes/.env
    printf '%s=%s\n' "$var" "$val" >>/root/.hermes/.env
  fi
done
# Auto-configure Telegram bot description on boot (never block startup)
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  (
    _app="${HERMES_APP_NAME:-hermes}"
    _desired_desc="Hermes AI Agent (${_app}) — Your AI assistant powered by Hermes on Fly.io"
    _desired_short="${_app} — Hermes AI Agent"
    # Fetch current long description
    _current_desc="$(curl -sf --max-time 5 \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMyDescription" 2>/dev/null \
      | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    # Fetch current short description independently
    _current_short="$(curl -sf --max-time 5 \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMyShortDescription" 2>/dev/null \
      | sed -n 's/.*"short_description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    # Reconcile long description
    if [[ "$_current_desc" != "$_desired_desc" ]]; then
      if ! curl -sf --max-time 5 \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyDescription" \
        --data-urlencode "description=${_desired_desc}" >/dev/null 2>&1; then
        echo "[hermes] Warning: failed to update bot description" >&2
      fi
    fi
    # Reconcile short description independently
    if [[ "$_current_short" != "$_desired_short" ]]; then
      if ! curl -sf --max-time 5 \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyShortDescription" \
        --data-urlencode "short_description=${_desired_short}" >/dev/null 2>&1; then
        echo "[hermes] Warning: failed to update bot short description" >&2
      fi
    fi
  ) || true
fi
# Patch config.yaml model settings from deploy secrets on every boot.
python3 - <<'PYEOF'
import os
from pathlib import Path

config_path = Path('/root/.hermes/config.yaml')
if not config_path.exists():
    raise SystemExit(0)

lines = config_path.read_text(encoding='utf-8').splitlines()
model_default = os.environ.get('LLM_MODEL', '').strip()
model_provider = os.environ.get('HERMES_LLM_PROVIDER', '').strip()
stt_provider = os.environ.get('HERMES_STT_PROVIDER', '').strip()
stt_model = os.environ.get('HERMES_STT_MODEL', '').strip()

if not model_default and not model_provider and not stt_provider and not stt_model:
    raise SystemExit(0)

def upsert(section_lines, key, value, indent='  '):
    if not value:
        return section_lines
    rendered = []
    updated = False
    for line in section_lines:
        if line.startswith(f'{indent}{key}:'):
            rendered.append(f'{indent}{key}: "{value}"')
            updated = True
        else:
            rendered.append(line)
    if not updated:
        rendered.append(f'{indent}{key}: "{value}"')
    return rendered

def upsert_top_level_section(lines, section_name, values):
    if not any(values.values()):
        return lines

    section_index = next((i for i, line in enumerate(lines) if line.strip() == f'{section_name}:'), None)
    if section_index is None:
        if lines and lines[-1].strip():
            lines = lines + ['']
        lines = lines + [f'{section_name}:']
        section_index = len(lines) - 1

    section_start = section_index + 1
    section_end = section_start
    while section_end < len(lines):
        line = lines[section_end]
        if line and not line.startswith(' '):
            break
        section_end += 1

    section = lines[section_start:section_end]
    for key, value in values.items():
        section = upsert(section, key, value)
    return lines[:section_start] + section + lines[section_end:]

lines = upsert_top_level_section(lines, 'model', {
    'default': model_default,
    'provider': model_provider,
})
lines = upsert_top_level_section(lines, 'stt', {
    'provider': stt_provider,
    'model': stt_model,
})
config_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PYEOF
# Clear rate limit entries for already-approved users on every boot
if [[ -f /root/.hermes/pairing/_rate_limits.json ]]; then
  python3 - <<'PYEOF'
import json, os, glob
rate_file = '/root/.hermes/pairing/_rate_limits.json'
approved_ids = set()
for af in glob.glob('/root/.hermes/pairing/*-approved.json'):
    platform = os.path.basename(af).replace('-approved.json', '')
    try:
        data = json.load(open(af))
        for uid in data.keys():
            approved_ids.add(f'{platform}:{uid}')
    except Exception:
        pass
try:
    limits = json.load(open(rate_file))
    cleaned = {k: v for k, v in limits.items() if k not in approved_ids}
    if cleaned != limits:
        json.dump(cleaned, open(rate_file, 'w'))
except Exception:
    pass
PYEOF
fi
# Pre-seed Telegram approved users on first boot only (skip pairing prompt for configured users)
if [[ -n "${TELEGRAM_ALLOWED_USERS:-}" ]] \
  && [[ ! -f /root/.hermes/pairing/telegram-approved.json ]]; then
  python3 - <<'PYEOF'
import json, os, time
approved_file = '/root/.hermes/pairing/telegram-approved.json'
users_raw = os.environ.get('TELEGRAM_ALLOWED_USERS', '')
entries = {}
for uid in users_raw.split(','):
    uid = uid.strip()
    if uid.isdigit():
        entries[uid] = {"user_name": "auto-approved", "approved_at": time.time()}
if entries:
    os.makedirs('/root/.hermes/pairing', exist_ok=True)
    json.dump(entries, open(approved_file, 'w'))
PYEOF
fi
# Write deploy provenance manifest on every boot (idempotent — latest config always wins)
python3 - <<'PYEOF'
import os, json
from datetime import datetime, timezone
_manifest = {
    'hermes_fly_version': os.environ.get('HERMES_FLY_VERSION', ''),
    'hermes_agent_ref': os.environ.get('HERMES_AGENT_REF', ''),
    'deploy_channel': os.environ.get('HERMES_DEPLOY_CHANNEL', 'stable'),
    'compatibility_policy_version': os.environ.get('HERMES_COMPAT_POLICY', ''),
    'reasoning_effort': os.environ.get('HERMES_REASONING_EFFORT', ''),
    'llm_provider': os.environ.get('HERMES_LLM_PROVIDER', ''),
    'llm_model': os.environ.get('LLM_MODEL', ''),
    'written_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
with open('/root/.hermes/deploy-manifest.json', 'w') as _fh:
    json.dump(_manifest, _fh, indent=2)
PYEOF
# Start hermes gateway
exec /opt/hermes/hermes-agent/venv/bin/hermes gateway run "$@"
