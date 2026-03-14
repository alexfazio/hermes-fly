# PR-D2 Follow-up Execution Plan (REVIEW_4): Verifier Recursion Guard + Deterministic Test Hardening

Date: 2026-03-14  
Parent documents:  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_3.md`  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d2-status-logs-review-2-implementation-report.md`  
Context: Static-analysis PR review findings for PR #11 (`worktree-majestic-hatching-sky -> main`)  
Timebox: 45 minutes (single session)  
Assignee profile: Junior developer  
Worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky`

## Implementation Status

Status: Ready for implementation  
Required outcome: Close all 3 review findings without changing runtime product behavior.

---

## 1) Findings To Resolve

### F1 (HIGH) - Verifier self-recursion risk

Files:
- `scripts/verify-pr-d2-status-logs.sh`
- `tests/verify-pr-d2-status-logs.bats`

Problem:
- `scripts/verify-pr-d2-status-logs.sh` invokes `tests/verify-pr-d2-status-logs.bats`.
- `tests/verify-pr-d2-status-logs.bats` invokes `scripts/verify-pr-d2-status-logs.sh`.
- Without a re-entrancy guard, this is an unbounded recursive path.

### F2 (MEDIUM) - Fragile invocation count assertion

File:
- `tests/verify-pr-d2-status-logs.bats`

Problem:
- Current check uses regex digit match (`[2-9]`), which incorrectly fails valid counts like `10` or `11`.

### F3 (LOW) - Streaming test timing flake

File:
- `tests/logs-ts-hybrid.bats`

Problem:
- Current streaming proof relies on fixed `sleep 0.2` and may fail on slow runners even when streaming is correct.

---

## 2) Scope

### In Scope (must implement)

1. Add verifier re-entrancy sentinel wiring.
2. Skip the verifier self-invocation bats test when running in re-entrant mode.
3. Replace regex count check with integer comparison.
4. Replace fixed sleep in streaming test with bounded polling timeout.

### Out of Scope (must not change)

1. No runtime production code in `src/`.
2. No parity baseline files in `tests/parity/baseline/`.
3. No changes to `scripts/install.sh`.
4. No changes to `scripts/release-guard.sh`.
5. No CI workflow changes.

---

## 3) Preconditions

### 3.1 Repository and Tooling

Run from worktree root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
```

Required tools:
- `bash`
- `rg`
- `git`
- `tests/bats/bin/bats` (already vendored in repo)

Optional timeout binary (one of):
- `timeout`
- `gtimeout`

### 3.2 Credential Readiness (explicit)

No credentials are required for this plan.

Reason:
- Verification commands use local test fixtures and `tests/mocks`.
- No external API calls are required.

Credential rule:
- Do not add or commit secrets.
- Do not modify `.env*` files for this patch.

### 3.3 Behavioral Contract (implementation target)

Happy path behavior:
1. Running verifier normally completes and prints exactly `PR-D2 status/logs verification passed.` as final line.
2. Streaming logs test proves first line appears before process exit using bounded timeout polling.

Edge-case behavior:
1. In re-entrant mode (`HERMES_FLY_PR_D2_VERIFIER_REENTRANT=1`), self-invocation test is skipped.
2. Invocation count check accepts any integer count `>= 2`.

Failure behavior:
1. If invocation count is `< 2`, test fails with exact message:  
   `MISSING: verify-pr-d2-status-logs.bats appears only once (not in bats invocation)`
2. If streaming first line is not observed before timeout, streaming test fails with exact timeout message.

Invariants:
1. Verifier still includes `tests/verify-pr-d2-status-logs.bats` in bats invocation.
2. No changes to out-of-scope files listed in section 2.

---

## 4) Ordered Implementation Steps

## 4.1 Step 1 - Add re-entrancy sentinel in verifier script

Path: `scripts/verify-pr-d2-status-logs.sh`  
Edit exactly the bats invocation command.

Required patch behavior:
1. Prefix bats command with this exact sentinel variable assignment:

```bash
HERMES_FLY_PR_D2_VERIFIER_REENTRANT=1 tests/bats/bin/bats \
```

2. Keep all bats file arguments unchanged, including:
- `tests/verify-pr-d2-status-logs.bats`

## 4.2 Step 2 - Gate self-invocation test in re-entrant mode

Path: `tests/verify-pr-d2-status-logs.bats`  
Edit test: `verify-pr-d2-status-logs.sh exits 0 and prints success message`.

