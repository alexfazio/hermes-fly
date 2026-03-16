# Remediation Plan: PR #12 Review-8 Findings

Date: 2026-03-16
Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_8.md`
Primary worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
Target PR: `#12 feat: complete TypeScript Commander.js full transition (9 slices)`
Supersedes: `typescript-commander-full-transition-20260315_REVIEW_7.md` (unresolved Step 1 only)

Execution mode:
- Static-analysis implementation and verification only.
- No product/API/architecture decisions delegated to implementer.
- Implementer works only in `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.

---

## 1) Objective

Resolve the remaining blocking defect in deploy integration tests.

1. Remove the 3 remaining double-quoted shim `printf` templates that expand `${1:-}` and `$@` too early.
2. Replace those 3 templates with a runtime-safe literal template (single-quoted `printf` payload) while keeping the existing outer `run bash -c '...'` structure.
3. Preserve assertion behavior in all 4 deploy tests.

---

## 2) In Scope / Out of Scope

### In Scope

1. `tests/integration.bats`
2. Only these 3 test blocks:
   - `hermes-fly deploy --no-auto-install skips install when fly not on PATH`
   - `hermes-fly deploy --channel invalid falls back to stable (PR-05)`
   - `hermes-fly deploy --channel preview uses runtime path without parse errors (PR-05)`

### Out of Scope

1. `src/**`
2. All files except `tests/integration.bats`
3. Runtime test execution in this remediation plan (verification is static-analysis only)
4. Matrix loop test logic, except read-only verification that it remains valid

---

## 3) Preconditions, Dependencies, Credentials

Preconditions:

1. Worktree path is `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.
2. Active branch is `worktree-compressed-waddling-rose`.
3. Required local tools are available: `bash`, `git`, `rg`, `awk`, `sed`, `sort`, `comm`, `wc`, `tr`.
4. No credentials are required.
5. Never commit plaintext secrets or `.env` files.
6. Capture pre-existing uncommitted changes before editing so scope verification checks only net-new drift.

Pre-check command:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
bash -euo pipefail -c '
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  test -f tests/integration.bats
  mkdir -p tmp/verification
  git diff --name-only | sort -u > tmp/verification/V5.preexisting.diff
'
```

Expected exit code: `0`
Expected artifacts:
- `tmp/verification/V5.preexisting.diff`

---

## 4) Behavioral Specification

### Happy path behavior

1. In each targeted test, the generated shim file body must contain literal `${1:-}` and `$@` tokens so they are evaluated when the shim executes.
2. The shim must return exit `1` only when called as `which fly`; for all other arguments it must delegate to `/usr/bin/which "$@"`.
3. Existing deploy assertions remain intact:
   - `assert_output --partial "auto-install disabled"` in all 4 deploy tests.
   - `refute_output --partial "Not authenticated"` in all 4 deploy tests.
   - `refute_output --partial "Unknown option"` and `refute_output --partial "Unknown command"` in the 3 channel tests.

### Edge-case behavior

1. Empty first positional arg (`${1:-}`) remains safe and does not raise unbound-variable errors.
2. Matrix test shim remains unchanged and still uses runtime-safe literal payload.

### Failure/error behavior

1. If any bad double-quoted shim template remains, verification fails.
2. If any targeted test loses required assertions, verification fails.
3. If any net-new modified file is outside `tests/integration.bats`, verification fails.

### Invariants

1. Only `tests/integration.bats` is modified by this remediation.
2. No design choices delegated to implementer; replacement string is exact.

---

## 5) Ordered Implementation Steps

Apply steps in exact order.

### Step 1 - Replace the 3 bad shim template lines with exact literal-safe template

Code refs:
- `tests/integration.bats` in the 3 targeted tests listed in Section 2.

Required edit in each of the 3 targeted tests:

1. Find this exact bad line:
   - `printf "#!/usr/bin/env bash\nif [[ \"${1:-}\" == \"fly\" ]]; then exit 1; fi\nexec /usr/bin/which \"$@\"\n" > "${tmp_no_fly}/which"`
2. Replace with this exact line:
   - `printf '\''#!/usr/bin/env bash\nif [[ "${1:-}" == "fly" ]]; then exit 1; fi\nexec /usr/bin/which "$@"\n'\'' > "${tmp_no_fly}/which"`

Notes:

1. Keep outer `run bash -c ' ... '` quotes unchanged.
2. Do not modify the matrix test shim line that is already runtime-safe.

Expected post-state:

1. No bad `printf "#!/usr/bin/env bash` lines remain in `tests/integration.bats`.
2. Exactly 3 occurrences of the replacement escaped-single-quote template exist.
3. Matrix test retains its existing single-quoted template form.

---

### Step 2 - Preserve assertion contract in all 4 deploy tests

Code refs:
- `tests/integration.bats`

Required post-edit state (no removals allowed):

1. `assert_output --partial "auto-install disabled"` present in all 4 deploy tests.
2. `refute_output --partial "Not authenticated"` present in all 4 deploy tests.
3. `refute_output --partial "Unknown option"` present in 3 channel tests.
4. `refute_output --partial "Unknown command"` present in 3 channel tests.

---

## 6) Deterministic Verification Matrix (Static Analysis Only)

Run from:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
mkdir -p tmp/verification
```

### V0 - Credential readiness and worktree guard

Purpose:
- Prove worktree/branch scope is correct and no secrets are embedded in this plan.
- Coverage type: credential-readiness.

Preconditions:
1. None.

Command:

```bash
bash -euo pipefail -c '
  test -d /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  if rg -n "OPENROUTER_API_KEY=.*[A-Za-z0-9]|TELEGRAM_BOT_TOKEN=.*[A-Za-z0-9]" docs/plans/typescript-commander-full-transition-20260315_REVIEW_8.md; then
    exit 1
  fi
' >tmp/verification/V0.out 2>tmp/verification/V0.err
```

Expected exit code: `0`
Expected output: no secret-assignment matches.
Artifacts:
- `tmp/verification/V0.out`
- `tmp/verification/V0.err`
Pass/fail rule: exit code `0` and empty `V0.err`.
Cleanup: none.

---

### V1 - Bad double-quoted shim template removed (failure-path prevention)

Purpose:
- Prove early-expansion bug pattern no longer exists.
- Coverage type: failure/error path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  if rg -n "printf \"#!/usr/bin/env bash" tests/integration.bats; then
    exit 1
  fi
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code: `0`
Expected output: no matches.
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`
Pass/fail rule: exit code `0`; any match is fail.
Cleanup: none.

---

### V2 - Per-block literal-safe replacement exists in the 3 targeted tests

Purpose:
- Prove each targeted block contains the exact escaped-single-quote replacement.
- Coverage type: happy path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  awk "/@test \"hermes-fly deploy --no-auto-install skips install when fly not on PATH\"/,/^}/" "${target}" > tmp/verification/V2.t1.block
  awk "/@test \"hermes-fly deploy --channel invalid falls back to stable \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t2.block
  awk "/@test \"hermes-fly deploy --channel preview uses runtime path without parse errors \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t3.block

  cat > tmp/verification/V2.expected.literal <<'\''TPL'\''
printf '\''#!/usr/bin/env bash\nif [[ "${1:-}" == "fly" ]]; then exit 1; fi\nexec /usr/bin/which "$@"\n'\'' > "${tmp_no_fly}/which"
TPL

  rg -F -f tmp/verification/V2.expected.literal tmp/verification/V2.t1.block
  rg -F -f tmp/verification/V2.expected.literal tmp/verification/V2.t2.block
  rg -F -f tmp/verification/V2.expected.literal tmp/verification/V2.t3.block
'
>tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code: `0`
Expected output: one literal-template match in each of the 3 extracted blocks.
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V2.t1.block`
- `tmp/verification/V2.t2.block`
- `tmp/verification/V2.t3.block`
- `tmp/verification/V2.expected.literal`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`
Pass/fail rule: all 3 block checks must match.
Cleanup: none.

---

### V3 - Matrix block remains runtime-safe and unchanged in intent

Purpose:
- Confirm matrix test still contains runtime-safe template and keeps loop behavior contract.
- Coverage type: edge case.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  awk "/@test \"channel end-to-end matrix resolves expected refs for stable preview edge \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V3.t4.block
  rg -n "for ch in stable preview edge; do" tmp/verification/V3.t4.block
  rg -n "printf '#!/usr/bin/env bash" tmp/verification/V3.t4.block
  rg -n "\\\$\\{1:-\\}" tmp/verification/V3.t4.block
  rg -n "\\\$@" tmp/verification/V3.t4.block
'
>tmp/verification/V3.out 2>tmp/verification/V3.err
```

Expected exit code: `0`
Expected output:
- loop line exists.
- matrix block contains single-quoted `printf` payload with `${1:-}` and `$@` preserved for shim runtime.
Artifacts:
- `tmp/verification/V3.t4.block`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`
Pass/fail rule: all 4 `rg` checks must match.
Cleanup: none.

---

### V4 - Required assertion contract preserved

Purpose:
- Ensure deploy assertion behavior was not weakened during template fix.
- Coverage type: regression/safety.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  awk "/@test \"hermes-fly deploy --no-auto-install skips install when fly not on PATH\"/,/^}/" "${target}" > tmp/verification/V4.t1.block
  awk "/@test \"hermes-fly deploy --channel invalid falls back to stable \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V4.t2.block
  awk "/@test \"hermes-fly deploy --channel preview uses runtime path without parse errors \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V4.t3.block
  awk "/@test \"channel end-to-end matrix resolves expected refs for stable preview edge \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V4.t4.block

  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V4.t1.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V4.t2.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V4.t3.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V4.t4.block

  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V4.t1.block
  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V4.t2.block
  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V4.t3.block
  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V4.t4.block

  rg -n "refute_output --partial \"Unknown option\"" tmp/verification/V4.t2.block
  rg -n "refute_output --partial \"Unknown option\"" tmp/verification/V4.t3.block
  rg -n "refute_output --partial \"Unknown option\"" tmp/verification/V4.t4.block

  rg -n "refute_output --partial \"Unknown command\"" tmp/verification/V4.t2.block
  rg -n "refute_output --partial \"Unknown command\"" tmp/verification/V4.t3.block
  rg -n "refute_output --partial \"Unknown command\"" tmp/verification/V4.t4.block
'
>tmp/verification/V4.out 2>tmp/verification/V4.err
```

Expected exit code: `0`
Expected output:
- all 4 blocks include `auto-install disabled` and `Not authenticated` refute.
- 3 channel blocks include `Unknown option` and `Unknown command` refutes.
Artifacts:
- `tmp/verification/V4.t1.block`
- `tmp/verification/V4.t2.block`
- `tmp/verification/V4.t3.block`
- `tmp/verification/V4.t4.block`
- `tmp/verification/V4.out`
- `tmp/verification/V4.err`
Pass/fail rule: all 14 assertion checks must match.
Cleanup: none.

---

### V5 - Scope containment (net-new files)

Purpose:
- Ensure remediation touches only `tests/integration.bats` in net-new diff.
- Coverage type: regression/safety.

Preconditions:
1. Pre-check completed and `tmp/verification/V5.preexisting.diff` exists.

Command:

```bash
bash -euo pipefail -c '
  allowed="^tests/integration\\.bats$"
  test -f tmp/verification/V5.preexisting.diff
  git diff --name-only | sort -u > tmp/verification/V5.current.diff
  sort -u tmp/verification/V5.preexisting.diff > tmp/verification/V5.preexisting.sorted
  comm -13 tmp/verification/V5.preexisting.sorted tmp/verification/V5.current.diff > tmp/verification/V5.new.diff
  if [[ -s tmp/verification/V5.new.diff ]]; then
    while IFS= read -r f; do
      if ! printf "%s\n" "${f}" | rg -q "${allowed}"; then
        printf "Out-of-scope changed file: %s\n" "${f}" >&2
        exit 1
      fi
    done < tmp/verification/V5.new.diff
  fi
' >tmp/verification/V5.out 2>tmp/verification/V5.err
```

Expected exit code: `0`
Expected output: no `Out-of-scope changed file:` message.
Artifacts:
- `tmp/verification/V5.preexisting.diff`
- `tmp/verification/V5.preexisting.sorted`
- `tmp/verification/V5.current.diff`
- `tmp/verification/V5.new.diff`
- `tmp/verification/V5.out`
- `tmp/verification/V5.err`
Pass/fail rule: exit code `0`, empty `V5.err`, no out-of-scope file lines.
Cleanup: none.

---

## 7) Step-to-Verification Traceability

1. Step 1 -> V1, V2, V3
2. Step 2 -> V4
3. Cross-cutting scope and credential safety -> V0, V5

---

## 8) Deliverables

1. Updated `tests/integration.bats` with exactly 3 corrected shim template lines.
2. Assertion contract preserved in all 4 deploy tests.
3. Static verification artifacts:
   - `tmp/verification/V0.out` through `tmp/verification/V5.out`

---

## 9) Completion Criteria

This remediation is complete only when all are true:

1. Step 1 and Step 2 applied in order.
2. V0, V1, V2, V3, V4, V5 all exit with `0`.
3. No `printf "#!/usr/bin/env bash` pattern remains in `tests/integration.bats`.
4. No product/API/architecture decisions delegated to implementer judgment.

## Execution Log

### Slice 1: Replace 3 bad shim template lines (Step 1)
- [x] S4 ANALYZE_CRITERIA: 3 criteria (no double-quoted printf, 3 single-quoted replacements, matrix unchanged)
- [x] S5 WRITE_TEST: V1 grep for bad pattern
- [x] S6 CONFIRM_RED: 3 matches at lines 104, 129, 146
- [x] S7 IMPLEMENT: `replace_all` edit replacing double-quoted printf with escaped-single-quote printf in all 3 occurrences
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: Assertion contract preservation (Step 2)
- [x] S4 ANALYZE_CRITERIA: 14 assertion checks across 4 blocks
- [x] S5-S8: verified as read-only; no edits required — all assertions intact
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration) — V0 PASS, V1 PASS, V2 PASS, V3 PASS, V4 PASS, V5 PASS
- Criteria walk: all satisfied
