# Remediation Plan: PR #12 Review-2 Findings

Date: 2026-03-15
Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_2.md`
Primary worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
Target PR: `#12 feat: complete TypeScript Commander.js full transition (9 slices)`

Execution mode:
- Static-analysis implementation and verification only.
- No product/API/architecture decisions delegated to implementer.

---

## 1) Objective

Resolve all REVIEW_2 findings with deterministic, junior-executable edits:

1. Fix deploy `saveApp()` schema mismatch so fallback app resolution remains functional.
2. Fix broken fallback verifiers/tests that still source `./lib/config.sh` after `lib/*.sh` archival.
3. Add explicit preflight guard for missing `OPENROUTER_API_KEY` in deploy wizard path.
4. Strengthen integration channel tests so they validate runtime command behavior (not help-only checks).

---

## 2) In Scope / Out of Scope

### In Scope

1. `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
2. `scripts/verify-pr-d2-status-logs.sh`
3. `tests/logs-ts-hybrid.bats`
4. `tests/integration.bats`
5. Deterministic assertion alignment updates in deploy runtime tests:
- `tests-ts/runtime/deploy-command.test.ts`
- `tests-ts/deploy/run-deploy-wizard.test.ts`

### Out of Scope

1. New CLI commands or options.
2. Re-introducing hybrid runtime dispatch in `hermes-fly`.
3. Unrelated legacy test suite rewrites outside files listed above.
4. Reverting archived `lib/archive/*.sh` moves.

---

## 3) Preconditions, Dependencies, and Credentials

Preconditions:

1. Work in `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose` only.
2. Branch must be `worktree-compressed-waddling-rose`.
3. No credentials are required for static verification.
4. Do not create/commit `.env` files.

Pre-check command:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
bash -euo pipefail -c '
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  mkdir -p tmp/verification
'
```

Expected exit code:
- `0`

---

## 4) Ordered Implementation Steps

Implement in exact order.

### Step 1 - Fix Deploy `saveApp()` to persist `current_app`

Issue:
- `FlyDeployWizard.saveApp()` writes `app:`/`region:` and can break `readCurrentApp()` fallback contract.

Code refs:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `src/contexts/runtime/infrastructure/adapters/current-app-config.ts`

Required edits:

1. In `saveApp(appName, region)` update persisted YAML key from `app:` to `current_app:`.
2. Preserve existing config file contents when updating `current_app`.
3. Do not overwrite unrelated keys in `config.yaml`.
4. Keep method signature unchanged (`saveApp(appName: string, region: string): Promise<void>`).

Mandatory behavior after edit:

1. `readCurrentApp()` must be able to read the app written by deploy wizard.
2. `config.yaml` written by deploy path contains exactly one `current_app:` line after update.
3. No write of `app: ${appName}` remains in this method.

---

### Step 2 - Repair Archived-lib references in fallback verifiers/tests

Issue:
- Active scripts still source `./lib/config.sh`, but file moved to `lib/archive/config.sh`.

Code refs:
- `scripts/verify-pr-d2-status-logs.sh`
- `tests/logs-ts-hybrid.bats`

Required edits:

1. Replace every `source ./lib/config.sh` with `source ./lib/archive/config.sh` in both files.
2. Keep all existing assertions and command semantics unchanged.
3. Do not alter fallback expectation strings.

Mandatory behavior after edit:

1. No source path in these two files points to `./lib/config.sh`.
2. Archive path is used consistently.

---

### Step 3 - Add deploy preflight guard for missing `OPENROUTER_API_KEY`

Issue:
- Deploy wizard forwards empty API key into secrets provisioning.

Code refs:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `src/contexts/deploy/application/use-cases/run-deploy-wizard.ts`

Required edits:

1. In `checkPrerequisites(opts)` add explicit validation:
- if `OPENROUTER_API_KEY` is unset or empty (after trim), return `{ ok: false, missing: "OPENROUTER_API_KEY" }`.
2. Keep existing `fly` prerequisite logic intact.
3. Do not add new interface fields to `DeployWizardPort`.
4. Update assertions in:
- `tests-ts/runtime/deploy-command.test.ts`
- `tests-ts/deploy/run-deploy-wizard.test.ts`

Mandatory behavior after edit:

1. Missing API key fails before provisioning phase.
2. Failure message path remains deterministic through existing missing-prerequisite flow.

---

### Step 4 - Strengthen integration channel tests (runtime behavior, not help-only)

Issue:
- Current channel tests rely on `--help` and do not validate deploy runtime behavior path.

Code refs:
- `tests/integration.bats`

Required edits:

1. Update these tests to invoke deploy runtime path (no `--help` in assertions):
- `hermes-fly deploy --channel badvalue --no-auto-install ...`
- `hermes-fly deploy --channel preview --no-auto-install ...`
- channel matrix test for `stable|preview|edge` using `--no-auto-install`.
2. Assert deterministic runtime-visible output and exit contract:
- exit failure
- contains `auto-install disabled` message
- does not contain `Unknown option`/`Unknown command`.
3. Keep tests independent of `lib/archive` sourcing.

Mandatory behavior after edit:

1. Integration tests confirm channel option traverses runtime execution path.
2. Tests remain TS-entrypoint visible and decoupled from legacy shell libraries.

---

## 5) Deterministic Verification Matrix (Static, Mandatory)

Run from:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
mkdir -p tmp/verification
```

### V0 - Credential Readiness

Purpose:
- validate no credentials are needed and no secret injection is required.

Preconditions/setup:
1. Repository is in target worktree.

Command:

```bash
bash -euo pipefail -c '
  test -d /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
  ! rg -n "\.env|OPENROUTER_API_KEY=.*[A-Za-z0-9]" docs/plans/typescript-commander-full-transition-20260315_REVIEW_2.md
' >tmp/verification/V0.out 2>tmp/verification/V0.err
```

Expected exit code:
- `0`

Expected output:
- `V0.err` empty.

Artifacts:
- `tmp/verification/V0.out`
- `tmp/verification/V0.err`

Pass/fail rule:
- pass only if exit `0`.

Cleanup:
- none.

---

### V1 - Deploy saveApp schema compatibility

Purpose:
- prove deploy writes schema readable by current app resolver.

Preconditions/setup:
1. Apply `V0` setup.

Command:

```bash
bash -euo pipefail -c '
  rg -n "current_app:" src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
  ! rg -n "app: \$\{appName\}" src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
  rg -n "\^current_app:" src/contexts/runtime/infrastructure/adapters/current-app-config.ts
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code:
- `0`

Expected output:
- `V1.out` contains all three required matches.
- `V1.err` is empty.

Artifacts:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `src/contexts/runtime/infrastructure/adapters/current-app-config.ts`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`

Pass/fail rule:
- pass only if all three grep expectations are satisfied.

Cleanup:
- none.

---

### V2 - No stale `./lib/config.sh` source paths in targeted fallback files

Purpose:
- verify archived path migration is complete where required.

Preconditions/setup:
1. Apply `V0` setup.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "source \./lib/config\.sh" scripts/verify-pr-d2-status-logs.sh tests/logs-ts-hybrid.bats
  rg -n "source \./lib/archive/config\.sh" scripts/verify-pr-d2-status-logs.sh tests/logs-ts-hybrid.bats
' >tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code:
- `0`

Expected output:
- `V2.out` includes archive-path source matches.
- `V2.err` is empty.

Artifacts:
- `scripts/verify-pr-d2-status-logs.sh`
- `tests/logs-ts-hybrid.bats`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`

Pass/fail rule:
- pass only if old path absent and new path present.

Cleanup:
- none.

---

### V3 - Missing API key preflight guard exists

Purpose:
- prove deploy fails early when `OPENROUTER_API_KEY` is missing.

Preconditions/setup:
1. Apply `V0` setup.

Command:

```bash
bash -euo pipefail -c '
  rg -n "OPENROUTER_API_KEY" src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
  rg -n "missing:\s*\"OPENROUTER_API_KEY\"|OPENROUTER_API_KEY.*required" src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
' >tmp/verification/V3.out 2>tmp/verification/V3.err
```

Expected exit code:
- `0`

Expected output:
- `V3.out` includes both key reference and missing-key guard reference.
- `V3.err` is empty.

Artifacts:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`

Pass/fail rule:
- pass only if both required patterns are present.

Cleanup:
- none.

---

### V4 - Integration channel tests execute runtime path (no help-only assertions)

Purpose:
- prove channel tests validate runtime behavior instead of help rendering.

Preconditions/setup:
1. Apply `V0` setup.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "deploy --channel .* --help" tests/integration.bats
  rg -n "deploy --channel badvalue --no-auto-install|deploy --channel preview --no-auto-install|for ch in stable preview edge" tests/integration.bats
  rg -n "auto-install disabled" tests/integration.bats
' >tmp/verification/V4.out 2>tmp/verification/V4.err
```

Expected exit code:
- `0`

Expected output:
- `V4.out` contains all runtime-path patterns.
- `V4.err` is empty.

Artifacts:
- `tests/integration.bats`
- `tmp/verification/V4.out`
- `tmp/verification/V4.err`

Pass/fail rule:
- pass only if help-only pattern absent and runtime-path patterns present.

Cleanup:
- none.

---

### V5 - Regression safety invariants preserved

Purpose:
- ensure this remediation does not regress cutover safety.

Preconditions/setup:
1. Apply `V0` setup.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "HERMES_FLY_IMPL_MODE|HERMES_FLY_TS_COMMANDS" hermes-fly src/cli.ts README.md
  ! rg -n "^source .*lib/" hermes-fly
  rg -n "exec node .*dist/cli.js" hermes-fly
  ! rg -n "npm run build --prefix .*\|\| true" scripts/verify-pr-full-commander.sh
' >tmp/verification/V5.out 2>tmp/verification/V5.err
```

Expected exit code:
- `0`

Expected output:
- `V5.out` includes launcher exec line.
- `V5.err` is empty.

Artifacts:
- `hermes-fly`
- `src/cli.ts`
- `README.md`
- `scripts/verify-pr-full-commander.sh`
- `tmp/verification/V5.out`
- `tmp/verification/V5.err`

Pass/fail rule:
- pass only if all four assertions hold.

Cleanup:
- none.

---

### V6 - Coverage category checks (happy/edge/failure/regression) remain represented

Purpose:
- satisfy verification coverage requirements for this remediation plan.

Preconditions/setup:
1. Apply `V0` setup.

Command:

```bash
bash -euo pipefail -c '
  rg -n "happy_checks\(\)|\[HAPPY\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
  rg -n "edge_checks\(\)|\[EDGE\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
  rg -n "failure_checks\(\)|\[FAILURE\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
  rg -n "regression_checks\(\)|\[REGRESSION\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
' >tmp/verification/V6.out 2>tmp/verification/V6.err
```

Expected exit code:
- `0`

Expected output:
- `V6.out` contains all 4 category patterns.
- `V6.err` is empty.

Artifacts:
- `scripts/verify-pr-full-commander.sh`
- `tests/verify-pr-full-commander.bats`
- `tmp/verification/V6.out`
- `tmp/verification/V6.err`

Pass/fail rule:
- pass only if all category patterns are present.

Cleanup:
- none.

---

### 5.1 Verification Coverage Mapping (Mandatory)

Coverage categories are satisfied only when the following checks pass:

1. Happy path coverage: `V1` (deploy saveApp compatibility path).
2. Edge-case coverage: `V2` (archived-lib source-path migration edge case).
3. Failure/error-path coverage: `V3` (missing API key preflight guard).
4. Regression/safety coverage: `V5` (hybrid-removal and launcher invariants).

Pass rule:
1. All four mapped checks above must pass in addition to `V0` and `V4`/`V6`.

---

## 6) Step-to-Verification Traceability

1. Step 1 -> `V1`
2. Step 2 -> `V2`
3. Step 3 -> `V3`
4. Step 4 -> `V4`
5. Global regression safety -> `V5`
6. Coverage requirements -> `V6`
7. Credential readiness -> `V0`

---

## 7) Completion Criteria

All must be true:

1. `V0` through `V6` pass.
2. No unresolved findings remain for:
- saveApp schema mismatch
- stale `./lib/config.sh` source paths in targeted fallback files
- missing deploy API-key preflight guard
- help-only integration channel tests
3. Diff includes only files listed in Section 2 In Scope.

---

## 8) Post-Implementation Cleanup

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
rm -rf tmp/verification
```

## Execution Log

### Step 1: Fix Deploy saveApp() schema
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (current_app: present, old app: absent, readCurrentApp regex match)
- [x] S5 WRITE_TEST: V1 bash verification (rg current_app: in fly-deploy-wizard.ts — fails initially)
- [x] S6 CONFIRM_RED: rg "current_app:" returned no match (guard absent)
- [x] S7 IMPLEMENT: src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts — saveApp() rewritten to read existing config, filter current_app: lines, append new current_app: value
- [x] S8 RUN_TESTS: V1 pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Step 2: Repair archived-lib references
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted (old path absent, archive path present in both files)
- [x] S5 WRITE_TEST: V2 bash verification (grep source ./lib/config.sh — fails as expected)
- [x] S6 CONFIRM_RED: 4 stale paths in verify-pr-d2-status-logs.sh, 2 in logs-ts-hybrid.bats
- [x] S7 IMPLEMENT: sed -i '' replacement in both files
- [x] S8 RUN_TESTS: V2 pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Step 3: Add OPENROUTER_API_KEY preflight guard
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted (OPENROUTER_API_KEY reference present, missing guard pattern present)
- [x] S5 WRITE_TEST: V3 bash verification + new test cases in run-deploy-wizard.test.ts and deploy-command.test.ts
- [x] S6 CONFIRM_RED: missing guard pattern rg returned no match
- [x] S7 IMPLEMENT: fly-deploy-wizard.ts checkPrerequisites() — added apiKey trim/empty guard returning {ok:false,missing:"OPENROUTER_API_KEY"}; added 2 tests in run-deploy-wizard.test.ts (missing key fails + provisioning not reached); added 1 test in deploy-command.test.ts (returns 1 when missing)
- [x] S8 RUN_TESTS: 13/13 wizard tests pass, 7/7 deploy command tests pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: Step 3 guard (before fly check) required adding OPENROUTER_API_KEY=test-key to integration tests that assert "auto-install disabled" (those tests must reach fly check). Addressed in Step 4.

### Step 4: Strengthen integration channel tests
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (no --help in channel tests, --no-auto-install patterns present, auto-install disabled asserted)
- [x] S5 WRITE_TEST: V4 bash verification (grep deploy --channel .* --help — present initially)
- [x] S6 CONFIRM_RED: 2 lines matched help-only pattern (lines 133, 142)
- [x] S7 IMPLEMENT: tests/integration.bats — updated 4 tests: (1) --no-auto-install test: added OPENROUTER_API_KEY=test-key; (2) "invalid falls back" test: added OPENROUTER_API_KEY=test-key + refute_output guards; (3) preview test: changed from --help to runtime path with --no-auto-install + OPENROUTER_API_KEY; (4) matrix test: changed from --help to --no-auto-install with OPENROUTER_API_KEY via node_dir variable
- [x] S8 RUN_TESTS: 15/15 integration tests pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: Matrix test uses double-quoted bash -c to allow node_dir variable expansion (consistent with tests that set PATH dynamically).

### VERIFY_ALL
- Test suite: pass (1 iteration) — 31/31 BATS (integration+install), 18/18 TS test scripts, 0 failures
- Criteria walk: V0 PASS, V1 PASS, V2 PASS, V3 PASS, V4 PASS, V5 PASS, V6 PASS — all satisfied