Required patch behavior:
1. Add this exact guard before running verifier script:

```bash
if [[ "${HERMES_FLY_PR_D2_VERIFIER_REENTRANT:-}" == "1" ]]; then
  skip "skipping verifier self-invocation in re-entrant mode"
fi
```

2. Keep existing normal-mode assertions unchanged.

## 4.3 Step 3 - Replace regex count check with arithmetic check

Path: `tests/verify-pr-d2-status-logs.bats`  
Edit test: `verify-pr-d2-status-logs.sh bats invocation includes verify-pr-d2-status-logs.bats`.

Required patch behavior:
1. Use exact numeric logic:

```bash
count="$(grep -c "verify-pr-d2-status-logs.bats" "${script}")"
if (( count < 2 )); then
  echo "MISSING: verify-pr-d2-status-logs.bats appears only once (not in bats invocation)"
  exit 1
fi
```

2. Remove regex-digit logic for this assertion (`[2-9]`).

## 4.4 Step 4 - Stabilize streaming proof test with bounded polling

Path: `tests/logs-ts-hybrid.bats`  
Edit test: `hybrid allowlisted logs streams output incrementally before process exit`.

Required patch behavior:
1. Remove fixed wait `sleep 0.2`.
2. Add exact bounded polling constants:
- `max_attempts=100`
- `sleep_per_attempt=0.05`
- total timeout = 5 seconds
3. Require first-line detection via polling loop.
4. If timeout reached, fail with exact message:
- `FAIL: line-1 not visible within 5.00s timeout (streaming not working)`
5. Keep existing process-alive assertion after first-line detection.

---

## 5) Deterministic Verification Criteria

All checks are mandatory and must pass.

## 5.0 Step-to-Verification Traceability

- Step 4.1 -> `V-STR-01`, `V-INV-01`
- Step 4.2 -> `V-EDGE-01`, `V-STR-01`
- Step 4.3 -> `V-FAIL-01`, `V-STR-01`
- Step 4.4 -> `V-EDGE-02`, `V-HAPPY-01`

## 5.1 V-CRED-01 (Credential readiness)

Purpose:
- Prove this patch requires no credentials.

Preconditions/setup:
- Current directory is worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n "(DISCORD_TOKEN|SPRITES_TOKEN|GITHUB_TOKEN|FLY_API_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|SECRET|PASSWORD)" \
  scripts/verify-pr-d2-status-logs.sh tests/verify-pr-d2-status-logs.bats tests/logs-ts-hybrid.bats
```

Expected exit code:
- `1` (no matches found).

Expected output/artifacts:
- No stdout lines.

Pass/fail rule:
- Pass if command exits `1` and prints nothing.
- Fail otherwise.

Cleanup:
- None.

## 5.2 V-STR-01 (Static structural wiring)

Purpose:
- Prove sentinel + skip guard + arithmetic count check + polling constructs exist, and deprecated constructs are removed.

Preconditions/setup:
- Current directory is worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n "HERMES_FLY_PR_D2_VERIFIER_REENTRANT=1 tests/bats/bin/bats" scripts/verify-pr-d2-status-logs.sh
rg -n "skip \"skipping verifier self-invocation in re-entrant mode\"" tests/verify-pr-d2-status-logs.bats
rg -n "\(\( count < 2 \)\)" tests/verify-pr-d2-status-logs.bats
rg -n "\[2-9\]" tests/verify-pr-d2-status-logs.bats
rg -n "max_attempts=100|sleep_per_attempt=0\.05|line-1 not visible within 5\.00s timeout" tests/logs-ts-hybrid.bats
rg -n "sleep 0\.2" tests/logs-ts-hybrid.bats
```

Expected exit code:
1. First, second, third, and fifth `rg` commands exit `0`.
2. Fourth and sixth `rg` commands exit `1`.

Expected output/artifacts:
- Positive searches print matching lines with file + line number.
- Negative searches print nothing.

Pass/fail rule:
- Pass only if all six command exit codes match expected values.
- Fail if any command deviates.

Cleanup:
- None.

## 5.3 V-EDGE-01 (Re-entrant edge behavior)

Purpose:
- Prove self-invocation test is skipped when re-entrant sentinel is set.

