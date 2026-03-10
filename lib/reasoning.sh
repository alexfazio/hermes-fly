#!/usr/bin/env bash
# lib/reasoning.sh — Reasoning effort compatibility gating and persistence
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# --- Source dependencies ---
_REASONING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${EXIT_SUCCESS+x}" ]]; then
  source "${_REASONING_SCRIPT_DIR}/ui.sh" 2>/dev/null || true
fi

# ==========================================================================
# Bundled compatibility snapshot (JSON)
#
# Source-of-truth: data/reasoning-snapshot.json
# Format: {"schema_version","policy_version","families":{...}}
# Per-family: {"allowed_efforts":[],"default":"..."}
#
# Loading:
#   - Snapshot is loaded at source time (_reasoning_load_snapshot runs when
#     this file is sourced). Validation warnings may appear on stderr for
#     any command that sources this module, including non-deploy commands
#     like 'hermes-fly help' or 'hermes-fly --version'.
#   - On validation failure, the snapshot is disabled and conservative
#     fallback defaults are used (no hard crash).
#
# Validation:
#   - All-or-nothing: a single malformed family disables the entire snapshot.
#     This is intentional — safety over partial tolerance, deterministic fallback.
#
# Policy:
#   - xhigh and none are excluded from first-run setup UX
#   - Unknown families default to "medium"
#   - GPT-5 family uses conservative cross-provider intersection (low|medium|high)
#     Note: "minimal" is excluded because Azure does not support it (plan §Q4)
#   - GPT-5-pro is high-only
#   - Reasoning capability is derived from snapshot family presence,
#     not inferred from model name alone (plan line 65)
#
# Exit codes (reasoning_prompt_effort):
#   0 — success (valid selection made)
#   1 — cancel/EOF (user closed input)
#   2 — retry exhaustion (max invalid attempts exceeded)
#   Callers must distinguish 1 and 2 for different control flow:
#   deploy.sh falls back on 1 (EOF), aborts on 2 (exhaustion).
# ==========================================================================

_REASONING_SNAPSHOT_FILE="${_REASONING_SCRIPT_DIR}/../data/reasoning-snapshot.json"
_REASONING_SNAPSHOT_RAW=""
REASONING_SNAPSHOT_VERSION=""

# --------------------------------------------------------------------------
# _reasoning_load_snapshot — load and parse the JSON snapshot file
# Sets _REASONING_SNAPSHOT_RAW and REASONING_SNAPSHOT_VERSION.
# Safe to call multiple times (idempotent).
# Policy: all-or-nothing validation — a single malformed family disables
# the entire snapshot (safety over partial tolerance).
# --------------------------------------------------------------------------
_reasoning_load_snapshot() {
  local file="${_REASONING_SNAPSHOT_FILE:-}"
  if [[ -n "$file" ]] && [[ -f "$file" ]]; then
    local raw
    raw="$(cat "$file")"

    # Validate required top-level keys
    if ! printf '%s\n' "$raw" | grep -q '"schema_version"'; then
      printf 'Warning: reasoning snapshot missing schema_version, disabling.\n' >&2
      _REASONING_SNAPSHOT_RAW=""
      REASONING_SNAPSHOT_VERSION=""
      return
    fi
    if ! printf '%s\n' "$raw" | grep -q '"policy_version"'; then
      printf 'Warning: reasoning snapshot missing policy_version, disabling.\n' >&2
      _REASONING_SNAPSHOT_RAW=""
      REASONING_SNAPSHOT_VERSION=""
      return
    fi
    if ! printf '%s\n' "$raw" | grep -q '"families"'; then
      printf 'Warning: reasoning snapshot missing families, disabling.\n' >&2
      _REASONING_SNAPSHOT_RAW=""
      REASONING_SNAPSHOT_VERSION=""
      return
    fi

    # Validate each family block has required keys and flat structure.
    # Extract family names scoped to the "families" block only, preventing
    # non-family top-level object keys (e.g., "metadata") from being
    # misclassified as families. Uses awk brace-matching to isolate the block.
    # The || true guards prevent grep exit 1 from crashing under set -euo pipefail
    # when the families block is empty or has no object-valued children.
    local families_block
    families_block="$(printf '%s\n' "$raw" | awk '
      /"families"[[:space:]]*:/ { found=1; depth=0 }
      found {
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          if (c == "}") {
            depth--
            if (depth == 0) { print; found=0; next }
          }
        }
        print
      }')" || true

    local family_names
    family_names="$(printf '%s\n' "$families_block" | grep -oE '"[a-zA-Z0-9_-]+"[[:space:]]*:[[:space:]]*\{' \
      | grep -v '"families"' \
      | sed 's/[[:space:]]*:.*//' | tr -d '"')" || true

    # Empty families: disable snapshot with warning (not a shell crash)
    if [[ -z "$family_names" ]]; then
      printf 'Warning: reasoning snapshot has no family definitions, disabling.\n' >&2
      _REASONING_SNAPSHOT_RAW=""
      REASONING_SNAPSHOT_VERSION=""
      return 0
    fi

    # Newline-safe iteration (avoids word-splitting pitfalls with unquoted $family_names)
    local fname
    while IFS= read -r fname; do
      [[ -z "$fname" ]] && continue
      local block
      block="$(printf '%s\n' "$raw" | sed -n "/\"${fname}\"/,/}/p")"
      if ! printf '%s\n' "$block" | grep -q '"allowed_efforts"'; then
        printf 'Warning: reasoning snapshot family "%s" missing allowed_efforts, disabling.\n' "$fname" >&2
        _REASONING_SNAPSHOT_RAW=""
        REASONING_SNAPSHOT_VERSION=""
        return
      fi
      if ! printf '%s\n' "$block" | grep -q '"default"'; then
        printf 'Warning: reasoning snapshot family "%s" missing default, disabling.\n' "$fname" >&2
        _REASONING_SNAPSHOT_RAW=""
        REASONING_SNAPSHOT_VERSION=""
        return
      fi
    done <<< "$family_names"

    _REASONING_SNAPSHOT_RAW="$raw"
    REASONING_SNAPSHOT_VERSION="$(printf '%s\n' "$_REASONING_SNAPSHOT_RAW" \
      | grep '"policy_version"' \
      | sed 's/.*"policy_version"[[:space:]]*:[[:space:]]*"//; s/".*//')"
  else
    _REASONING_SNAPSHOT_RAW=""
    REASONING_SNAPSHOT_VERSION=""
  fi
}

