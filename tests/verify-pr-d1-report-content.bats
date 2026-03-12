#!/usr/bin/env bats
# tests/verify-pr-d1-report-content.bats — report-content verifier helper checks

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

teardown() {
  _common_teardown
}

@test "report-content helper accepts marker-based wording variations" {
  run bash -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT

    review3="${tmp}/review3.md"
    review1="${tmp}/review1.md"
    review2="${tmp}/review2.md"

    cat >"${review3}" <<'"'"'EOF'"'"'
## Summary
Some summary text.

## Section 5 Verification Command Log Summary
All section 5 checks passed deterministically.

Guardrails:
- scripts/install.sh unchanged
- scripts/release-guard.sh unchanged
EOF

    cat >"${review1}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The regression-prevention surface is behavior and content based in active gates.
EOF

    cat >"${review2}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The active verification surface is behavior-first and content-assertive.
EOF

    "${PROJECT_ROOT}/scripts/verify-pr-d1-report-content.sh" "${review3}" "${review1}" "${review2}"
  '
  assert_success
}

@test "report-content helper rejects missing section-5 pass signal" {
  run bash -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT

    review3="${tmp}/review3.md"
    review1="${tmp}/review1.md"
    review2="${tmp}/review2.md"

    cat >"${review3}" <<'"'"'EOF'"'"'
## Summary
Some summary text.

## Section 5 Verification Command Log Summary
Section 5 checks are listed below.

Guardrails:
- scripts/install.sh unchanged
- scripts/release-guard.sh unchanged
EOF

    cat >"${review1}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The regression-prevention surface is behavior and content based in active gates.
EOF

    cat >"${review2}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The active verification surface is behavior-first and content-assertive.
EOF

    "${PROJECT_ROOT}/scripts/verify-pr-d1-report-content.sh" "${review3}" "${review1}" "${review2}"
  '
  assert_failure
}

@test "report-content helper rejects negated section-5 pass wording" {
  run bash -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT

    review3="${tmp}/review3.md"
    review1="${tmp}/review1.md"
    review2="${tmp}/review2.md"

    cat >"${review3}" <<'"'"'EOF'"'"'
## Summary
Some summary text.

## Section 5 Verification Command Log Summary
Section 5 checks did not pass.

Guardrails:
- scripts/install.sh unchanged
- scripts/release-guard.sh unchanged
EOF

    cat >"${review1}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The regression-prevention surface is behavior and content based in active gates.
EOF

    cat >"${review2}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The active verification surface is behavior-first and content-assertive.
EOF

    "${PROJECT_ROOT}/scripts/verify-pr-d1-report-content.sh" "${review3}" "${review1}" "${review2}"
  '
  assert_failure
}

@test "report-content helper rejects section-5 wording with pass substring only" {
  run bash -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT

    review3="${tmp}/review3.md"
    review1="${tmp}/review1.md"
    review2="${tmp}/review2.md"

    cat >"${review3}" <<'"'"'EOF'"'"'
## Summary
Some summary text.

## Section 5 Verification Command Log Summary
Section 5 checks were surpassed by stronger gates.

Guardrails:
- scripts/install.sh unchanged
- scripts/release-guard.sh unchanged
EOF

    cat >"${review1}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The regression-prevention surface is behavior and content based in active gates.
EOF

    cat >"${review2}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The active verification surface is behavior-first and content-assertive.
EOF

    "${PROJECT_ROOT}/scripts/verify-pr-d1-report-content.sh" "${review3}" "${review1}" "${review2}"
  '
  assert_failure
}

@test "report-content helper rejects section-5 wording with hyphenated non-pass token" {
  run bash -c '
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap "rm -rf \"${tmp}\"" EXIT

    review3="${tmp}/review3.md"
    review1="${tmp}/review1.md"
    review2="${tmp}/review2.md"

    cat >"${review3}" <<'"'"'EOF'"'"'
## Summary
Some summary text.

## Section 5 Verification Command Log Summary
Section 5 checks were pass-through placeholders.

Guardrails:
- scripts/install.sh unchanged
- scripts/release-guard.sh unchanged
EOF

    cat >"${review1}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The regression-prevention surface is behavior and content based in active gates.
EOF

    cat >"${review2}" <<'"'"'EOF'"'"'
## Historical TDD Addendum
This addendum records the historical process deviation and its closure path.
The active verification surface is behavior-first and content-assertive.
EOF

    "${PROJECT_ROOT}/scripts/verify-pr-d1-report-content.sh" "${review3}" "${review1}" "${review2}"
  '
  assert_failure
}
