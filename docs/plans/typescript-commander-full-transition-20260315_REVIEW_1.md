# Remediation Plan: PR #12 Full Commander Transition Review Findings

Date: 2026-03-15

Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_1.md`

Source PR:
- `#12 feat: complete TypeScript Commander.js full transition (9 slices)`
- Branch: `worktree-compressed-waddling-rose -> main`
- Worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
- Compare: `b7cb6ae...177f044`

Execution mode:
- Static-analysis implementation plan with deterministic static verification commands.
- Do not introduce product/API/architecture decisions beyond what is fixed in this plan.

---

## 1) Objective

Close all review findings from PR #12 so the implementation matches the TS-only Commander end-state contract:

1. Deploy command must execute a real production TS flow (not a hard-disabled stub).
2. README must no longer document removed hybrid migration env flags.
3. Legacy runtime `lib/*.sh` root files must be decommissioned (archived), and active TS transition scripts/tests must not source them.
4. Final verifier must fail hard on build failure.
5. Integration version checks must read version from `src/version.ts` contract, not legacy launcher variables.

---

## 2) In Scope and Out of Scope

### In Scope

1. `src/commands/deploy.ts` production wiring fix.
2. New deploy wizard concrete adapter for production path.
3. `README.md` migration-flag content cleanup.
4. `scripts/install.sh`, `tests/install.bats`, `tests/integration.bats` removal of active `lib/` coupling.
5. `scripts/verify-pr-full-commander.sh` build strictness fix.
6. Archiving legacy runtime Bash files out of `lib/*.sh` root.

### Out of Scope

1. New CLI commands or flags.
2. Changing user-visible semantics for already-green `list/status/logs/resume/doctor/destroy` contracts.
3. Refactoring unrelated legacy test suites beyond references explicitly listed in this plan.

---

## 3) Preconditions and Safety

1. Work only in: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.
2. No credentials required.
3. Do not commit plaintext secrets or `.env` files.
4. Preserve `hermes-fly` executable path and TS entrypoint (`dist/cli.js`).
5. Keep changes constrained to files listed in Section 4.

Pre-check commands:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
git rev-parse --abbrev-ref HEAD
git status --short
```

Expected:
- Branch is `worktree-compressed-waddling-rose`.
- Only expected PR files are modified.

---

## 4) Ordered Implementation Steps

Implement in exact order.

### Step 1 - Replace Deploy Hard-Disabled Production Path

Issue addressed:
- High: `deploy` currently returns `interactive wizard not available in this build` in production.

Code refs:
- `src/commands/deploy.ts`
- `src/contexts/deploy/application/ports/deploy-wizard.port.ts`
- `src/contexts/deploy/application/use-cases/run-deploy-wizard.ts`
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-runner.ts`
- `src/contexts/deploy/infrastructure/adapters/template-writer.ts`
- `src/contexts/deploy/infrastructure/config-repository.ts`
- `src/adapters/process.ts`

Edits:

1. Create `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`.
2. Implement one concrete class that `implements DeployWizardPort` and composes existing deploy adapters/use-cases.
3. In `src/commands/deploy.ts`, replace the `if (!wizard) { ... not available ... return 1; }` branch with deterministic default construction:
- `const wizard = options.wizard ?? new <ConcreteDeployWizard>(...)`
- always execute `RunDeployWizardUseCase`.
4. Keep existing `--no-auto-install` and `--channel` parsing behavior unchanged.
5. Remove the literal string `deploy: interactive wizard not available in this build` from production code.

Scope guard:
- Do not alter command names/options in `src/cli.ts`.

---

### Step 2 - Remove Hybrid Migration Flags from README

Issue addressed:
- High: README still documents removed hybrid env flags.

Code refs:
- `README.md`

Edits:

1. Remove section `## Developer Migration Flags` and all examples referencing:
- `HERMES_FLY_IMPL_MODE`
- `HERMES_FLY_TS_COMMANDS`
2. Add replacement TS-native runtime note:
- `hermes-fly` dispatches through Commander/TypeScript runtime (`node dist/cli.js`).
- No migration env flags are required.

Scope guard:
- Keep all non-migration docs sections intact.

---

### Step 3 - Decommission Root `lib/*.sh` Runtime Files and Remove Active Coupling