Preconditions/setup:
- Current directory is worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
out="$(mktemp)"
HERMES_FLY_PR_D2_VERIFIER_REENTRANT=1 tests/bats/bin/bats tests/verify-pr-d2-status-logs.bats \
  -f "verify-pr-d2-status-logs.sh exits 0 and prints success message" >"${out}" 2>&1
rc="$?"
printf "%s\n" "${rc}"
grep -F "skip" "${out}"
grep -F "skipping verifier self-invocation in re-entrant mode" "${out}"
rm -f "${out}"
```

Expected exit code:
- Overall command block exits `0`.
- Printed `rc` value is `0`.

Expected output/artifacts:
- Bats output contains `skip` and exact skip message.

Pass/fail rule:
- Pass if `rc=0` and both grep commands succeed.
- Fail otherwise.

Cleanup:
- Removes temporary output file.

## 5.4 V-FAIL-01 (Failure path for invocation count)

Purpose:
- Prove numeric count logic fails deterministically when count is below threshold.

Preconditions/setup:
- Current directory is worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
tmp_script="$(mktemp)"
awk 'BEGIN{removed=0} {if (!removed && $0 ~ /tests\/verify-pr-d2-status-logs\.bats/) {removed=1; next} print}' \
  scripts/verify-pr-d2-status-logs.sh > "${tmp_script}"

set +e
msg="$(bash -c '
  set -euo pipefail
  script="$1"
  count="$(grep -c "verify-pr-d2-status-logs.bats" "${script}")"
  if (( count < 2 )); then
    echo "MISSING: verify-pr-d2-status-logs.bats appears only once (not in bats invocation)"
    exit 1
  fi
' _ "${tmp_script}" 2>&1)"
rc="$?"
set -e

printf "%s\n" "${rc}"
printf "%s\n" "${msg}"

if [[ "${rc}" -ne 1 ]]; then
  echo "Unexpected exit code for failure-path check" >&2
  rm -f "${tmp_script}"
  exit 1
fi

if [[ "${msg}" != "MISSING: verify-pr-d2-status-logs.bats appears only once (not in bats invocation)" ]]; then
  echo "Unexpected failure-path message" >&2
  rm -f "${tmp_script}"
  exit 1
fi

rm -f "${tmp_script}"
```

Expected exit code:
- Overall block exits `0`.
- Internal failure-path `rc` is exactly `1`.

Expected output/artifacts:
- Printed `rc` line equals `1`.
- Printed message exactly matches required failure string.

Pass/fail rule:
- Pass only if internal `rc=1` and exact message string matches.
- Fail otherwise.

Cleanup:
- Removes temporary script file.

## 5.5 V-EDGE-02 (Streaming edge behavior)

Purpose:
- Prove streaming test implementation now uses bounded polling and retains process-alive assertion ordering.

Preconditions/setup:
- Current directory is worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
nl -ba tests/logs-ts-hybrid.bats | sed -n '90,170p'
```

Expected exit code:
- `0`.

Expected output/artifacts:
- Output region includes:
  - `max_attempts=100`
  - `sleep_per_attempt=0.05`
  - polling loop for line-1 detection
  - timeout failure message with `5.00s`
  - process-alive assertion after detection block

Pass/fail rule:
- Pass if all listed constructs appear in the displayed block in expected logical order.
- Fail otherwise.

Cleanup:
- None.

## 5.6 V-HAPPY-01 (Happy path end-to-end verifier run)

Purpose:
- Prove normal verifier flow completes without recursion and keeps success contract.

Preconditions/setup:
- Current directory is worktree root.
- `npm` dependencies already installed in this worktree.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
out="$(mktemp)"
if command -v timeout >/dev/null 2>&1; then
  timeout 180s ./scripts/verify-pr-d2-status-logs.sh >"${out}" 2>&1
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout 180s ./scripts/verify-pr-d2-status-logs.sh >"${out}" 2>&1
else
  ./scripts/verify-pr-d2-status-logs.sh >"${out}" 2>&1
fi
rc="$?"
printf "%s\n" "${rc}"
tail -1 "${out}"
rm -f "${out}"
```

Expected exit code:
- Overall command block exits `0`.
- Printed `rc` value is `0`.

Expected output/artifacts:
- Final line exactly: `PR-D2 status/logs verification passed.`

Pass/fail rule:
- Pass only if `rc=0` and final line exact-match succeeds.
- Fail otherwise.

Cleanup:
- Removes temporary output file.

## 5.7 V-INV-01 (Regression and invariant guard)

Purpose:
- Prove out-of-scope files and invariants remain unchanged.

