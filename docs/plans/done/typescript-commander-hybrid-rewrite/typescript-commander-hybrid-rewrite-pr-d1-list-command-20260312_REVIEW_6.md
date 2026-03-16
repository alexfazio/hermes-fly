# PR-D2 REVIEW-6 Execution Plan: Harden Malformed-Flag Failure Assertions In Verifier

Date: 2026-03-14  
Parent plans/reports:  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_5.md`  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d2-status-logs-review-2-implementation-report.md`  
Context: Follow-up after static PR review finding on verifier coverage gap  
Worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky`  
Target branch: `worktree-majestic-hatching-sky`  
Assignee profile: Junior developer

## Implementation Status

Status: Ready for implementation  
Primary outcome: prevent false-pass verification by enforcing exit-code and stdout-empty assertions for malformed explicit-flag failure paths.

---

## 1) Finding To Resolve

### F1 (MEDIUM): Verifier malformed-flag checks do not assert full failure contract

Code references:
- `scripts/verify-pr-d2-status-logs.sh`
- `tests/verify-pr-d2-status-logs.bats`

Problem summary:
1. Malformed-flag blocks currently assert stderr text content only.
2. They do not assert command exit code (`1`).
3. They do not assert stdout emptiness on failure.
4. This allows a false pass if command behavior regresses but still emits expected stderr line.

Required behavior after fix:
1. For `status -a --unknown-flag` malformed case:
- exit code must be exactly `1`
- stdout must be empty
- stderr must include explicit app failure for `--unknown-flag`
- stderr must not include `fallback-app` or `No app specified`
2. For `logs -a --unknown-flag` malformed case:
- exit code must be exactly `1`
- stdout must be empty
- stderr must include explicit app failure for `--unknown-flag`
- stderr must not include `fallback-app` or `No app specified`
3. Structural verifier test must enforce that these assertions remain present in script.
4. Existing happy-path verifier coverage must remain intact:
- status baseline diff assertions for `-a test-app`
- logs baseline diff assertions for `-a test-app`
- terminal success message `PR-D2 status/logs verification passed.`

---

## 2) Scope

### In Scope

1. Update malformed status block in `scripts/verify-pr-d2-status-logs.sh` to capture and assert exit/stdout.
2. Update malformed logs block in `scripts/verify-pr-d2-status-logs.sh` to capture and assert exit/stdout.
3. Update structural checks in `tests/verify-pr-d2-status-logs.bats` to verify the new assertions exist.

### Out of Scope

1. No modifications to any `src/` production code.
2. No modifications to `scripts/install.sh`.
3. No modifications to `scripts/release-guard.sh`.
4. No modifications to parity snapshot files in `tests/parity/baseline/`.
5. No command routing or behavior changes outside verifier coverage.

---

## 3) Preconditions, Dependencies, and Credential Readiness

## 3.1 Working Directory

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
```

## 3.2 Required Tooling

- `bash`
- `rg`
- `git`
- `node`
- `npm`
- `tests/bats/bin/bats`

## 3.3 Dependencies

