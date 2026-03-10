#!/usr/bin/env bats
# tests/reasoning.bats — TDD tests for lib/reasoning.sh reasoning effort gating

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/reasoning.sh"
}

teardown() {
  _common_teardown
}

# ==========================================================================
# JSON snapshot file (REVIEW_1: No JSON snapshot file)
# ==========================================================================

@test "data/reasoning-snapshot.json exists" {
  assert [ -f "${PROJECT_ROOT}/data/reasoning-snapshot.json" ]
}

@test "snapshot JSON has required top-level keys" {
  run cat "${PROJECT_ROOT}/data/reasoning-snapshot.json"
  assert_success
  assert_output --partial '"schema_version"'
  assert_output --partial '"policy_version"'
  assert_output --partial '"families"'
}

@test "snapshot JSON families have required keys (allowed_efforts, default)" {
  run cat "${PROJECT_ROOT}/data/reasoning-snapshot.json"
  assert_success
  assert_output --partial '"allowed_efforts"'
  assert_output --partial '"default"'
}

@test "REASONING_SNAPSHOT_VERSION matches JSON policy_version" {
  local json_version
  json_version="$(grep '"policy_version"' "${PROJECT_ROOT}/data/reasoning-snapshot.json" \
    | sed 's/.*"policy_version"[[:space:]]*:[[:space:]]*"//; s/".*//')"
  [[ "$REASONING_SNAPSHOT_VERSION" == "$json_version" ]]
}

@test "reasoning_get_allowed_efforts reads from snapshot, not hardcoded" {
  # Create a test snapshot with DIFFERENT values than the real one
  local test_snapshot="${BATS_TEST_TMPDIR}/test-snapshot.json"
  cat >"$test_snapshot" <<'EOF'
{
  "schema_version": "1",
  "policy_version": "0.0.1-test",
  "families": {
    "gpt-5": {
      "allowed_efforts": ["medium", "high"],
      "default": "high"
    }
  }
}
EOF
  # Point reasoning module to test snapshot and reload
  _REASONING_SNAPSHOT_FILE="$test_snapshot"
  _reasoning_load_snapshot

  run reasoning_get_allowed_efforts "gpt-5"
  assert_output "medium|high"

  # Verify default also reads from snapshot
  run reasoning_get_default "gpt-5"
  assert_output "high"

  # Restore real snapshot
  _REASONING_SNAPSHOT_FILE="${PROJECT_ROOT}/data/reasoning-snapshot.json"
  _reasoning_load_snapshot
}

@test "reasoning_model_supports_reasoning derives from snapshot, not hardcoded" {
  # Create a test snapshot with ONLY gpt-5-pro (no gpt-5)
  local test_snapshot="${BATS_TEST_TMPDIR}/test-snapshot.json"
  cat >"$test_snapshot" <<'EOF'
{
  "schema_version": "1",
  "policy_version": "0.0.1-test",
  "families": {
    "gpt-5-pro": {
      "allowed_efforts": ["high"],
      "default": "high"
    }
  }
}
EOF
  _REASONING_SNAPSHOT_FILE="$test_snapshot"
  _reasoning_load_snapshot

  # gpt-5-mini normalizes to "gpt-5" which is NOT in this test snapshot
  run reasoning_model_supports_reasoning "openai/gpt-5-mini"
  assert_failure

  # gpt-5-pro normalizes to "gpt-5-pro" which IS in this test snapshot
  run reasoning_model_supports_reasoning "openai/gpt-5-pro"
  assert_success

  # Restore real snapshot
  _REASONING_SNAPSHOT_FILE="${PROJECT_ROOT}/data/reasoning-snapshot.json"
  _reasoning_load_snapshot
}

@test "reasoning_model_supports_reasoning: no snapshot loaded returns failure" {
  # Clear snapshot
  local old_raw="$_REASONING_SNAPSHOT_RAW"
  _REASONING_SNAPSHOT_RAW=""

  run reasoning_model_supports_reasoning "openai/gpt-5-mini"
  assert_failure

  # Restore
  _REASONING_SNAPSHOT_RAW="$old_raw"
}