Preconditions/setup:
- Current directory is worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
git diff --name-only -- scripts/install.sh scripts/release-guard.sh
git diff --name-only -- tests/parity/baseline
git diff --name-only -- src
```

Expected exit code:
- All commands exit `0`.

Expected output/artifacts:
- All commands print no lines.

Pass/fail rule:
- Pass only if output is empty for all three commands.
- Fail if any path is listed.

Cleanup:
- None.

---

## 6) Completion Checklist

1. Steps 4.1-4.4 implemented exactly.
2. All verification checks `V-CRED-01` through `V-INV-01` pass.
3. Only these files are modified:
- `scripts/verify-pr-d2-status-logs.sh`
- `tests/verify-pr-d2-status-logs.bats`
- `tests/logs-ts-hybrid.bats`
4. Commit message references: `pr-d2 verifier recursion guard + deterministic test hardening`.

---

## 7) Supporting Information

1. No external documentation lookup is required to execute this plan.
2. No database migrations, feature flags, rollout, or release-guard changes are part of this patch.
3. Rollback procedure (if needed before commit):

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
git restore scripts/verify-pr-d2-status-logs.sh tests/verify-pr-d2-status-logs.bats tests/logs-ts-hybrid.bats
```

4. Safety rule: never commit plaintext secrets; this plan does not require adding secrets.

## Execution Log

### Slice 1: Add re-entrancy sentinel in verifier script
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted (V-STR-01 check 1, V-INV-01)
- [x] S5 WRITE_TEST: rg structural check on scripts/verify-pr-d2-status-logs.sh
- [x] S6 CONFIRM_RED: sentinel absent (rg exit 1)
- [x] S7 IMPLEMENT: modified `scripts/verify-pr-d2-status-logs.sh` — prefixed bats command with `HERMES_FLY_PR_D2_VERIFIER_REENTRANT=1`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: Gate self-invocation test in re-entrant mode
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted (V-EDGE-01, V-STR-01 check 2)
- [x] S5 WRITE_TEST: rg structural check on tests/verify-pr-d2-status-logs.bats
- [x] S6 CONFIRM_RED: skip guard absent (rg exit 1)
- [x] S7 IMPLEMENT: modified `tests/verify-pr-d2-status-logs.bats` — added REENTRANT guard before `run bash -c` in self-invocation test
- [x] S8 RUN_TESTS: pass (1 iteration) — bats skip fires with rc=0
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: Replace regex count check with arithmetic check
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (V-STR-01 checks 3+4, V-FAIL-01)
- [x] S5 WRITE_TEST: rg structural checks on tests/verify-pr-d2-status-logs.bats
- [x] S6 CONFIRM_RED: `(( count < 2 ))` absent, `[2-9]` present
- [x] S7 IMPLEMENT: modified `tests/verify-pr-d2-status-logs.bats` — replaced regex pipe pattern with `(( count < 2 ))` in bats-invocation test; also fixed second `[2-9]` instance in missing-app test (line 121) to satisfy V-STR-01's requirement that no `[2-9]` remains in the file
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: [S10] V-STR-01 check 4 initially failed because a second `[2-9]` instance existed at line 121 in the "missing-app grep checks for logs" test (outside the plan's explicit target test). Both instances shared the same conceptual flaw; fixed both to satisfy the file-wide V-STR-01 structural check.

### Slice 4: Stabilize streaming proof test with bounded polling
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (V-STR-01 checks 5+6, V-EDGE-02)
- [x] S5 WRITE_TEST: rg structural checks on tests/logs-ts-hybrid.bats
- [x] S6 CONFIRM_RED: polling constructs absent, `sleep 0.2` present
- [x] S7 IMPLEMENT: modified `tests/logs-ts-hybrid.bats` — replaced fixed `sleep 0.2` block with bounded polling loop (max_attempts=100, sleep_per_attempt=0.05, timeout msg with 5.00s)
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 run — V-HAPPY-01 ran full verifier end-to-end: rc=0, "PR-D2 status/logs verification passed.")
- Criteria walk: all satisfied (V-CRED-01 exit 1 no creds, V-STR-01 all 6 checks correct, V-EDGE-01 skip fires in re-entrant mode, V-FAIL-01 exact failure message, V-EDGE-02 polling constructs in correct order, V-HAPPY-01 rc=0 correct sentinel, V-INV-01 no out-of-scope changes)