If dependencies are missing, run:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
npm install
```

## 3.4 Credentials

No credentials required.  
Do not add or modify any `.env*` files.  
Do not commit secrets.

---

## 4) Ordered Implementation Steps (No Decisions Delegated)

Perform steps exactly in order.

## 4.1 Step 1 - Harden malformed status block in verifier script

File: `scripts/verify-pr-d2-status-logs.sh`

In the existing malformed status block (`./hermes-fly status -a --unknown-flag`):

1. Keep command invocation, but capture exit code deterministically into `${TMP_DIR}/malformed-status.exit`.
2. Add assertion: exit code file value must equal `1`.
3. Add assertion: `${tmp}/malformed-status.out` must be empty.
4. Keep existing stderr assertions unchanged:
- contains `Failed to get status for app '--unknown-flag'`
- does not contain `fallback-app`
- does not contain `No app specified`

Implementation pattern to mirror existing script style:
1. Write exit code with `printf "%s\n" "$?" >"${TMP_DIR}/malformed-status.exit"`.
2. On mismatch, print a deterministic `Unexpected malformed-status exit: ...` message and `exit 1`.
3. On non-empty stdout, print deterministic `Unexpected malformed-status stdout: ...` message and `exit 1`.

## 4.2 Step 2 - Harden malformed logs block in verifier script

File: `scripts/verify-pr-d2-status-logs.sh`

In the existing malformed logs block (`./hermes-fly logs -a --unknown-flag`):

1. Keep command invocation, but capture exit code deterministically into `${TMP_DIR}/malformed-logs.exit`.
2. Add assertion: exit code file value must equal `1`.
3. Add assertion: `${tmp}/malformed-logs.out` must be empty.
4. Keep existing stderr assertions unchanged:
- contains `Failed to fetch logs for app '--unknown-flag'`
- does not contain `fallback-app`
- does not contain `No app specified`

Implementation pattern to mirror existing script style:
1. Write exit code with `printf "%s\n" "$?" >"${TMP_DIR}/malformed-logs.exit"`.
2. On mismatch, print deterministic `Unexpected malformed-logs exit: ...` message and `exit 1`.
3. On non-empty stdout, print deterministic `Unexpected malformed-logs stdout: ...` message and `exit 1`.

## 4.3 Step 3 - Extend structural verifier-contract test

File: `tests/verify-pr-d2-status-logs.bats`

Update the test that validates malformed-flag assertions so it also requires all newly-added script assertions to exist.

Required structural checks to add:
1. Presence of `malformed-status.exit` usage in script.
2. Presence of `Unexpected malformed-status exit` check string in script.
3. Presence of `Unexpected malformed-status stdout` check string in script.
4. Presence of `malformed-logs.exit` usage in script.
5. Presence of `Unexpected malformed-logs exit` check string in script.
6. Presence of `Unexpected malformed-logs stdout` check string in script.

Use existing style:
1. `grep -q ... "${script}"`
2. deterministic `echo "MISSING: ..."`
3. `exit 1` on missing match

---

## 5) Deterministic Verification Criteria

All checks are mandatory.

## 5.0 Step-to-Verification Traceability

- Step 4.1 -> `V1`, `V4`
- Step 4.2 -> `V2`, `V4`
- Step 4.3 -> `V3`, `V8`
- Scope invariants -> `V5`
- Happy-path safety -> `V6`
- Runtime failure-path behavior -> `V7`

## 5.1 V1 - Status malformed block contains exit + stdout assertions

Purpose:
- Prove malformed status block enforces full failure contract.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  s="scripts/verify-pr-d2-status-logs.sh"
  rg -n "malformed-status\\.exit" "$s" >/dev/null
  rg -n "Unexpected malformed-status exit" "$s" >/dev/null
  rg -n "Unexpected malformed-status stdout" "$s" >/dev/null
  rg -n "Failed to get status for app '\''--unknown-flag'\''" "$s" >/dev/null
'
```

Expected exit code:
- `0`.

Expected output:
- none required.

Artifacts:
- `scripts/verify-pr-d2-status-logs.sh`

Pass/fail rule:
- Pass only if command exits `0`.
- Fail on any non-zero exit.

Cleanup:
- none.

## 5.2 V2 - Logs malformed block contains exit + stdout assertions

Purpose:
- Prove malformed logs block enforces full failure contract.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  s="scripts/verify-pr-d2-status-logs.sh"
  rg -n "malformed-logs\\.exit" "$s" >/dev/null
  rg -n "Unexpected malformed-logs exit" "$s" >/dev/null
  rg -n "Unexpected malformed-logs stdout" "$s" >/dev/null
  rg -n "Failed to fetch logs for app '\''--unknown-flag'\''" "$s" >/dev/null
