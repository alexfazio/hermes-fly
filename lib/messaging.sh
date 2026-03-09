#!/usr/bin/env bash
# lib/messaging.sh — Telegram setup wizard
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source ui.sh for prompts ---
_MESSAGING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v ui_ask &>/dev/null; then
  # shellcheck source=./ui.sh disable=SC1091
  source "${_MESSAGING_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi

# --- Validation ---

# Validate Telegram bot token format.
# Valid format: digits, colon, then alphanumeric/hyphen/underscore chars.
# Example: 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
# Returns 0 if valid, 1 if not.
messaging_validate_telegram_token() {
  local token="${1:-}"
  if [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    return 0
  fi
  return 1
}

# Call Telegram getMe to validate token and get bot identity.
# Sets DEPLOY_TELEGRAM_BOT_USERNAME and DEPLOY_TELEGRAM_BOT_NAME on success.
# Returns 0 on success, 1 if curl fails or response ok=false.
messaging_validate_telegram_token_api() {
  local token="$1"
  local response
  response="$(curl -sf --max-time 10 "https://api.telegram.org/bot${token}/getMe" 2>/dev/null)" || return 1
  printf '%s' "$response" | grep -q '"ok":true' || return 1
  local username
  username="$(printf '%s' "$response" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [[ -z "$username" ]] && return 1
  DEPLOY_TELEGRAM_BOT_USERNAME="$username"
  DEPLOY_TELEGRAM_BOT_NAME="$(printf '%s' "$response" | sed -n 's/.*"first_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  export DEPLOY_TELEGRAM_BOT_USERNAME DEPLOY_TELEGRAM_BOT_NAME
  return 0
}

# Validate user IDs are numeric (comma-separated).
# Empty input is valid (allow all users).
# Returns 0 if valid, 1 if any ID is non-numeric.
messaging_validate_user_ids() {
  local input="$1"
  [[ -z "$input" ]] && return 0
  local id
  local IFS=','
  for id in $input; do
    id="$(printf '%s' "$id" | tr -d '[:space:]')"
    if [[ -n "$id" ]] && ! [[ "$id" =~ ^[0-9]+$ ]]; then
      return 1
    fi
  done
  return 0
}

# --- Setup menu ---

# Present a choice menu for messaging platform selection.
# Reads user choice from stdin.
# Echoes: "telegram" or "skip"
# Returns 0.
messaging_setup_menu() {
  printf '\nWant to chat with your agent via a messaging app?\n' >&2
  printf '  ┌───┬──────────┬──────────────────────────────────────┐\n' >&2
  printf '  │ # │ Platform │ Description                          │\n' >&2
  printf '  ├───┼──────────┼──────────────────────────────────────┤\n' >&2
  printf '  │ 1 │ Telegram │ Chat with your agent via Telegram bot│\n' >&2
  printf '  │ 2 │ Skip     │ Set this up later                    │\n' >&2
  printf '  └───┴──────────┴──────────────────────────────────────┘\n' >&2
  local choice
  while true; do
    printf 'Choice [2]: ' >&2
    IFS= read -r choice
    [[ -z "$choice" ]] && choice=2
    case "$choice" in
      1)
        echo "telegram"
        return 0
        ;;
      2)
        echo "skip"
        return 0
        ;;
      *) printf 'Invalid choice. Please enter 1 or 2.\n' >&2 ;;
    esac
  done
}

# --- Telegram setup ---