Issues addressed:
- Medium: root `lib/*.sh` still present.
- Medium: active TS transition scripts/tests still depend on `lib/`.

Code refs:
- `lib/*.sh`
- `scripts/install.sh`
- `tests/install.bats`
- `tests/integration.bats`

Edits:

1. Archive legacy shell files:
- create `lib/archive/`
- move all current root `lib/*.sh` into `lib/archive/`
- after move, root `lib/` must contain zero `*.sh` files.
- expected archived file set (exact):
  - `lib/archive/config.sh`
  - `lib/archive/deploy.sh`
  - `lib/archive/destroy.sh`
  - `lib/archive/docker-helpers.sh`
  - `lib/archive/doctor.sh`
  - `lib/archive/fly-helpers.sh`
  - `lib/archive/list.sh`
  - `lib/archive/logs.sh`
  - `lib/archive/messaging.sh`
  - `lib/archive/openrouter.sh`
  - `lib/archive/prereqs.sh`
  - `lib/archive/reasoning.sh`
  - `lib/archive/status.sh`
  - `lib/archive/ui.sh`

2. Update `scripts/install.sh`:
- remove copy block for `src_dir/lib`.
- keep copy of `hermes-fly`, `dist/`, `templates/`, `data/`, and `package.json`.

3. Update `tests/install.bats`:
- remove assertions requiring `${dest}/lib/ui.sh`.
- keep TS runtime assertions (launcher + `dist/cli.js` copy behavior).

4. Update `tests/integration.bats`:
- remove tests that source `lib/*.sh` directly.
- replace those cases with TS-entrypoint-visible assertions only.

Scope guard:
- Do not add any new root `lib/*.sh` compatibility shim files.

---

### Step 4 - Make Final Verifier Fail on Build Errors

Issue addressed:
- Medium: final verifier currently masks build failures.

Code refs:
- `scripts/verify-pr-full-commander.sh`

Edits:

1. Replace build line:
- from: `npm run build --prefix "${PROJECT_ROOT}" >/dev/null 2>&1 || true`
- to: strict failing form without `|| true`.
2. Keep all category outputs unchanged:
- `[HAPPY] PASS`
- `[EDGE] PASS`
- `[FAILURE] PASS`
- `[REGRESSION] PASS`
- `Full Commander transition verification passed.`

---

### Step 5 - Fix Integration Version Source Contract

Issue addressed:
- Low: integration tests derive version from removed launcher variable.

Code refs:
- `tests/integration.bats`
- `src/version.ts`

Edits:

1. Replace legacy expected-version extraction that parses `HERMES_FLY_VERSION` from `hermes-fly`.
2. Derive expected version from `src/version.ts` (`HERMES_FLY_TS_VERSION`).
3. Keep assertions on `hermes-fly --version` and `hermes-fly version` behavior.

---

## 5) Deterministic Verification Matrix (Static, Mandatory)

Run from:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
mkdir -p tmp/verification
```

### 5.0 Global Verification Preconditions (applies to all V1-V11)

Preconditions/setup:
1. Run commands from `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.
2. Active branch must be `worktree-compressed-waddling-rose`.
3. `tmp/verification/` exists and is writable.
4. No credentials required.
5. Do not print or commit secret values.

Validation command:

```bash
bash -euo pipefail -c '
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  test -d tmp/verification
'
```

Expected exit code:
- `0`

---

### V1 - Deploy Production Wiring Exists

Purpose:
- prove deploy no longer hard-fails due missing injected wizard.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "interactive wizard not available in this build" src/commands/deploy.ts
  rg -n "new .*DeployWizard\\(" src/commands/deploy.ts
  rg -n "implements DeployWizardPort" src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code:
- `0`

Expected output:
- `V1.out` includes matches for concrete wizard construction and `implements DeployWizardPort`.
- `V1.err` is empty.

Artifacts:
- `src/commands/deploy.ts`
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`

Pass/fail:
- pass only if exit `0` and all required matches present.

Cleanup:
- none.

---

### V2 - README Migration Flags Removed

Purpose:
- ensure docs no longer advertise removed hybrid runtime flags.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "HERMES_FLY_IMPL_MODE|HERMES_FLY_TS_COMMANDS|Developer Migration Flags" README.md
  rg -n "Commander|dist/cli.js|TypeScript" README.md
' >tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code:
- `0`

Expected output:
- first grep returns no matches.
- second grep returns at least one TS-runtime explanatory line.

Artifacts:
- `README.md`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`