# Load snapshot at source time
_reasoning_load_snapshot

# --------------------------------------------------------------------------
# reasoning_normalize_family MODEL_ID — normalize model ID to family key
# Args: model_id (e.g., "openai/gpt-5-mini", "anthropic/claude-sonnet-4")
# Returns: family key to stdout (e.g., "gpt-5", "gpt-5-pro", "unknown")
#
# DUAL-UPDATE REQUIREMENT: When adding a new family, update BOTH:
#   1. The case patterns below (maps model names → family key)
#   2. data/reasoning-snapshot.json (defines allowed efforts and default)
# Families handled: gpt-5, gpt-5-pro
# --------------------------------------------------------------------------
reasoning_normalize_family() {
  local model_id="$1"

  # Strip provider prefix (everything before first /)
  local model_name
  if [[ "$model_id" == */* ]]; then
    model_name="${model_id#*/}"
  else
    model_name="$model_id"
  fi

  # Strip colon variants (:free, :nitro, etc.)
  model_name="${model_name%%:*}"

  # Match families (order matters: most specific first)
  case "$model_name" in
    gpt-5-pro|gpt-5-pro-*)
      printf '%s' "gpt-5-pro"
      ;;
    gpt-5-mini|gpt-5-mini-*|gpt-5-nano|gpt-5-nano-*|gpt-5|gpt-5-[0-9]*|gpt-5.[0-9]*|gpt-5-codex|gpt-5-codex-*)
      printf '%s' "gpt-5"
      ;;
    *)
      printf '%s' "unknown"
      ;;
  esac
}

# --------------------------------------------------------------------------
# reasoning_get_allowed_efforts FAMILY — return allowed efforts for family
# Args: family key from reasoning_normalize_family
# Returns: pipe-separated effort list to stdout
# Reads from bundled JSON snapshot; falls back to conservative default.
# --------------------------------------------------------------------------
reasoning_get_allowed_efforts() {
  local family="$1"

  # Snapshot-derived lookup
  # NOTE: The sed parser assumes a flat JSON structure per family (no nested objects).
  # It terminates at the first '}' after the family key. If the snapshot gains nested
  # objects, this parser must be updated. See data/reasoning-snapshot.json.
  if [[ -n "${_REASONING_SNAPSHOT_RAW:-}" ]]; then
    local block
    block="$(printf '%s\n' "$_REASONING_SNAPSHOT_RAW" | sed -n "/\"${family}\"/,/}/p")"
    if [[ -n "$block" ]]; then
      local efforts
      efforts="$(printf '%s\n' "$block" | grep '"allowed_efforts"' \
        | sed 's/.*\[//; s/\].*//; s/"//g; s/[[:space:]]//g; s/,/|/g')"
      if [[ -n "$efforts" ]]; then
        printf '%s' "$efforts"
        return
      fi
    fi
  fi

  # Fallback for unknown/missing family: conservative default
  printf '%s' "low|medium|high"
}