# Interactive Telegram bot setup wizard.
# Prompts for bot token and allowed user IDs.
# Sets global vars: DEPLOY_TELEGRAM_BOT_TOKEN, DEPLOY_TELEGRAM_ALLOWED_USERS
# Returns 0 on success.
messaging_setup_telegram() {
  printf '\n--- Telegram Bot Setup ---\n' >&2
  printf 'To create a Telegram bot:\n' >&2
  printf '  1. Open https://t.me/BotFather in Telegram\n' >&2
  printf '  2. Send /newbot and follow the prompts\n' >&2
  printf '  3. Copy the bot token provided\n\n' >&2

  local token
  while true; do
    ui_ask_secret 'Bot token:' token
    if ! messaging_validate_telegram_token "$token"; then
      printf 'Error: token format invalid. Expected format: 123456789:ABCdef...\n' >&2
      continue
    fi
    printf 'Verifying token with Telegram...\n' >&2
    if ! messaging_validate_telegram_token_api "$token"; then
      printf 'Error: Telegram rejected this token. Check it and try again.\n' >&2
      continue
    fi
    printf 'Found bot: @%s (%s)\n' "$DEPLOY_TELEGRAM_BOT_USERNAME" "$DEPLOY_TELEGRAM_BOT_NAME" >&2
    if ui_confirm "Continue with this bot?"; then
      break
    fi
  done

  # Access control menu
  local users="" access_choice
  while true; do
    printf '\nWho should be able to talk to this bot?\n\n' >&2
    printf '  ┌───┬──────────────────┬────────────────────────────────────────────┐\n' >&2
    printf '  │ # │ Option           │ Description                                │\n' >&2
    printf '  ├───┼──────────────────┼────────────────────────────────────────────┤\n' >&2
    printf '  │ 1 │ Only me          │ Just you — enter your Telegram user ID     │\n' >&2
    printf '  │ 2 │ Specific people  │ You and others — enter comma-separated IDs │\n' >&2
    printf '  │ 3 │ Anyone           │ No restrictions — anyone who finds the bot │\n' >&2
    printf '  └───┴──────────────────┴────────────────────────────────────────────┘\n' >&2
    printf 'Choose [1]: ' >&2
    IFS= read -r access_choice
    [[ -z "$access_choice" ]] && access_choice=1

    case "$access_choice" in
      1)
        printf '\nTo find your Telegram user ID:\n' >&2
        printf '  Open https://t.me/userinfobot — it replies with your numeric ID\n\n' >&2
        while true; do
          printf 'Your user ID: ' >&2
          IFS= read -r users
          if [[ -n "$users" ]] && messaging_validate_user_ids "$users"; then
            break
          fi
          printf 'Error: user IDs must be numeric (e.g., 123456789).\n' >&2
        done
        break
        ;;
      2)
        printf '\nTo find Telegram user IDs:\n' >&2
        printf '  Open https://t.me/userinfobot — it replies with your numeric ID\n\n' >&2
        while true; do
          printf 'User IDs (comma-separated): ' >&2
          IFS= read -r users
          if [[ -n "$users" ]] && messaging_validate_user_ids "$users"; then
            break
          fi
          printf 'Error: user IDs must be numeric (e.g., 123456789). Use commas to separate.\n' >&2
        done
        break
        ;;
      3)
        if ui_confirm "Allow anyone to use this bot? This is not recommended for most setups."; then
          DEPLOY_GATEWAY_ALLOW_ALL_USERS="true"
          export DEPLOY_GATEWAY_ALLOW_ALL_USERS
          break
        fi
        # Rejected — loop back to access menu
        ;;
      *)
        printf 'Invalid choice. Please enter 1, 2, or 3.\n' >&2
        ;;
    esac
  done

  # Home channel — auto-suggest first user ID (skip for "Anyone" mode)
  if [[ -n "$users" ]]; then
    local first_id
    first_id="$(printf '%s' "$users" | cut -d',' -f1 | tr -d '[:space:]')"
    printf '\nSet a home channel for bot status messages.\n' >&2
    if ui_confirm "Use $first_id as home channel?"; then
      DEPLOY_TELEGRAM_HOME_CHANNEL="$first_id"
      export DEPLOY_TELEGRAM_HOME_CHANNEL
    fi
  fi

  DEPLOY_TELEGRAM_BOT_TOKEN="$token"
  DEPLOY_TELEGRAM_ALLOWED_USERS="$users"
  DEPLOY_MESSAGING_PLATFORM="telegram"
  export DEPLOY_TELEGRAM_BOT_TOKEN DEPLOY_TELEGRAM_ALLOWED_USERS DEPLOY_MESSAGING_PLATFORM

  return 0
}