Pass/fail:
- pass only if exit `0`.

Cleanup:
- none.

---

### V3 - Root `lib/*.sh` Decommissioned

Purpose:
- enforce Slice 9 runtime decommission contract.

Preconditions/setup:
1. Apply `5.0`.
2. Step 3 file-move edits are complete.

Command:

```bash
bash -euo pipefail -c '
  test -d lib/archive
  shopt -s nullglob
  files=(lib/*.sh)
  test ${#files[@]} -eq 0
  for f in \
    config.sh deploy.sh destroy.sh docker-helpers.sh doctor.sh fly-helpers.sh \
    list.sh logs.sh messaging.sh openrouter.sh prereqs.sh reasoning.sh status.sh ui.sh; do
    test -f "lib/archive/${f}"
  done
' >tmp/verification/V3.out 2>tmp/verification/V3.err
```

Expected exit code:
- `0`

Expected output:
- `V3.out` is empty.
- `V3.err` is empty.

Artifacts:
- `lib/archive/`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`

Pass/fail:
- pass only if no root `lib/*.sh` files remain and archive contains migrated files.

Cleanup:
- none.

---

### V4 - Active TS Transition Files No Longer Source `lib/`

Purpose:
- ensure active TS transition scripts/tests no longer require legacy runtime files.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "source .*lib/|lib/config.sh|lib/deploy.sh|lib/ui.sh" scripts/install.sh tests/install.bats tests/integration.bats
' >tmp/verification/V4.out 2>tmp/verification/V4.err
```

Expected exit code:
- `0`

Expected output:
- `V4.out` is empty.
- `V4.err` is empty.

Artifacts:
- `scripts/install.sh`
- `tests/install.bats`
- `tests/integration.bats`
- `tmp/verification/V4.out`
- `tmp/verification/V4.err`

Pass/fail:
- pass only if no matches.

Cleanup:
- none.

---

### V5 - Final Verifier Build Gate Is Strict

Purpose:
- ensure full verifier cannot pass with broken build.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "npm run build --prefix .*\\|\\| true" scripts/verify-pr-full-commander.sh
  rg -n "npm run build --prefix" scripts/verify-pr-full-commander.sh
' >tmp/verification/V5.out 2>tmp/verification/V5.err
```

Expected exit code:
- `0`

Expected output:
- `V5.out` includes `npm run build --prefix`.
- `V5.out` does not include `|| true`.
- `V5.err` is empty.

Artifacts:
- `scripts/verify-pr-full-commander.sh`
- `tmp/verification/V5.out`
- `tmp/verification/V5.err`

Pass/fail:
- pass only if build line exists and no build-masking pattern exists.

Cleanup:
- none.

---

### V6 - Integration Version Contract Uses `src/version.ts`

Purpose:
- verify integration tests are aligned with TS source-of-truth version contract.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "HERMES_FLY_VERSION" tests/integration.bats
  rg -n "src/version.ts|HERMES_FLY_TS_VERSION" tests/integration.bats
' >tmp/verification/V6.out 2>tmp/verification/V6.err
```

Expected exit code:
- `0`

Expected output:
- `V6.out` includes `src/version.ts` or `HERMES_FLY_TS_VERSION`.
- `V6.out` does not include `HERMES_FLY_VERSION`.
- `V6.err` is empty.

Artifacts:
- `tests/integration.bats`
- `src/version.ts`
- `tmp/verification/V6.out`
- `tmp/verification/V6.err`

Pass/fail:
- pass only if legacy variable usage is absent and TS version source is referenced.

Cleanup:
- none.

---

### V7 - Regression Safety Guard (No Hybrid Runtime References in Entrypoint)

Purpose:
- ensure runtime cutover remains intact after remediation edits.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  ! rg -n "HERMES_FLY_IMPL_MODE|HERMES_FLY_TS_COMMANDS" hermes-fly src/cli.ts
  ! rg -n "^source .*lib/" hermes-fly
  rg -n "exec node .*dist/cli.js" hermes-fly
' >tmp/verification/V7.out 2>tmp/verification/V7.err
```

Expected exit code:
- `0`

Expected output:
- `V7.out` includes one `exec node .*dist/cli.js` match.
- `V7.err` is empty.

Artifacts:
- `hermes-fly`
- `src/cli.ts`
- `tmp/verification/V7.out`
- `tmp/verification/V7.err`

Pass/fail:
- pass only if no hybrid/source references and launcher command remains present.

Cleanup:
- none.

---

### V8 - Happy-Path Coverage Check Presence

Purpose:
- prove the final verifier still includes explicit happy-path coverage.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  rg -n "happy_checks\\(\\)" scripts/verify-pr-full-commander.sh
  rg -n "\\[HAPPY\\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
' >tmp/verification/V8.out 2>tmp/verification/V8.err
```

Expected exit code:
- `0`

Expected output:
- `V8.out` includes `happy_checks()` and `[HAPPY] PASS`.
- `V8.err` is empty.

Artifacts:
- `scripts/verify-pr-full-commander.sh`
- `tests/verify-pr-full-commander.bats`
- `tmp/verification/V8.out`
- `tmp/verification/V8.err`

Pass/fail:
- pass only if both required matches are present and exit code is `0`.

Cleanup:
- none.

---

### V9 - Edge-Case Coverage Check Presence

Purpose:
- prove the final verifier still includes explicit edge-case coverage.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  rg -n "edge_checks\\(\\)" scripts/verify-pr-full-commander.sh
  rg -n "\\[EDGE\\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
' >tmp/verification/V9.out 2>tmp/verification/V9.err
```

Expected exit code:
- `0`

Expected output:
- `V9.out` includes `edge_checks()` and `[EDGE] PASS`.
- `V9.err` is empty.

Artifacts:
- `scripts/verify-pr-full-commander.sh`
- `tests/verify-pr-full-commander.bats`
- `tmp/verification/V9.out`
- `tmp/verification/V9.err`

Pass/fail:
- pass only if both required matches are present and exit code is `0`.

Cleanup:
- none.

---

### V10 - Failure-Path Coverage Check Presence

Purpose:
- prove the final verifier still includes explicit failure-path coverage.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  rg -n "failure_checks\\(\\)" scripts/verify-pr-full-commander.sh
  rg -n "\\[FAILURE\\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
' >tmp/verification/V10.out 2>tmp/verification/V10.err
```

Expected exit code:
- `0`

Expected output:
- `V10.out` includes `failure_checks()` and `[FAILURE] PASS`.
- `V10.err` is empty.

Artifacts:
- `scripts/verify-pr-full-commander.sh`
- `tests/verify-pr-full-commander.bats`
- `tmp/verification/V10.out`
- `tmp/verification/V10.err`

Pass/fail:
- pass only if both required matches are present and exit code is `0`.

Cleanup:
- none.

---

### V11 - Regression Coverage Check Presence

Purpose:
- prove regression/safety coverage remains explicitly enforced.

Preconditions/setup:
1. Apply `5.0`.

Command:

```bash
bash -euo pipefail -c '
  rg -n "regression_checks\\(\\)" scripts/verify-pr-full-commander.sh
  rg -n "\\[REGRESSION\\] PASS" scripts/verify-pr-full-commander.sh tests/verify-pr-full-commander.bats
' >tmp/verification/V11.out 2>tmp/verification/V11.err
```

Expected exit code:
- `0`

Expected output:
- `V11.out` includes `regression_checks()` and `[REGRESSION] PASS`.
- `V11.err` is empty.

Artifacts:
- `scripts/verify-pr-full-commander.sh`
- `tests/verify-pr-full-commander.bats`
- `tmp/verification/V11.out`
- `tmp/verification/V11.err`

Pass/fail:
- pass only if both required matches are present and exit code is `0`.

Cleanup:
- none.

---

## 6) Step-to-Verification Traceability

1. Step 1 -> `V1`, `V7`, `V8`, `V9`, `V10`, `V11`
2. Step 2 -> `V2`
3. Step 3 -> `V3`, `V4`
4. Step 4 -> `V5`
5. Step 5 -> `V6`
6. Global cutover safety -> `V7`, `V11`

---

## 7) Completion Criteria

This remediation is complete only when all are true:

1. `V1` through `V7` pass.
2. `V8` through `V11` pass.
3. No unresolved findings remain for:
- deploy disabled production path
- README hybrid flag docs
- root `lib/*.sh` decommission + active coupling
- build masking in final verifier
- integration version-source contract
4. Diff scope remains limited to files referenced in this plan.

---

## 8) Post-Implementation Cleanup

After review sign-off:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
rm -rf tmp/verification
```

---

## Execution Log

### Step 1: deploy-production-wiring
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted (stub removal, FlyDeployWizard concrete class, default construction wiring)
- [x] S5 WRITE_TEST: tests-ts/runtime/deploy-command.test.ts (pre-existing test confirmed red with stub)
- [x] S6 CONFIRM_RED: test fails — "interactive wizard not available in this build" returned
- [x] S7 IMPLEMENT: created `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`; updated `src/commands/deploy.ts` — replaced hard-disabled branch with `const wizard = options.wizard ?? new FlyDeployWizard(options.env)`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Step 2: readme-migration-flags-removal
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted (remove Developer Migration Flags section; add TS-native runtime note)
- [x] S5 WRITE_TEST: V2 static check (grep for HERMES_FLY_IMPL_MODE/HERMES_FLY_TS_COMMANDS/Developer Migration Flags in README.md)
- [x] S6 CONFIRM_RED: check fails — flags section found at README.md:126-156
- [x] S7 IMPLEMENT: removed `## Developer Migration Flags` section; added `## Runtime` section with Commander.js/node dist/cli.js note
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Step 3: lib-decommission-and-coupling-removal
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted (archive 14 lib/*.sh files; remove lib/ from install.sh copy block; remove lib/ui.sh assertions from install.bats; replace lib/-sourcing tests in integration.bats with TS-entrypoint-visible assertions)
- [x] S5 WRITE_TEST: V3 (root lib/*.sh count=0, archive presence), V4 (no lib/ coupling in active files)
- [x] S6 CONFIRM_RED: V3 fails — 14 root lib/*.sh files present; V4 fails — coupling in install.bats and integration.bats
- [x] S7 IMPLEMENT: `mkdir -p lib/archive && mv lib/*.sh lib/archive/`; removed lib/ copy block from `scripts/install.sh`; removed lib/ui.sh assertions from `tests/install.bats` including mock git heredocs (4 occurrences); replaced 3 channel tests in `tests/integration.bats` that sourced lib/deploy.sh with TS-entrypoint-visible assertions; updated 2 version extraction lines to use src/version.ts
- [x] S8 RUN_TESTS: pass (3 iterations — extra iterations for install.bats mock git script heredoc cleanup)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: [S8a] install.bats had lib/ui.sh references scattered across 4 locations including mock git heredocs at lines 197-284, not just the main test assertions; required sed -i '' with three substitution patterns

### Step 4: verifier-build-gate-strictness
- [x] S4 ANALYZE_CRITERIA: 1 criterion extracted (remove `|| true` from build line in verify-pr-full-commander.sh)
- [x] S5 WRITE_TEST: V5 static check (grep for `|| true` in build line)
- [x] S6 CONFIRM_RED: check fails — `|| true` found at scripts/verify-pr-full-commander.sh:141
- [x] S7 IMPLEMENT: removed `|| true` from build line
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Step 5: integration-version-contract
- [x] S4 ANALYZE_CRITERIA: 1 criterion extracted (replace HERMES_FLY_VERSION extraction with HERMES_FLY_TS_VERSION from src/version.ts)
- [x] S5 WRITE_TEST: V6 static check (grep for HERMES_FLY_VERSION absence, src/version.ts presence in integration.bats)
- [x] S6 CONFIRM_RED: check fails — HERMES_FLY_VERSION found in tests/integration.bats:17,25
- [x] S7 IMPLEMENT: replaced both version extraction lines with `grep -oE 'HERMES_FLY_TS_VERSION = "[0-9.]+"' "${PROJECT_ROOT}/src/version.ts" | grep -oE '[0-9.]+'`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- V1-V11 static checks: all pass (1 run, no retries)
- In-scope BATS (integration.bats + install.bats + verify-pr-full-commander.bats): 41/41 pass
- TypeScript unit tests (tests-ts/**/*.test.ts): 149/149 pass
- Pre-existing failure outside scope: tests/verify-pr-d2-status-logs.bats test 2 ("exits 0 and prints success message") — confirmed pre-existing in committed state 177f044 before REVIEW_1 changes; not caused by this plan
- Criteria walk: all 5 steps fully satisfied