'
```

Expected exit code:
- `0`.

Expected output:
- none required.

Artifacts:
- `scripts/verify-pr-d2-status-logs.sh`

Pass/fail rule:
- Pass only if command exits `0`.
- Fail on any non-zero exit.

Cleanup:
- none.

## 5.3 V3 - BATS structural test enforces new script assertions

Purpose:
- Ensure future edits cannot remove these checks without failing verifier-contract tests.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  t="tests/verify-pr-d2-status-logs.bats"
  rg -n "malformed-status\\.exit" "$t" >/dev/null
  rg -n "Unexpected malformed-status exit" "$t" >/dev/null
  rg -n "Unexpected malformed-status stdout" "$t" >/dev/null
  rg -n "malformed-logs\\.exit" "$t" >/dev/null
  rg -n "Unexpected malformed-logs exit" "$t" >/dev/null
  rg -n "Unexpected malformed-logs stdout" "$t" >/dev/null
'
```

Expected exit code:
- `0`.

Expected output:
- none required.

Artifacts:
- `tests/verify-pr-d2-status-logs.bats`

Pass/fail rule:
- Pass only if command exits `0`.
- Fail on any non-zero exit.

Cleanup:
- none.

## 5.4 V4 - Runtime failure behavior is explicitly guarded in verifier script

Purpose:
- Validate that verifier script itself now checks all failure invariants for malformed explicit app selection.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  s="scripts/verify-pr-d2-status-logs.sh"
  rg -n "malformed-status\\.out" "$s" >/dev/null
  rg -n "malformed-logs\\.out" "$s" >/dev/null
  rg -n "fallback-app" "$s" >/dev/null
  rg -n "No app specified" "$s" >/dev/null
'
```

Expected exit code:
- `0`.

Expected output:
- none required.

Artifacts:
- `scripts/verify-pr-d2-status-logs.sh`

Pass/fail rule:
- Pass only if command exits `0`.
- Fail on any non-zero exit.

Cleanup:
- none.

## 5.5 V5 - Out-of-scope invariant guard

Purpose:
- Prove no forbidden files changed while implementing this plan.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
git diff --name-only -- scripts/install.sh scripts/release-guard.sh

git diff --name-only -- tests/parity/baseline

git diff --name-only -- src
```

Expected exit code:
- all commands `0`.

Expected output:
- first command: empty
- second command: empty
- third command: empty

Artifacts:
- git working diff in current worktree

Pass/fail rule:
- Pass only if all three outputs are empty.
- Fail otherwise.

Cleanup:
- none.

## 5.6 V6 - Happy-path verifier contract remains present

Purpose:
- Prove this remediation does not remove existing happy-path verifier coverage.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  s="scripts/verify-pr-d2-status-logs.sh"
  rg -n "diff -u tests/parity/baseline/status\\.stdout\\.snap" "$s" >/dev/null
  rg -n "diff -u tests/parity/baseline/logs\\.stdout\\.snap" "$s" >/dev/null
  rg -n "PR-D2 status/logs verification passed\\." "$s" >/dev/null
'
```

Expected exit code:
- `0`.

Expected output:
- none required.

Artifacts:
- `scripts/verify-pr-d2-status-logs.sh`

Pass/fail rule:
- Pass only if command exits `0`.
- Fail on any non-zero exit.

Cleanup:
- none.

## 5.7 V7 - Runtime failure-path check for malformed explicit app

Purpose:
- Prove malformed explicit-flag commands fail with exit `1`, no stdout, and explicit app name in stderr.

Preconditions/setup:
- In worktree root.
- `npm install` completed.
- Local mock binaries under `tests/mocks` available.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  npm run build >/dev/null
  tmp="$(mktemp -d)"
  trap "rm -rf \"${tmp}\"" EXIT
  mkdir -p "${tmp}/config" "${tmp}/logs"
  printf "current_app: fallback-app\n" > "${tmp}/config/config.yaml"

  set +e
  PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
    MOCK_FLY_STATUS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
    ./hermes-fly status -a --unknown-flag >"${tmp}/status.out" 2>"${tmp}/status.err"
  status_exit="$?"
  set -e
  [[ "${status_exit}" -eq 1 ]]
  test ! -s "${tmp}/status.out"
  grep -qF "Failed to get status for app '\''--unknown-flag'\''" "${tmp}/status.err"
  ! grep -q "fallback-app" "${tmp}/status.err"
  ! grep -q "No app specified" "${tmp}/status.err"

  set +e
  PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
    MOCK_FLY_LOGS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
    ./hermes-fly logs -a --unknown-flag >"${tmp}/logs.out" 2>"${tmp}/logs.err"
  logs_exit="$?"
  set -e
  [[ "${logs_exit}" -eq 1 ]]
  test ! -s "${tmp}/logs.out"
  grep -qF "Failed to fetch logs for app '\''--unknown-flag'\''" "${tmp}/logs.err"
  ! grep -q "fallback-app" "${tmp}/logs.err"
  ! grep -q "No app specified" "${tmp}/logs.err"
'
```