@test "reasoning_get_allowed_efforts falls back to conservative default without snapshot" {
  local old_raw="$_REASONING_SNAPSHOT_RAW"
  _REASONING_SNAPSHOT_RAW=""

  run reasoning_get_allowed_efforts "gpt-5"
  assert_output "low|medium|high"

  _REASONING_SNAPSHOT_RAW="$old_raw"
}

@test "reasoning_get_default falls back to medium without snapshot" {
  local old_raw="$_REASONING_SNAPSHOT_RAW"
  _REASONING_SNAPSHOT_RAW=""

  run reasoning_get_default "gpt-5"
  assert_output "medium"

  _REASONING_SNAPSHOT_RAW="$old_raw"
}

# Module guard test is in scaffold.bats (shared guard tests for all modules)

# ==========================================================================
# reasoning_normalize_family
# ==========================================================================

@test "reasoning_normalize_family: gpt-5-mini normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5-mini"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5-mini with date suffix normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5-mini-2025-08-07"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5-nano normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5-nano"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5 (base) normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5.1 normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5.1"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5.2 normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5.2"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5-codex normalizes to gpt-5" {
  run reasoning_normalize_family "openai/gpt-5-codex"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: gpt-5-pro normalizes to gpt-5-pro" {
  run reasoning_normalize_family "openai/gpt-5-pro"
  assert_success
  assert_output "gpt-5-pro"
}

@test "reasoning_normalize_family: gpt-5-pro with date suffix normalizes to gpt-5-pro" {
  run reasoning_normalize_family "openai/gpt-5-pro-2025-09-01"
  assert_success
  assert_output "gpt-5-pro"
}

@test "reasoning_normalize_family: claude model is unknown" {
  run reasoning_normalize_family "anthropic/claude-sonnet-4"
  assert_success
  assert_output "unknown"
}

@test "reasoning_normalize_family: google model is unknown" {
  run reasoning_normalize_family "google/gemini-2.5-flash"
  assert_success
  assert_output "unknown"
}

@test "reasoning_normalize_family: deepseek model is unknown" {
  run reasoning_normalize_family "deepseek/deepseek-r1"
  assert_success
  assert_output "unknown"
}

@test "reasoning_normalize_family: bare model without provider" {
  run reasoning_normalize_family "gpt-5-mini"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: colon variant stripped" {
  run reasoning_normalize_family "openai/gpt-5-mini:free"
  assert_success
  assert_output "gpt-5"
}

@test "reasoning_normalize_family: empty string returns unknown" {
  run reasoning_normalize_family ""
  assert_success
  assert_output "unknown"
}

# ==========================================================================
# reasoning_get_allowed_efforts (AC-01)
# ==========================================================================

@test "reasoning_get_allowed_efforts: gpt-5 returns low|medium|high" {
  run reasoning_get_allowed_efforts "gpt-5"
  assert_success
  assert_output "low|medium|high"
}

@test "reasoning_get_allowed_efforts: gpt-5-pro returns high only" {
  run reasoning_get_allowed_efforts "gpt-5-pro"
  assert_success
  assert_output "high"
}

@test "reasoning_get_allowed_efforts: unknown returns low|medium|high" {
  run reasoning_get_allowed_efforts "unknown"
  assert_success
  assert_output "low|medium|high"
}

@test "reasoning_get_allowed_efforts: gpt-5 excludes xhigh (AC-01)" {
  run reasoning_get_allowed_efforts "gpt-5"
  assert_success
  refute_output --partial "xhigh"
}

@test "reasoning_get_allowed_efforts: gpt-5 excludes none (AC-01)" {
  run reasoning_get_allowed_efforts "gpt-5"
  assert_success
  refute_output --partial "none"
}