# --------------------------------------------------------------------------
# reasoning_get_default FAMILY — return default effort for family
# Args: family key from reasoning_normalize_family
# Returns: default effort to stdout
# Reads from bundled JSON snapshot; falls back to "medium".
# --------------------------------------------------------------------------
reasoning_get_default() {
  local family="$1"

  # Snapshot-derived lookup
  if [[ -n "${_REASONING_SNAPSHOT_RAW:-}" ]]; then
    local block
    block="$(printf '%s\n' "$_REASONING_SNAPSHOT_RAW" | sed -n "/\"${family}\"/,/}/p")"
    if [[ -n "$block" ]]; then
      local default_val
      default_val="$(printf '%s\n' "$block" | grep '"default"' \
        | sed 's/.*"default"[[:space:]]*:[[:space:]]*"//; s/".*//')"
      if [[ -n "$default_val" ]]; then
        printf '%s' "$default_val"
        return
      fi
    fi
  fi

  # Fallback: conservative default
  printf '%s' "medium"
}

# --------------------------------------------------------------------------
# reasoning_validate_effort FAMILY EFFORT — check if effort is valid for family
# Args: family key, effort value
# Returns: 0 if valid, 1 if invalid
# --------------------------------------------------------------------------
reasoning_validate_effort() {
  local family="$1"
  local effort="$2"

  local allowed
  allowed="$(reasoning_get_allowed_efforts "$family")"

  # Check if effort appears in the pipe-separated allowed list
  local IFS='|'
  local val
  for val in $allowed; do
    if [[ "$val" == "$effort" ]]; then
      return 0
    fi
  done
  return 1
}

# --------------------------------------------------------------------------
# reasoning_model_supports_reasoning MODEL_ID — check if model has reasoning
# Derives capability from snapshot family presence (not hardcoded).
# Returns 0 if model's family is defined in the snapshot, 1 otherwise.
# Non-reasoning models (Anthropic, Google, etc.) skip the reasoning prompt.
# --------------------------------------------------------------------------
reasoning_model_supports_reasoning() {
  local model_id="$1"
  local family
  family="$(reasoning_normalize_family "$model_id")"

  # Family "unknown" is never in the snapshot
  [[ "$family" == "unknown" ]] && return 1

  # Check if family is defined in the loaded snapshot
  if [[ -n "${_REASONING_SNAPSHOT_RAW:-}" ]]; then
    if printf '%s\n' "$_REASONING_SNAPSHOT_RAW" | grep -q "\"${family}\"[[:space:]]*:"; then
      return 0
    fi
    return 1
  fi

  # No snapshot loaded: conservative default — assume no reasoning support
  return 1
}

# Maximum retry attempts for interactive reasoning effort prompt.
# Referenced by tests to avoid hardcoding attempt counts.
REASONING_MAX_PROMPT_ATTEMPTS=3

# --------------------------------------------------------------------------
# reasoning_prompt_effort MODEL_ID — interactive reasoning effort selection
# Shows menu with only valid options for the model's family.
# Returns: selected effort value to stdout
# Exit codes:
#   0 — success (valid selection made)
#   1 — cancel/EOF (user closed input)
#   2 — retry exhaustion (max invalid attempts exceeded)
# --------------------------------------------------------------------------
reasoning_prompt_effort() {
  local model_id="$1"

  local family
  family="$(reasoning_normalize_family "$model_id")"

  local allowed
  allowed="$(reasoning_get_allowed_efforts "$family")"

  local default_effort
  default_effort="$(reasoning_get_default "$family")"

  # Build menu from allowed efforts
  local options=()
  local IFS='|'
  for val in $allowed; do
    options+=("$val")
  done
  unset IFS

  local num_options=${#options[@]}

  # Single option: auto-select
  if [[ "$num_options" -eq 1 ]]; then
    printf '%s\n' "Reasoning effort for ${model_id}: ${options[0]} (only supported level)" >&2
    printf '%s' "${options[0]}"
    return 0
  fi

  # Multi-option menu with retry loop
  local default_idx=1
  local i marker choice
  local attempt=0
  while [[ "$attempt" -lt "$REASONING_MAX_PROMPT_ATTEMPTS" ]]; do
    # Render menu (compute default_idx inline during display)
    printf '\nSelect reasoning effort for %s:\n' "$model_id" >&2
    i=1
    for val in "${options[@]}"; do
      marker=""
      if [[ "$val" == "$default_effort" ]]; then
        marker=" (recommended)"
        default_idx=$i
      fi
      printf '  %d) %s%s\n' "$i" "$val" "$marker" >&2
      ((i++))
    done

    printf 'Choice [%d]: ' "$default_idx" >&2
    if ! IFS= read -r choice; then
      # EOF — user closed input
      return 1
    fi
    [[ -z "$choice" ]] && choice="$default_idx"

    # Validate numeric and in range
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$num_options" ]]; then
      printf '%s' "${options[$((choice - 1))]}"
      return 0
    fi

    ((attempt++))
    if [[ "$attempt" -lt "$REASONING_MAX_PROMPT_ATTEMPTS" ]]; then
      printf 'Invalid choice. Please enter a number between 1 and %d.\n' "$num_options" >&2
    else
      printf 'Too many invalid attempts.\n' >&2
    fi
  done

  # Retry exhaustion — distinct from EOF/cancel (exit code 1)
  return 2
}