Expected exit code:
- `0`.

Expected output:
- none required.

Artifacts:
- temporary files: `${tmp}/status.out`, `${tmp}/status.err`, `${tmp}/logs.out`, `${tmp}/logs.err`

Pass/fail rule:
- Pass only if command exits `0`.
- Fail on any non-zero exit.

Cleanup:
- temporary directory removed via trap.

## 5.8 V8 - End-to-end verifier happy-path check

Purpose:
- Prove verifier still succeeds end-to-end after adding new malformed-flag assertions.

Preconditions/setup:
- In worktree root.
- `npm install` completed.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
bash -euo pipefail -c '
  out="$(mktemp)"
  trap "rm -f \"${out}\"" EXIT
  ./scripts/verify-pr-d2-status-logs.sh >"${out}" 2>&1
  tail -1 "${out}" | grep -qF "PR-D2 status/logs verification passed."
'
```

Expected exit code:
- `0`.

Expected output:
- last verifier output line is exactly `PR-D2 status/logs verification passed.`

Artifacts:
- temporary output file created by check command

Pass/fail rule:
- Pass only if command exits `0` and last line matches exactly.
- Fail otherwise.

Cleanup:
- temporary output file removed via trap.

---

## 6) Completion Checklist

1. Step 4.1 implemented.
2. Step 4.2 implemented.
3. Step 4.3 implemented.
4. `V1` through `V8` all pass.
5. No out-of-scope file changes.

---

## 7) Supporting Information

1. This plan is self-contained and does not require external research.
2. No credentials, rollout controls, or migrations are required.
3. Rollback (before commit):

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
git restore scripts/verify-pr-d2-status-logs.sh tests/verify-pr-d2-status-logs.bats
```

---

## Execution Log

### Slice 1: Harden malformed status block in verifier script
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (exit=1, stdout empty, keep stderr assertions)
- [x] S5 WRITE_TEST: tests/verify-pr-d2-status-logs.bats — added 6 structural grep checks to existing malformed-flag test
- [x] S6 CONFIRM_RED: test 10 failed with "MISSING: malformed-status.exit assertion"
- [x] S7 IMPLEMENT: scripts/verify-pr-d2-status-logs.sh — replaced `|| true` with exit capture + exit=1 + stdout-empty assertions
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: Harden malformed logs block in verifier script
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (exit=1, stdout empty, keep stderr assertions)
- [x] S5 WRITE_TEST: shared with Slice 1 (6 structural checks cover both status and logs)
- [x] S6 CONFIRM_RED: confirmed RED via Slice 1 test run
- [x] S7 IMPLEMENT: scripts/verify-pr-d2-status-logs.sh — same pattern applied to logs block
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: Extend structural verifier-contract test
- [x] S4 ANALYZE_CRITERIA: 6 structural checks required (malformed-status.exit, Unexpected malformed-status exit, Unexpected malformed-status stdout, malformed-logs.exit, Unexpected malformed-logs exit, Unexpected malformed-logs stdout)
- [x] S5 WRITE_TEST: tests/verify-pr-d2-status-logs.bats — 6 grep checks added before script changes
- [x] S6 CONFIRM_RED: test 10 failed (RED) before script implementation
- [x] S7 IMPLEMENT: (covered by Slices 1+2 script changes)
- [x] S8 RUN_TESTS: 11/11 pass
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration, 11/11)
- Criteria walk: all satisfied — V1 PASS, V2 PASS, V3 PASS, V4 PASS, V5 PASS, V6 PASS, V7 PASS, V8 PASS