@test "reasoning_get_allowed_efforts: unknown excludes xhigh" {
  run reasoning_get_allowed_efforts "unknown"
  assert_success
  refute_output --partial "xhigh"
}

@test "reasoning_get_allowed_efforts: unknown excludes none" {
  run reasoning_get_allowed_efforts "unknown"
  assert_success
  refute_output --partial "none"
}

# ==========================================================================
# reasoning_get_default (AC-02)
# ==========================================================================

@test "reasoning_get_default: gpt-5 defaults to medium (AC-02)" {
  run reasoning_get_default "gpt-5"
  assert_success
  assert_output "medium"
}

@test "reasoning_get_default: gpt-5-pro defaults to high" {
  run reasoning_get_default "gpt-5-pro"
  assert_success
  assert_output "high"
}

@test "reasoning_get_default: unknown defaults to medium (AC-03)" {
  run reasoning_get_default "unknown"
  assert_success
  assert_output "medium"
}

# ==========================================================================
# reasoning_validate_effort (AC-04)
# ==========================================================================

@test "reasoning_validate_effort: gpt-5 + medium is valid" {
  run reasoning_validate_effort "gpt-5" "medium"
  assert_success
}

@test "reasoning_validate_effort: gpt-5 + low is valid" {
  run reasoning_validate_effort "gpt-5" "low"
  assert_success
}

@test "reasoning_validate_effort: gpt-5 + high is valid" {
  run reasoning_validate_effort "gpt-5" "high"
  assert_success
}

@test "reasoning_validate_effort: gpt-5 + xhigh is rejected (AC-04)" {
  run reasoning_validate_effort "gpt-5" "xhigh"
  assert_failure
}

@test "reasoning_validate_effort: gpt-5 + none is rejected" {
  run reasoning_validate_effort "gpt-5" "none"
  assert_failure
}

@test "reasoning_validate_effort: gpt-5-pro + high is valid" {
  run reasoning_validate_effort "gpt-5-pro" "high"
  assert_success
}

@test "reasoning_validate_effort: gpt-5-pro + medium is rejected" {
  run reasoning_validate_effort "gpt-5-pro" "medium"
  assert_failure
}

@test "reasoning_validate_effort: gpt-5-pro + xhigh is rejected" {
  run reasoning_validate_effort "gpt-5-pro" "xhigh"
  assert_failure
}

@test "reasoning_validate_effort: unknown + medium is valid" {
  run reasoning_validate_effort "unknown" "medium"
  assert_success
}

@test "reasoning_validate_effort: unknown + xhigh is rejected" {
  run reasoning_validate_effort "unknown" "xhigh"
  assert_failure
}

# ==========================================================================
# reasoning_model_supports_reasoning
# ==========================================================================

@test "reasoning_model_supports_reasoning: gpt-5-mini supports reasoning" {
  run reasoning_model_supports_reasoning "openai/gpt-5-mini"
  assert_success
}

@test "reasoning_model_supports_reasoning: gpt-5 supports reasoning" {
  run reasoning_model_supports_reasoning "openai/gpt-5"
  assert_success
}

@test "reasoning_model_supports_reasoning: gpt-5-pro supports reasoning" {
  run reasoning_model_supports_reasoning "openai/gpt-5-pro"
  assert_success
}

@test "reasoning_model_supports_reasoning: claude does not" {
  run reasoning_model_supports_reasoning "anthropic/claude-sonnet-4"
  assert_failure
}

@test "reasoning_model_supports_reasoning: gemini does not" {
  run reasoning_model_supports_reasoning "google/gemini-2.5-flash"
  assert_failure
}

@test "reasoning_model_supports_reasoning: deepseek does not" {
  run reasoning_model_supports_reasoning "deepseek/deepseek-r1"
  assert_failure
}

@test "reasoning_model_supports_reasoning: unknown model does not" {
  run reasoning_model_supports_reasoning "some-unknown/model"
  assert_failure
}

