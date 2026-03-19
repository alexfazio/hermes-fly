#!/bin/bash
set -euo pipefail

RUNTIME_DIR="/root/.hermes/runtime"
SUPERVISOR_PID_FILE="${RUNTIME_DIR}/gateway-supervisor.pid"
CHILD_PID_FILE="${RUNTIME_DIR}/gateway.pid"
STARTED_AT_FILE="${RUNTIME_DIR}/gateway-started-at"
RUNTIME_ENV_FILE="/root/.hermes/.env"
SELF_CHAT_STATE_FILE="/root/.hermes/whatsapp/self-chat-identity.json"

mkdir -p "${RUNTIME_DIR}"

child_pid=""
restart_requested=0
shutdown_requested=0

cleanup() {
  rm -f "${SUPERVISOR_PID_FILE}" "${CHILD_PID_FILE}"
}

clear_runtime_overrides() {
  unset WHATSAPP_ENABLED WHATSAPP_MODE WHATSAPP_ALLOWED_USERS WHATSAPP_HOME_CONTACT
  unset HERMES_FLY_WHATSAPP_SELF_CHAT_NUMBER HERMES_FLY_WHATSAPP_SELF_CHAT_JID HERMES_FLY_WHATSAPP_SELF_CHAT_LID
}

load_runtime_overrides() {
  clear_runtime_overrides

  if [[ -f "${RUNTIME_ENV_FILE}" ]]; then
    eval "$(
      python3 - <<'PYEOF'
import shlex
from pathlib import Path

env_path = Path('/root/.hermes/.env')
wanted = {'WHATSAPP_ENABLED', 'WHATSAPP_MODE', 'WHATSAPP_ALLOWED_USERS'}

for line in env_path.read_text(encoding='utf-8').splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith('#') or '=' not in line:
        continue
    key, value = line.split('=', 1)
    key = key.strip()
    if key in wanted | {'WHATSAPP_HOME_CONTACT'}:
        print(f"export {key}={shlex.quote(value)}")
PYEOF
    )"
  fi

  if [[ -f "${SELF_CHAT_STATE_FILE}" ]]; then
    eval "$(
      python3 - <<'PYEOF'
import json
import shlex
from pathlib import Path

state_path = Path('/root/.hermes/whatsapp/self-chat-identity.json')
try:
    state = json.loads(state_path.read_text(encoding='utf-8'))
except Exception:
    raise SystemExit(0)

self_number = str(state.get('self_number', '')).strip()
self_jid = str(state.get('self_jid', '')).strip()
self_lid = str(state.get('self_lid', '')).strip()

mapping = {
    'HERMES_FLY_WHATSAPP_SELF_CHAT_NUMBER': self_number,
    'HERMES_FLY_WHATSAPP_SELF_CHAT_JID': self_jid,
    'HERMES_FLY_WHATSAPP_SELF_CHAT_LID': self_lid,
}
for key, value in mapping.items():
    if value:
        print(f"export {key}={shlex.quote(value)}")

if self_number:
    print("export WHATSAPP_ENABLED=true")
    print("export WHATSAPP_MODE=self-chat")
    print(f"export WHATSAPP_ALLOWED_USERS={shlex.quote(self_number)}")
    print(f"export WHATSAPP_HOME_CONTACT={shlex.quote(self_number)}")
PYEOF
    )"
  fi
}

request_restart() {
  restart_requested=1
  if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" 2>/dev/null; then
    kill -TERM "${child_pid}" 2>/dev/null || true
  fi
}

request_shutdown() {
  shutdown_requested=1
  if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" 2>/dev/null; then
    kill -TERM "${child_pid}" 2>/dev/null || true
  fi
}

start_gateway() {
  printf '%s\n' "$$" > "${SUPERVISOR_PID_FILE}"
  load_runtime_overrides
  cd /root/.hermes
  /opt/hermes/hermes-agent/venv/bin/hermes gateway run --replace "$@" &
  child_pid="$!"
  printf '%s\n' "${child_pid}" > "${CHILD_PID_FILE}"
  date +%s%N > "${STARTED_AT_FILE}"
}

trap cleanup EXIT
trap request_restart USR1
trap request_shutdown TERM INT

while true; do
  start_gateway "$@"

  set +e
  wait "${child_pid}"
  child_status=$?
  set -e

  rm -f "${CHILD_PID_FILE}"

  if [[ "${shutdown_requested}" -eq 1 ]]; then
    exit "${child_status}"
  fi

  if [[ "${restart_requested}" -eq 1 ]]; then
    restart_requested=0
    child_pid=""
    continue
  fi

  exit "${child_status}"
done
