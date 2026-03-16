# PR-D2 REVIEW-5 Execution Plan: Resolve-App Explicit-Flag Safety Fix + Regression Gate

Date: 2026-03-14  
Parent plans/reports:  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_4.md`  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d2-status-logs-review-2-implementation-report.md`  
Context: Post-REVIEW-4 follow-up to close remaining HIGH finding in static review  
Worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky`  
Target branch: `worktree-majestic-hatching-sky`  
Assignee profile: Junior developer

## Implementation Status

Status: Ready for implementation  
Primary outcome: prevent silent fallback to `current_app` when user supplied explicit `-a`, and lock this behavior with deterministic tests + verifier checks.

---

## 1) Finding To Resolve

### F1 (HIGH): `resolveApp` may target wrong app for malformed explicit `-a`

Code references:
- `src/commands/resolve-app.ts`
- `tests-ts/runtime/show-status.test.ts`
- `tests-ts/runtime/show-logs.test.ts`
- `scripts/verify-pr-d2-status-logs.sh`
- `tests/verify-pr-d2-status-logs.bats`

Problem summary:
1. Current TS logic can clear explicit app and fall back to `current_app` when `-a` is followed by a hyphen-prefixed token.
2. This can execute against the wrong app without user intent.
3. Existing comment in `resolve-app.ts` claims parity semantics that do not hold after this behavior drift.

Required behavior after fix:
1. If no `-a` appears: use `current_app` fallback.
2. If `-a` appears and has a following token (including `--unknown-flag`): treat token as explicit app.
3. If `-a` appears with no following token: return `null`.
4. Last explicit `-a VALUE` wins.

---

## 2) Scope

### In Scope

1. Update explicit-flag parse logic in `src/commands/resolve-app.ts`.
2. Update runtime tests in:
- `tests-ts/runtime/show-status.test.ts`
- `tests-ts/runtime/show-logs.test.ts`
3. Add verifier runtime assertions in `scripts/verify-pr-d2-status-logs.sh` for explicit malformed-flag behavior.
4. Add corresponding structural checks in `tests/verify-pr-d2-status-logs.bats`.

### Out of Scope

1. No changes to any `src/` files except `src/commands/resolve-app.ts`.
2. No changes to `scripts/install.sh`.
3. No changes to `scripts/release-guard.sh`.
4. No changes to `tests/parity/baseline/*`.
5. No command-routing architecture changes.

---

## 3) Preconditions, Dependencies, and Credential Readiness

## 3.1 Working Directory

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
```

## 3.2 Required Tooling

- `bash`
- `node`
- `npm`
- `rg`
- `tests/bats/bin/bats`

## 3.3 Dependency Readiness

If dependencies are missing, run once:

```bash
npm install
```

## 3.4 Credentials

No credentials are required for this patch.

Reason:
- All verification commands rely on local mocks (`tests/mocks`) and local unit tests.

Secret handling constraints:
1. Do not create or modify `.env*` files for this patch.
2. Do not commit secrets or tokens.

---

## 4) Ordered Implementation Steps (No Decisions Delegated)

Perform steps exactly in order.

## 4.1 Step 1 - Update explicit `-a` parsing in resolve-app

File: `src/commands/resolve-app.ts`

Implement exactly:
1. Introduce `seenExplicitFlag` boolean.
2. On each `-a` token:
- If next token exists: store as explicit app value (last wins), advance index by one.
- If next token does not exist: mark explicit value as missing.
3. Return logic:
- If `seenExplicitFlag` and explicit value present -> return explicit value.
- If `seenExplicitFlag` and explicit value missing -> return `null`.
- If `seenExplicitFlag` is false -> return `readCurrentApp({ env: options.env })`.
4. Remove hyphen-prefix rejection check (`startsWith("-")`).
5. Update the function comment so it matches implemented behavior exactly.

## 4.2 Step 2 - Update status runtime tests

File: `tests-ts/runtime/show-status.test.ts`

Apply these exact expectation changes:
1. `resolveApp(["-a", "--unknown-flag"], envWithCurrentApp)` must assert `"--unknown-flag"`.
2. `resolveApp(["-a", "first", "-a"], envWithCurrentApp)` must assert `null`.
3. Keep `resolveApp(["-a", "first", "-a"], envWithoutCurrentApp)` asserting `null`.

## 4.3 Step 3 - Add logs explicit malformed-flag edge test

File: `tests-ts/runtime/show-logs.test.ts`

Add one dedicated test with exact scenario:
1. Create config with `current_app: fallback-app`.
2. Use mock `LogsReaderPort` that emits `logs for ${app}\n` on stream callback.
3. Execute `runLogsCommand(["-a", "--unknown-flag"], ...)`.
4. Assert:
- exit code `0`
- stdout exactly `logs for --unknown-flag\n`
- stderr exactly empty string

Keep existing trailing `-a` no-value test unchanged.

## 4.4 Step 4 - Add deterministic verifier runtime assertions (status + logs)

File: `scripts/verify-pr-d2-status-logs.sh`

Add both assertion blocks (not optional):

1. **Status explicit malformed-flag block**
- Setup config with `current_app: fallback-app`.
- Run with mocks + failure mode:
  - `MOCK_FLY_STATUS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status -a --unknown-flag`
- Assert:
  - stderr contains `Failed to get status for app '--unknown-flag'`
  - stderr does **not** contain `fallback-app`
  - stderr does **not** contain `No app specified`

2. **Logs explicit malformed-flag block**
- Setup config with `current_app: fallback-app`.
- Run with mocks + failure mode:
  - `MOCK_FLY_LOGS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs -a --unknown-flag`
- Assert:
  - stderr contains `Failed to fetch logs for app '--unknown-flag'`
  - stderr does **not** contain `fallback-app`
  - stderr does **not** contain `No app specified`

## 4.5 Step 5 - Add verifier-contract structural checks

File: `tests/verify-pr-d2-status-logs.bats`

Add one new test block that structurally checks `scripts/verify-pr-d2-status-logs.sh` contains:
1. `status -a --unknown-flag` assertion block.
2. `logs -a --unknown-flag` assertion block.
3. Negative assertions for both:
- not containing `fallback-app`
- not containing `No app specified`

---

## 5) Deterministic Verification Criteria

All checks are mandatory.

## 5.0 Step-to-Verification Traceability

- Step 4.1 -> `V1`, `V2`
- Step 4.2 -> `V3`
- Step 4.3 -> `V4`, `V8`
- Step 4.4 -> `V5`, `V8`
- Step 4.5 -> `V6`
- Scope invariants -> `V7`
- Happy-path safety -> `V9`

## 5.1 V1 - Explicit hyphen-prefixed value is no longer filtered

Purpose:
- Prove parser removed `startsWith("-")` filter.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n "startsWith\(\"-\"\)" src/commands/resolve-app.ts
```

Expected exit code:
- `1`.

Expected output/artifacts:
- no output.

Pass/fail rule:
- Pass if exit code is `1`.
- Fail otherwise.

Cleanup:
- none.

## 5.2 V2 - Explicit-flag branch structure is deterministic

Purpose:
- Prove `seenExplicitFlag` gating exists and fallback only occurs when no explicit flag was provided.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n "seenExplicitFlag" src/commands/resolve-app.ts
rg -n "if \(seenExplicitFlag\)" src/commands/resolve-app.ts
rg -n "return readCurrentApp\(" src/commands/resolve-app.ts
```

Expected exit code:
- all 3 commands exit `0`.

Expected output/artifacts:
- first two commands show explicit-flag branch logic.
- third command shows fallback return path.

Pass/fail rule:
- Pass only if all 3 commands match.
- Fail otherwise.

Cleanup:
- none.

## 5.3 V3 - Status tests enforce explicit malformed-flag semantics

Purpose:
- Prove status test expectations were updated to new contract.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n "resolveApp\(\[\"-a\", \"--unknown-flag\"\]" tests-ts/runtime/show-status.test.ts
rg -n "assert\.equal\(app, \"--unknown-flag\"\)" tests-ts/runtime/show-status.test.ts
rg -n "resolveApp\(\[\"-a\", \"first\", \"-a\"\], envWithCurrentApp\)" tests-ts/runtime/show-status.test.ts
rg -n "assert\.equal\(app, null\)" tests-ts/runtime/show-status.test.ts
```

Expected exit code:
- all 4 commands exit `0`.

Expected output/artifacts:
- matches for unknown-flag explicit app and trailing-`-a` -> null behavior.

Pass/fail rule:
- Pass only if all 4 matches exist.
- Fail otherwise.

Cleanup:
- none.

## 5.4 V4 - Logs runtime test enforces explicit malformed-flag semantics

Purpose:
- Prove logs test suite contains deterministic explicit malformed-flag case.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n "runLogsCommand\(\[\"-a\", \"--unknown-flag\"\]" tests-ts/runtime/show-logs.test.ts
rg -n "logs for --unknown-flag" tests-ts/runtime/show-logs.test.ts
```

Expected exit code:
- both commands exit `0`.

Expected output/artifacts:
- dedicated test case and exact stdout assertion for explicit app value.

Pass/fail rule:
- Pass only if both matches exist.
- Fail otherwise.

Cleanup:
- none.

## 5.5 V5 - Verifier script includes status+logs malformed-flag runtime assertions

Purpose:
- Prove verifier script enforces this regression class.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n -- "status -a --unknown-flag" scripts/verify-pr-d2-status-logs.sh
rg -n -- "logs -a --unknown-flag" scripts/verify-pr-d2-status-logs.sh
rg -n -- "fallback-app" scripts/verify-pr-d2-status-logs.sh
rg -n -- "No app specified" scripts/verify-pr-d2-status-logs.sh
```

Expected exit code:
- all 4 commands exit `0`.

Expected output/artifacts:
- status block and logs block present.
- negative assertions for fallback/no-app present in script.

Pass/fail rule:
- Pass only if all 4 matches exist.
- Fail otherwise.

Cleanup:
- none.

## 5.6 V6 - Verifier bats contract enforces new script assertions

Purpose:
- Ensure verifier-contract tests will fail if malformed-flag script assertions are removed.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
rg -n -- "status -a --unknown-flag" tests/verify-pr-d2-status-logs.bats
rg -n -- "logs -a --unknown-flag" tests/verify-pr-d2-status-logs.bats
rg -n -- "fallback-app" tests/verify-pr-d2-status-logs.bats
rg -n -- "No app specified" tests/verify-pr-d2-status-logs.bats
```

Expected exit code:
- all 4 commands exit `0`.

Expected output/artifacts:
- structural test lines referencing all required script assertions.

Pass/fail rule:
- Pass only if all 4 commands match.
- Fail otherwise.

Cleanup:
- none.

## 5.7 V7 - Out-of-scope regression guard

Purpose:
- Prove forbidden files were not modified.

Preconditions/setup:
- In worktree root.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
git diff --name-only -- scripts/install.sh scripts/release-guard.sh

git diff --name-only -- tests/parity/baseline

git diff --name-only -- src | rg -v "^src/commands/resolve-app\.ts$"
```

Expected exit code:
- first two commands exit `0` with empty output.
- third pipeline exits `1`.

Expected output/artifacts:
- no output from all checks.

Pass/fail rule:
- Pass only if outputs are empty and exit codes match expected values.
- Fail otherwise.

Cleanup:
- none.

## 5.8 V8 - Failure-path runtime proof (explicit malformed app is used)

Purpose:
- Prove runtime error path uses explicit malformed app value, not fallback app.

Preconditions/setup:
- In worktree root.
- `npm install` completed.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
npm run build

tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
printf "current_app: fallback-app\n" > "${tmp}/config/config.yaml"

PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  MOCK_FLY_STATUS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status \
  ./hermes-fly status -a --unknown-flag >"${tmp}/status.out" 2>"${tmp}/status.err" || true

PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  MOCK_FLY_LOGS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
  ./hermes-fly logs -a --unknown-flag >"${tmp}/logs.out" 2>"${tmp}/logs.err" || true

grep -F "Failed to get status for app '--unknown-flag'" "${tmp}/status.err"
grep -F "Failed to fetch logs for app '--unknown-flag'" "${tmp}/logs.err"
if grep -q "fallback-app" "${tmp}/status.err" "${tmp}/logs.err"; then exit 1; fi
if grep -q "No app specified" "${tmp}/status.err" "${tmp}/logs.err"; then exit 1; fi

rm -rf "${tmp}"
```

Expected exit code:
- overall block exits `0`.

Expected output/artifacts:
- grep outputs include explicit `--unknown-flag` error lines.
- no `fallback-app` and no `No app specified` in stderr artifacts.

Pass/fail rule:
- Pass only if all grep assertions succeed and both negative checks remain empty.
- Fail otherwise.

Cleanup:
- removes temporary directory.

## 5.9 V9 - Happy-path regression safety (runtime tests)

Purpose:
- Prove status/logs runtime suites still pass after resolve-app behavior fix.

Preconditions/setup:
- In worktree root.
- `npm install` completed.

Commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
npm run test:runtime-status
npm run test:runtime-logs
```

Expected exit code:
- both commands exit `0`.

Expected output/artifacts:
- command output contains test runner completion for both files.
- no failing assertions.

Pass/fail rule:
- Pass only if both commands return exit code `0`.
- Fail otherwise.

Cleanup:
- none.

---

## 6) Completion Checklist

1. Steps 4.1 through 4.5 implemented exactly.
2. Verification checks `V1` through `V9` all pass.
3. No out-of-scope file changes.
4. Commit message includes: `fix(pr-d2-review5): resolve-app explicit -a safety + verifier guard`.

---

## 7) Supporting Information

1. This plan is self-contained; no external research is required.
2. No credentials, migrations, feature flags, rollout, or release-guard changes are required.
3. Rollback (before commit) for this plan scope:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
git restore src/commands/resolve-app.ts tests-ts/runtime/show-status.test.ts tests-ts/runtime/show-logs.test.ts scripts/verify-pr-d2-status-logs.sh tests/verify-pr-d2-status-logs.bats
```

---

## Execution Log

### Slice 1: resolve-app.ts explicit-flag parse logic
- [x] S4 ANALYZE_CRITERIA: V1 (startsWith filter removed), V2 (seenExplicitFlag structure), V7 (scope), V8 (runtime proof), V9 (happy-path)
- [x] S5 WRITE_TEST: updated show-status.test.ts expectations (3 tests) + show-logs.test.ts (1 updated, 1 added) to new contract — these fail against old impl
- [x] S6 CONFIRM_RED: 3 failures in test:runtime-status, 2 failures in test:runtime-logs
- [x] S7 IMPLEMENT: src/commands/resolve-app.ts — removed startsWith("-") guard, added seenExplicitFlag boolean, new return logic
- [x] S8 RUN_TESTS: pass (1 iteration) — 31/31 status, 17/17 logs
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: S5 included test updates for Slices 2+3 (status and logs test expectations) to enable RED confirmation before implementation. Show-status tests refactored to use named `envWithCurrentApp` variable to satisfy V3 rg patterns.

### Slice 2: show-status.test.ts expectations
- [x] S4 ANALYZE_CRITERIA: V3 (4 rg patterns), updated alongside Slice 1 test phase
- [x] S5 WRITE_TEST: 3 tests updated — `-a without a value` → null, trailing `-a` with current app → null, `--unknown-flag` → `"--unknown-flag"`; named variable `envWithCurrentApp` extracted
- [x] S6 CONFIRM_RED: covered by Slice 1 RED run
- [x] S7 IMPLEMENT: covered by Slice 1 implementation
- [x] S8 RUN_TESTS: pass (1 iteration) — 31/31
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: show-logs.test.ts explicit malformed-flag test
- [x] S4 ANALYZE_CRITERIA: V4 (2 rg patterns), updated alongside Slice 1 test phase
- [x] S5 WRITE_TEST: `-a without value` test updated to assert no-app error; new test added for `[-a, --unknown-flag]` → exit 0, stdout `logs for --unknown-flag\n`, stderr empty
- [x] S6 CONFIRM_RED: covered by Slice 1 RED run (2 failures in test:runtime-logs)
- [x] S7 IMPLEMENT: covered by Slice 1 implementation
- [x] S8 RUN_TESTS: pass (1 iteration) — 17/17
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: verify-pr-d2-status-logs.sh malformed-flag assertions
- [x] S4 ANALYZE_CRITERIA: V5 (4 rg patterns), V8 (runtime proof via script)
- [x] S5 WRITE_TEST: added status + logs malformed-flag blocks to verifier script
- [x] S6 CONFIRM_RED: N/A (verifier script additions are additive; confirmed via V5 rg before and after)
- [x] S7 IMPLEMENT: scripts/verify-pr-d2-status-logs.sh — added status -a --unknown-flag and logs -a --unknown-flag assertion blocks with negative checks
- [x] S8 RUN_TESTS: pass (1 iteration) — bats ok 2 (verifier exits 0)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 5: verify-pr-d2-status-logs.bats structural checks
- [x] S4 ANALYZE_CRITERIA: V6 (4 rg patterns)
- [x] S5 WRITE_TEST: new bats test block added checking structural presence of malformed-flag assertions
- [x] S6 CONFIRM_RED: N/A (structural check is additive)
- [x] S7 IMPLEMENT: tests/verify-pr-d2-status-logs.bats — new @test block with grep + arithmetic count checks
- [x] S8 RUN_TESTS: pass (1 iteration) — 11/11 bats, ok 10 is new test
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration) — 31/31 test:runtime-status, 17/17 test:runtime-logs, 11/11 bats verify-pr-d2-status-logs.bats
- Criteria walk: all satisfied — V1 ✓ V2 ✓ V3 ✓ V4 ✓ V5 ✓ V6 ✓ V7 ✓ V8 ✓ V9 ✓