# ==========================================================================
# reasoning_prompt_effort — interactive prompt
# ==========================================================================

@test "reasoning_prompt_effort: accepts default (medium) for gpt-5-mini (AC-02)" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5-mini" <<< "" 2>/dev/null
  '
  assert_success
  assert_output "medium"
}

@test "reasoning_prompt_effort: user selects low for gpt-5" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5" <<< "1" 2>/dev/null
  '
  assert_success
  assert_output "low"
}

@test "reasoning_prompt_effort: user selects high for gpt-5" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5" <<< "3" 2>/dev/null
  '
  assert_success
  assert_output "high"
}

@test "reasoning_prompt_effort: gpt-5-pro auto-selects high (single option)" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5-pro" 2>/dev/null
  '
  assert_success
  assert_output "high"
}

@test "reasoning_prompt_effort: gpt-5-pro shows only supported level message" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5-pro" 2>&1
  '
  assert_success
  assert_output --partial "only supported level"
}

@test "reasoning_prompt_effort: menu shows recommended marker for default" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5-mini" <<< "" 2>&1
  '
  assert_success
  assert_output --partial "(recommended)"
}

@test "reasoning_prompt_effort: menu does not show xhigh option" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5-mini" <<< "" 2>&1
  '
  assert_success
  refute_output --partial "xhigh"
}

@test "reasoning_prompt_effort: menu does not show none option" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5-mini" <<< "" 2>&1
  '
  assert_success
  refute_output --partial "none"
}

@test "reasoning_prompt_effort: retries on invalid input up to REASONING_MAX_PROMPT_ATTEMPTS then fails with exit 2" {
  # Feed exactly REASONING_MAX_PROMPT_ATTEMPTS (3) invalid inputs to exhaust retries.
  # Count must match REASONING_MAX_PROMPT_ATTEMPTS in lib/reasoning.sh.
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5" < <(printf "99\nabc\n0\n") 2>&1
  '
  [[ "$status" -eq 2 ]]
  assert_output --partial "Invalid choice"
  assert_output --partial "Too many invalid attempts"
}

@test "reasoning_prompt_effort: valid choice after invalid input succeeds" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    result="$(reasoning_prompt_effort "openai/gpt-5" < <(printf "99\n1\n") 2>/dev/null)"
    echo "$result"
  '
  assert_success
  assert_output "low"
}

@test "reasoning_prompt_effort: EOF returns exit code 1 (not 2)" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    reasoning_prompt_effort "openai/gpt-5" < /dev/null
  '
  [[ "$status" -eq 1 ]]
}

# ==========================================================================
# Snapshot version
# ==========================================================================

@test "REASONING_SNAPSHOT_VERSION is set" {
  [[ -n "$REASONING_SNAPSHOT_VERSION" ]]
}

@test "REASONING_MAX_PROMPT_ATTEMPTS is set to 3" {
  [[ "$REASONING_MAX_PROMPT_ATTEMPTS" -eq 3 ]]
}

# ==========================================================================
# Snapshot validation (_reasoning_load_snapshot)
# ==========================================================================

@test "snapshot validation: missing schema_version disables snapshot" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    tmpf="$(mktemp)"
    echo "{\"policy_version\":\"1.0.0\",\"families\":{}}" > "$tmpf"
    _REASONING_SNAPSHOT_FILE="$tmpf"
    _reasoning_load_snapshot
    echo "RAW=${_REASONING_SNAPSHOT_RAW:-empty}"
  ' 2>&1
  assert_success
  assert_output --partial "missing schema_version"
  assert_output --partial "RAW=empty"
}

@test "snapshot validation: missing policy_version disables snapshot" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    tmpf="$(mktemp)"
    echo "{\"schema_version\":\"1\",\"families\":{}}" > "$tmpf"
    _REASONING_SNAPSHOT_FILE="$tmpf"
    _reasoning_load_snapshot
    echo "RAW=${_REASONING_SNAPSHOT_RAW:-empty}"
  ' 2>&1
  assert_success
  assert_output --partial "missing policy_version"
  assert_output --partial "RAW=empty"
}

