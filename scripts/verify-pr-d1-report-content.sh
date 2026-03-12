#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf "Usage: %s <review3-report> <review1-plan> <review2-plan>\n" "$0" >&2
  exit 1
fi

review3_report="$1"
review1_plan="$2"
review2_plan="$3"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    printf "Missing required file: %s\n" "${path}" >&2
    exit 1
  fi
}

require_pattern() {
  local pattern="$1"
  local path="$2"
  if ! grep -Eiq "${pattern}" "${path}"; then
    printf "Missing required pattern '%s' in %s\n" "${pattern}" "${path}" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local path="$2"
  if grep -Eiq "${pattern}" "${path}"; then
    printf "Found forbidden pattern '%s' in %s\n" "${pattern}" "${path}" >&2
    exit 1
  fi
}

require_file "${review3_report}"
require_file "${review1_plan}"
require_file "${review2_plan}"

# REVIEW-3 implementation report: keep heading checks strict, but make pass-signal wording resilient.
# Require standalone pass tokens to avoid substring false positives like "surpassed" or "pass-through".
grep -x "## Summary" "${review3_report}" >/dev/null
grep -x "## Section 5 Verification Command Log Summary" "${review3_report}" >/dev/null
require_pattern "section[[:space:]]*5.*(criteria|checks).*([^[:alnum:]_-]|^)(pass|passed)([^[:alnum:]_-]|$)" "${review3_report}"
reject_pattern "section[[:space:]]*5.*(did[[:space:]]+not|didn't|not|never|without).*([^[:alnum:]_-]|^)(pass|passed)([^[:alnum:]_-]|$)" "${review3_report}"
reject_pattern "(did[[:space:]]+not|didn't|not|never|without).*([^[:alnum:]_-]|^)(pass|passed)([^[:alnum:]_-]|$).*section[[:space:]]*5" "${review3_report}"
grep -F "scripts/install.sh" "${review3_report}" >/dev/null
grep -F "scripts/release-guard.sh" "${review3_report}" >/dev/null

# REVIEW-1 and REVIEW-2 addenda: lock intent markers without exact-sentence brittleness.
for plan_file in "${review1_plan}" "${review2_plan}"; do
  grep -x "## Historical TDD Addendum" "${plan_file}" >/dev/null
  require_pattern "historical process deviation" "${plan_file}"
  require_pattern "(active verification surface|regression-prevention surface)" "${plan_file}"
  require_pattern "behavior" "${plan_file}"
  require_pattern "content" "${plan_file}"
done
