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
# Bridge Fly secrets into /root/.hermes/.env on every boot (not just first deploy)
for var in OPENROUTER_API_KEY LLM_MODEL LLM_BASE_URL LLM_API_KEY NOUS_API_KEY \
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
# Patch config.yaml model.default from LLM_MODEL on every boot
if [[ -n "${LLM_MODEL:-}" ]]; then
  _safe_model="${LLM_MODEL//|/\\|}"
  sed -i "s|^  default: \".*\"|  default: \"${_safe_model}\"|" /root/.hermes/config.yaml
fi
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
# Start hermes gateway
exec /opt/hermes/hermes-agent/venv/bin/hermes gateway "$@"
