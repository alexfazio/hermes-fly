# Remediation Plan: PR #12 Review-3 Findings

Date: 2026-03-15
Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_3.md`
Primary worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
Target PR: `#12 feat: complete TypeScript Commander.js full transition (9 slices)`

Execution mode:
- Static-analysis implementation and verification only.
- No product/API/architecture decisions delegated to implementer.
- Implementer works only in `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.

---

## 1) Objective

Resolve all Review-3 findings with deterministic, junior-executable edits:

1. Fix broken source paths in active status hybrid tests after `lib/*.sh` archival.
2. Remove stale dist-missing legacy-fallback assertions that conflict with thin launcher architecture.
3. Align deploy config persistence contract so `saveApp(appName, region)` persists both `current_app` and listable app-region entries.

---

## 2) In Scope / Out of Scope

### In Scope

1. `tests/status-ts-hybrid.bats`
2. `tests/logs-ts-hybrid.bats`
3. `scripts/verify-pr-d2-status-logs.sh`
4. `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
5. `tests-ts/deploy/run-deploy-wizard.test.ts` (new/updated assertions for persisted config contract)

### Out of Scope

1. New CLI commands or command flags.
2. Re-introducing hybrid dispatch in `hermes-fly`.
3. Moving files out of `lib/archive/`.
4. Changes to installer behavior (`scripts/install.sh`) unless directly required by the listed findings.

---

## 3) Preconditions, Dependencies, and Credentials

Preconditions:

1. Work only in the target worktree path.
2. Branch must be `worktree-compressed-waddling-rose`.
3. No credentials are required for this remediation plan.
4. Do not create or commit `.env` files and do not print secret values.

Pre-check command:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
bash -euo pipefail -c '
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  test -f tests/status-ts-hybrid.bats
  test -f tests/logs-ts-hybrid.bats
  test -f scripts/verify-pr-d2-status-logs.sh
  test -f src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
  mkdir -p tmp/verification
'
```

Expected exit code:
- `0`

---

## 4) Ordered Implementation Steps

Implement in exact order.

### Step 1 - Fix stale `source ./lib/config.sh` path in active status hybrid tests

Issue:
- `tests/status-ts-hybrid.bats` still sources `./lib/config.sh`, but runtime files were archived under `lib/archive/`.

Code refs:
- `tests/status-ts-hybrid.bats`
- `lib/archive/config.sh`

Required edits:

1. Replace all `source ./lib/config.sh` occurrences with `source ./lib/archive/config.sh` in `tests/status-ts-hybrid.bats`.
2. Do not alter test names, assertions, or command flow in this step.

Mandatory behavior after edit:

1. `tests/status-ts-hybrid.bats` contains zero references to `source ./lib/config.sh`.
2. `tests/status-ts-hybrid.bats` contains one or more references to `source ./lib/archive/config.sh` for current-app setup.

---

### Step 2 - Remove stale dist-missing fallback assertions tied to legacy fallback warnings

Issue:
- With thin launcher (`hermes-fly` -> `exec node dist/cli.js`), dist-missing fallback-to-legacy warning assertions are no longer valid.

Code refs:
- `hermes-fly`
- `tests/status-ts-hybrid.bats`
- `tests/logs-ts-hybrid.bats`
- `scripts/verify-pr-d2-status-logs.sh`

Required edits:

1. Remove dist-missing fallback test blocks that:
- intentionally remove/move `dist/cli.js`, and
- assert warning text `TS implementation unavailable ... falling back to legacy`.
2. Keep all non-dist-missing status/logs parity and malformed-flag checks intact.
3. Do not change launcher behavior in `hermes-fly`.

Mandatory behavior after edit:

1. No `status`/`logs` tests or verifier blocks still assert dist-missing fallback warning strings.
2. No `status`/`logs` remediation files still remove/move `dist/cli.js` for fallback assertions.
3. `hermes-fly` remains a thin node launcher.

---

### Step 3 - Make deploy `saveApp(appName, region)` persist listable app-region data

Issue:
- `FlyDeployWizard.saveApp(appName, region)` accepts `region` but currently writes only `current_app`.
- Runtime list parser reads `apps` entries (`- name`, `region`) from `config.yaml`.

Code refs:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `src/contexts/deploy/application/use-cases/run-deploy-wizard.ts`
- `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`
- `src/contexts/deploy/infrastructure/adapters/fly-resume-reader.ts`
- `tests-ts/deploy/run-deploy-wizard.test.ts`

Required edits:

1. Update `FlyDeployWizard.saveApp(appName, region)` to persist all of:
- `current_app: <appName>`
- `apps:` header (if missing)
- app entry with:
  - `  - name: <appName>`
  - `    region: <region>`
2. Preserve existing non-target lines in `config.yaml` when writing.
3. Avoid duplicate entries for the same app name when updating existing config.
4. Keep method signature unchanged: `saveApp(appName: string, region: string): Promise<void>`.
5. Add/extend TS tests in `tests-ts/deploy/run-deploy-wizard.test.ts` with exact test names:
- `saveApp writes current_app and apps region entry`
- `saveApp rewrites existing app entry without duplicates`
6. In the first test, assert the saved config contains `current_app:`, `apps:`, `- name:`, and `region:` entries.
7. In the second test, seed config with an existing app entry and assert resulting config keeps exactly one entry for that app.

Mandatory behavior after edit:

1. Save path writes schema compatible with both current-app resolution and list registry parsing.
2. A single app update does not create duplicate `name` entries for the same app.

---

## 5) Deterministic Verification Matrix (Static, Mandatory)

Run from:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
mkdir -p tmp/verification
```

### V0 - Credential readiness and scope guard

Purpose:
- prove this remediation does not require secrets and runs in correct worktree/branch.
- Coverage type: credential readiness.

Preconditions/setup:
1. None beyond section 3 pre-check.

Command:

```bash
bash -euo pipefail -c '
  test -d /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  if rg -n "OPENROUTER_API_KEY=.*[A-Za-z0-9]|TELEGRAM_BOT_TOKEN=.*[A-Za-z0-9]" docs/plans/typescript-commander-full-transition-20260315_REVIEW_3.md; then
    exit 1
  fi
' >tmp/verification/V0.out 2>tmp/verification/V0.err
```

Expected exit code:
- `0`

Expected artifacts:
- `tmp/verification/V0.out`
- `tmp/verification/V0.err`

Pass/fail rule:
- pass only if exit code is `0` and `V0.err` is empty.

Cleanup:
- none.

---

### V1 - Status hybrid test path migration complete

Purpose:
- verify stale `./lib/config.sh` source path is fully removed from status hybrid test.
- Coverage type: happy path.

Preconditions/setup:
1. Apply V0 setup.

Command:

```bash
bash -euo pipefail -c '
  if rg -n "source ./lib/config\\.sh" tests/status-ts-hybrid.bats; then
    exit 1
  fi
  rg -n "source ./lib/archive/config\\.sh" tests/status-ts-hybrid.bats
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code:
- `0`

Expected output:
- `V1.out` shows one or more archive-path matches.
- no stale-path matches.

Artifacts:
- `tests/status-ts-hybrid.bats`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`

Pass/fail rule:
- pass only if stale path is absent and archive path has one or more matches.

Cleanup:
- none.

---

### V2 - Dist-missing fallback legacy assertions removed from targeted files

Purpose:
- verify stale architecture assertions are removed from remediation scope files.
- Coverage type: edge case.

Preconditions/setup:
1. Apply V0 setup.

Command:

```bash
bash -euo pipefail -c '
  rg -n "exec node .*dist/cli\\.js" hermes-fly
  if rg -n "TS implementation unavailable for command .*falling back to legacy" tests/status-ts-hybrid.bats tests/logs-ts-hybrid.bats scripts/verify-pr-d2-status-logs.sh; then
    exit 1
  fi
  if rg -n "rm -f dist/cli\\.js|mv dist/cli\\.js" tests/status-ts-hybrid.bats tests/logs-ts-hybrid.bats scripts/verify-pr-d2-status-logs.sh; then
    exit 1
  fi
' >tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code:
- `0`

Expected output:
- `V2.out` includes launcher check from `hermes-fly`.
- no warning-pattern and no dist-remove/move matches.

Artifacts:
- `hermes-fly`
- `tests/status-ts-hybrid.bats`
- `tests/logs-ts-hybrid.bats`
- `scripts/verify-pr-d2-status-logs.sh`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`

Pass/fail rule:
- pass only if launcher match exists and both negated searches are clean.

Cleanup:
- none.

---

### V3 - Deploy saveApp persistence contract includes current app and app-region entry

Purpose:
- prove deploy adapter writes schema usable by both current-app resolution and deployment list parsing.
- Coverage type: happy path structural contract.

Preconditions/setup:
1. Apply V0 setup.

Command:

```bash
bash -euo pipefail -c '
  target="src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts"
  awk "/saveApp\\(appName: string, region: string\\)/,/^  }/" "${target}" > tmp/verification/V3.saveapp.block
  rg -n "saveApp\\(appName: string, region: string\\)" src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
  rg -n "current_app:" tmp/verification/V3.saveapp.block
  rg -n "apps:" tmp/verification/V3.saveapp.block
  rg -n "name:" tmp/verification/V3.saveapp.block
  rg -n "region:" tmp/verification/V3.saveapp.block
  if rg -n "existing\\.includes\\(" tmp/verification/V3.saveapp.block; then
    exit 1
  fi
  rg -n "regionMatch = line\\.match\\(/\\^    region:" src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts
' >tmp/verification/V3.out 2>tmp/verification/V3.err
```

Expected exit code:
- `0`

Expected output:
- all required schema-write/read anchors present.

Artifacts:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`
- `tmp/verification/V3.saveapp.block`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`

Pass/fail rule:
- pass only if saveApp block contains all required schema anchors, does not use `existing.includes(\`name: ...\`)` short-circuit, and registry parser region match remains present.

Cleanup:
- none.

---

### V4 - Failure-path verification: stale source path no longer present where previously failing

Purpose:
- verify the specific previous failure vector cannot occur in scope files.
- Coverage type: failure/error path.

Preconditions/setup:
1. Apply V0 setup.

Command:

```bash
bash -euo pipefail -c '
  if rg -n "source ./lib/config\\.sh" tests/status-ts-hybrid.bats scripts/verify-pr-d2-status-logs.sh tests/logs-ts-hybrid.bats; then
    exit 1
  fi
  rg -n "source ./lib/archive/config\\.sh" tests/status-ts-hybrid.bats scripts/verify-pr-d2-status-logs.sh tests/logs-ts-hybrid.bats
' >tmp/verification/V4.out 2>tmp/verification/V4.err
```

Expected exit code:
- `0`

Expected output:
- first check clean (no stale source path).
- second check returns one or more archive-path matches.

Artifacts:
- `tmp/verification/V4.out`
- `tmp/verification/V4.err`

Pass/fail rule:
- pass only if no stale sources remain and archive references are present.

Cleanup:
- none.

---

### V5 - Regression/safety guard on out-of-scope files and launcher invariant

Purpose:
- ensure remediation did not drift into unrelated runtime/installer surfaces.
- Coverage type: regression/safety.

Preconditions/setup:
1. Apply V0 setup.

Command:

```bash
bash -euo pipefail -c '
  test -z "$(git diff --name-only -- scripts/install.sh)"
  rg -n "exec node .*dist/cli\\.js" hermes-fly
' >tmp/verification/V5.out 2>tmp/verification/V5.err
```

Expected exit code:
- `0`

Expected output:
- no diff lines for `scripts/install.sh` from this remediation.
- launcher invariant still present.

Artifacts:
- `hermes-fly`
- `scripts/install.sh`
- `tmp/verification/V5.out`
- `tmp/verification/V5.err`

Pass/fail rule:
- pass only if both conditions are true.

Cleanup:
- none.

---

### V6 - Step 3 test-spec presence for persistence and dedup behavior

Purpose:
- verify Step 3 required TS tests were added with deterministic names and dedup assertion intent.
- Coverage type: regression/safety for future changes.

Preconditions/setup:
1. Apply V0 setup.

Command:

```bash
bash -euo pipefail -c '
  rg -n "saveApp writes current_app and apps region entry" tests-ts/deploy/run-deploy-wizard.test.ts
  rg -n "saveApp rewrites existing app entry without duplicates" tests-ts/deploy/run-deploy-wizard.test.ts
  rg -n "current_app:|apps:|name:|region:" tests-ts/deploy/run-deploy-wizard.test.ts
  rg -n "exactly one|length, 1|toBe\\(1\\)|assert\\.equal\\(.*1" tests-ts/deploy/run-deploy-wizard.test.ts
' >tmp/verification/V6.out 2>tmp/verification/V6.err
```

Expected exit code:
- `0`

Expected output:
- `V6.out` contains matches for both required test names, key schema assertions, and duplicate-count style assertion.

Artifacts:
- `tests-ts/deploy/run-deploy-wizard.test.ts`
- `tmp/verification/V6.out`
- `tmp/verification/V6.err`

Pass/fail rule:
- pass only if all four command checks match.

Cleanup:
- none.

---

## 6) Step-to-Verification Traceability

1. Step 1 -> V1, V4
2. Step 2 -> V2, V4
3. Step 3 -> V3, V6
4. Cross-cutting safety -> V0, V5

---

## 7) Deliverables

1. Updated tests/scripts with corrected `lib/archive` sourcing and removed stale dist-missing fallback assertions.
2. Updated deploy adapter config persistence logic with `current_app` + app-region list entry contract.
3. Updated deploy use-case test coverage in `tests-ts/deploy/run-deploy-wizard.test.ts` for persisted config contract.
4. Verification artifacts in `tmp/verification/V0.out` through `tmp/verification/V6.out` (static checks only).

---

## 8) Completion Criteria

This plan is complete only when all conditions are true:

1. All implementation steps are applied in order.
2. V0, V1, V2, V3, V4, V5, and V6 all exit with code `0`.
3. No blocking deviations remain in the three identified findings.
4. No product/API/architecture decisions were left to implementer judgment.