@test "snapshot validation: missing families key disables snapshot" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    tmpf="$(mktemp)"
    echo "{\"schema_version\":\"1\",\"policy_version\":\"1.0.0\"}" > "$tmpf"
    _REASONING_SNAPSHOT_FILE="$tmpf"
    _reasoning_load_snapshot
    echo "RAW=${_REASONING_SNAPSHOT_RAW:-empty}"
  ' 2>&1
  assert_success
  assert_output --partial "missing families"
  assert_output --partial "RAW=empty"
}

@test "snapshot validation: family missing allowed_efforts disables snapshot" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    tmpf="$(mktemp)"
    cat > "$tmpf" <<JSON
{
  "schema_version": "1",
  "policy_version": "1.0.0",
  "families": {
    "gpt-5": {
      "default": "medium"
    }
  }
}
JSON
    _REASONING_SNAPSHOT_FILE="$tmpf"
    _reasoning_load_snapshot
    echo "RAW=${_REASONING_SNAPSHOT_RAW:-empty}"
  ' 2>&1
  assert_success
  assert_output --partial "missing allowed_efforts"
  assert_output --partial "RAW=empty"
}

@test "snapshot validation: family missing default disables snapshot" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    tmpf="$(mktemp)"
    cat > "$tmpf" <<JSON
{
  "schema_version": "1",
  "policy_version": "1.0.0",
  "families": {
    "gpt-5": {
      "allowed_efforts": ["low", "medium", "high"]
    }
  }
}
JSON
    _REASONING_SNAPSHOT_FILE="$tmpf"
    _reasoning_load_snapshot
    echo "RAW=${_REASONING_SNAPSHOT_RAW:-empty}"
  ' 2>&1
  assert_success
  assert_output --partial "missing default"
  assert_output --partial "RAW=empty"
}

@test "snapshot validation: malformed snapshot falls back to conservative defaults" {
  run bash -c '
    export NO_COLOR=1
    source lib/ui.sh
    source lib/reasoning.sh
    tmpf="$(mktemp)"
    echo "not json at all {{" > "$tmpf"
    _REASONING_SNAPSHOT_FILE="$tmpf"
    _reasoning_load_snapshot
    echo "ALLOWED=$(reasoning_get_allowed_efforts "gpt-5")"
    echo "DEFAULT=$(reasoning_get_default "gpt-5")"
  ' 2>&1
  assert_success
  assert_output --partial "ALLOWED=low|medium|high"
  assert_output --partial "DEFAULT=medium"
}

# ==========================================================================
# End-to-end model → effort flow (AC-01, AC-03, AC-04)
# ==========================================================================

@test "e2e: gpt-5-mini model → family gpt-5 → no xhigh allowed (AC-01)" {
  local family
  family="$(reasoning_normalize_family "openai/gpt-5-mini")"
  [[ "$family" == "gpt-5" ]]

  local allowed
  allowed="$(reasoning_get_allowed_efforts "$family")"
  [[ "$allowed" == "low|medium|high" ]]

  run reasoning_validate_effort "$family" "xhigh"
  assert_failure
}

@test "e2e: unknown model → conservative medium default (AC-03)" {
  local family
  family="$(reasoning_normalize_family "meta-llama/llama-4-maverick")"
  [[ "$family" == "unknown" ]]

  # Unknown family should NOT support reasoning
  run reasoning_model_supports_reasoning "meta-llama/llama-4-maverick"
  assert_failure

  local default
  default="$(reasoning_get_default "$family")"
  [[ "$default" == "medium" ]]
}

@test "e2e: gpt-5 + xhigh rejected pre-deploy (AC-04)" {
  local family
  family="$(reasoning_normalize_family "openai/gpt-5-mini")"
  run reasoning_validate_effort "$family" "xhigh"
  assert_failure
}
