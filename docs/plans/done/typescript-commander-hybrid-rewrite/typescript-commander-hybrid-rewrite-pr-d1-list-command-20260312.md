# PR-D1 Execution Plan: TypeScript `list` Command Migration + Hybrid Parity Gate (Phase 2 Start)

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-20260311_1.md`  
Parent phase: Phase 2 (Migrate `list`), first implementation chunk  
Timebox: 90 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-d1-list-command` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Implement the first Phase 2 migration slice by porting `list` to TypeScript in the runtime context, wiring it to Commander, and proving deterministic parity against the committed list baseline snapshot while keeping safe bash fallback behavior.

This PR migrates one command only: `list`. No default promotion, no user-facing behavior change in default mode.

---

## 2) Scope

### In scope (must ship in this PR)

1. Add TypeScript process and flyctl adapters needed by `list`.
2. Add runtime context port/use-case/infrastructure adapter for deployment listing.
3. Add TS `list` command handler and wire it in `src/cli.ts`.
4. Add tests for runtime list use-case and hybrid TS list command parity.
5. Add npm scripts for runtime list tests and one-command verifier.
6. Add deterministic verifier script for PR-D1.
7. Update README developer section with TS `list` canary usage.

### Out of scope (do not do in this PR)

1. No migration of `status`, `logs`, `doctor`, `destroy`, `resume`, `deploy`.
2. No default TS promotion changes (`list` remains opt-in via allowlist).
3. No changes to parity baseline snapshot files (`tests/parity/baseline/list.*.snap` must remain unchanged).
4. No `scripts/install.sh` changes.
5. No `scripts/release-guard.sh` changes.
6. No CI workflow file additions.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm anchors before edits:

1. Hybrid dispatcher and allowlist gates exist:
- `hermes-fly:96-158`
- `hermes-fly:160-238`

2. TS CLI scaffold exists with no `list` command yet:
- `src/cli.ts:1-23`

3. Legacy `list` contract exists:
- `lib/list.sh:23-57`
- `tests/list.bats:18-52`

4. Parity baseline for `list` exists and is committed:
- `tests/parity/baseline/list.stdout.snap`
- `tests/parity/baseline/list.stderr.snap`
- `tests/parity/baseline/list.exit.snap`

5. Existing quality gates pass:

```bash
npm run parity:check
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
tests/bats/bin/bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats
```

If these are not true, resolve drift first.

---

## 4) Exact File Changes

## 4.1 Update `package.json` scripts for PR-D1 test surface

Path: `package.json` (scripts block at `package.json:5-13`).  
Action: modify.

Required changes:

1. Add script:
- `"test:runtime-list": "tsx --test tests-ts/runtime/list-deployments.test.ts"`

2. Add script:
- `"verify:pr-d1-list-command": "bash scripts/verify-pr-d1-list-command.sh"`

3. Keep existing scripts unchanged:
- `build`
- `typecheck`
- `arch:ddd-boundaries`
- `test:domain-primitives`
- `parity:capture`
- `parity:compare`
- `parity:check`

## 4.2 Update boundary rule for process adapter

Path: `dependency-cruiser.cjs` (child-process rule at `dependency-cruiser.cjs:20-25`).  
Action: modify.

Required changes:

1. Expand child-process allowlist so only these files may import `child_process`:
- `src/legacy/bash-bridge.ts`
- `src/adapters/process.ts`

2. Keep all domain-layer constraints unchanged.

## 4.3 Add low-level adapters

Create:

1. `src/adapters/process.ts`
2. `src/adapters/flyctl.ts`

Required behavior:

### `src/adapters/process.ts`

1. Provide typed command execution wrapper for external processes.
2. Capture `stdout`, `stderr`, `exitCode` deterministically as UTF-8 text.
3. Accept optional env overrides for test determinism.
4. Do not print directly to console.

### `src/adapters/flyctl.ts`

1. Use process adapter to execute:
- `fly status --app <app> --json`
2. Parse JSON and extract first machine `state`.
3. Return `null` when lookup fails/parsing fails/non-zero exit.
4. No throws for normal lookup failures (list command should degrade to `?`).

## 4.4 Add runtime context contracts + use-case + infrastructure adapter

Create:

1. `src/contexts/runtime/application/ports/deployment-registry.port.ts`
2. `src/contexts/runtime/application/use-cases/list-deployments.ts`
3. `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`

Required behavior:

### `deployment-registry.port.ts`

1. Export typed row model for list output:
- `appName`
- `region`
- `platform`
- `machine`
2. Export `DeploymentRegistryPort` interface.

### `list-deployments.ts`

1. Export `ListDeploymentsUseCase`.
2. Return deterministic result shape for presentation layer:
- empty state signal, or
- ordered row list.

### `fly-deployment-registry.ts`

1. Read configured apps from `${HERMES_FLY_CONFIG_DIR:-$HOME/.hermes-fly}/config.yaml`.
2. Resolve region from config; fallback `?` when missing.
3. Resolve platform from deploy YAML (`deploys/<app>.yaml` `messaging.platform`); fallback `-`.
4. Resolve machine state via flyctl adapter; fallback `?` on failure.
5. Truncate app display name to 26 chars with `...` suffix parity.
6. Preserve config order (same order as `config_list_apps` behavior).

## 4.5 Add TS `list` command and wire Commander

Create:

1. `src/commands/list.ts`

Update:

1. `src/cli.ts`

Required behavior:

### `src/commands/list.ts`

1. Render empty case exactly:
- `No deployed agents found. Run: hermes-fly deploy`
2. Render table header/underline/row format byte-compatible with current baseline spacing:
- `App Name`, `Region`, `Platform`, `Machine`
3. Return exit code `0` on success path.

### `src/cli.ts`

1. Register `list` subcommand.
2. Delegate to TS list handler.
3. Preserve existing version contract:
- `hermes-fly --version`
- `hermes-fly version` (via bash dispatcher fallback path behavior remains unchanged outside allowlisted list path).

## 4.6 Add TS + hybrid parity tests for `list`

Create:

1. `tests-ts/runtime/list-deployments.test.ts`
2. `tests/list-ts-hybrid.bats`

Required tests:

### `tests-ts/runtime/list-deployments.test.ts`

1. Empty registry returns empty-state result.
2. Non-empty registry returns deterministic rows.
3. Truncation rule (`26` with ellipsis) preserved.
4. Fallback placeholders preserved (`region ?`, `platform -`, `machine ?`).

### `tests/list-ts-hybrid.bats`

1. Build TS artifact and run allowlisted TS list path (`hybrid` + `HERMES_FLY_TS_COMMANDS=list`).
2. Empty config case matches exact legacy message.
3. Seeded deterministic app case matches committed parity baseline files:
- stdout == `tests/parity/baseline/list.stdout.snap`
- stderr == `tests/parity/baseline/list.stderr.snap`
- exit == `tests/parity/baseline/list.exit.snap`
4. Dist-missing fallback still works for allowlisted `list` with single warning line and preserved stdout contract.

## 4.7 Update README developer section

Path: `README.md` developer migration section around `README.md:126-171`.  
Action: append subsection.

Title:

1. `TS List Canary`

Required content:

```bash
npm run build
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list
```

Required sentence:

1. `Use this opt-in path to validate TypeScript list parity while default behavior remains legacy.`

## 4.8 Add deterministic verifier script for PR-D1

Create:

1. `scripts/verify-pr-d1-list-command.sh` (executable)

Script steps:

1. Verify all required new files exist.
2. Run:
- `npm run build`
- `npm run typecheck`
- `npm run arch:ddd-boundaries`
- `npm run test:domain-primitives`
- `npm run test:runtime-list`
3. Run:
- `tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats`
4. Run direct deterministic parity assertion for allowlisted TS list path against baseline list snapshots.
5. Print `PR-D1 verification passed.` only on success.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f src/adapters/process.ts
test -f src/adapters/flyctl.ts
test -f src/commands/list.ts
test -f src/contexts/runtime/application/ports/deployment-registry.port.ts
test -f src/contexts/runtime/application/use-cases/list-deployments.ts
test -f src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts
test -f tests-ts/runtime/list-deployments.test.ts
test -f tests/list-ts-hybrid.bats
test -f scripts/verify-pr-d1-list-command.sh
```

Expected: all exit `0`.

## 5.2 TypeScript build and architecture checks

Run:

```bash
npm run build
npm run typecheck
npm run arch:ddd-boundaries
```

Expected: all exit `0`.

## 5.3 Runtime list unit tests

Run:

```bash
npm run test:runtime-list
```

Expected: exit `0` and all test cases pass.

## 5.4 Hybrid TS list empty-state contract

Run:

```bash
tmp="$(mktemp -d)"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list
```

Expected:

1. Exit `0`.
2. Stdout exactly: `No deployed agents found. Run: hermes-fly deploy`.
3. Stderr empty.

## 5.5 Hybrid TS list deterministic parity against baseline

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list >"${tmp}/out" 2>"${tmp}/err"; \
    printf "%s\n" "$?" >"${tmp}/exit"'
diff -u tests/parity/baseline/list.stdout.snap "${tmp}/out"
diff -u tests/parity/baseline/list.stderr.snap "${tmp}/err"
diff -u tests/parity/baseline/list.exit.snap "${tmp}/exit"
```

Expected: all diffs exit `0`.

## 5.6 Allowlisted `list` fallback when artifact missing

Run:

```bash
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; rm -f dist/cli.js; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list >"${tmp}/out" 2>"${tmp}/err"'
head -n 1 "${tmp}/err"
diff -u tests/parity/baseline/list.stdout.snap "${tmp}/out"
```

Expected:

1. Command exits `0`.
2. First stderr line equals:
- `Warning: TS implementation unavailable for command 'list'; falling back to legacy`
3. Stdout diff exits `0`.

## 5.7 Regression safety checks

Run:

```bash
npm run test:domain-primitives
tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: all exit `0`.

## 5.8 One-command verifier

Run:

```bash
./scripts/verify-pr-d1-list-command.sh
```

Expected: exit `0`, prints `PR-D1 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. `list` command is implemented in TS and wired in Commander.
2. TS `list` output matches committed parity baseline for deterministic seeded scenario.
3. TS list empty-state message matches legacy contract exactly.
4. Allowlisted `list` still falls back safely to bash when `dist/cli.js` is unavailable.
5. Runtime list unit tests pass.
6. Existing bats suites remain green.
7. Existing CLI behavior remains unchanged in default mode.
8. No changes in:
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-D1: migrate list command to TypeScript runtime context with parity gate
```

Recommended PR title:

```text
PR-D1 Phase 2: TypeScript list command + hybrid parity verification
```

Recommended PR checklist text:

1. Ran `npm run build`
2. Ran `npm run typecheck`
3. Ran `npm run arch:ddd-boundaries`
4. Ran `npm run test:domain-primitives`
5. Ran `npm run test:runtime-list`
6. Verified hybrid TS `list` output matches `tests/parity/baseline/list.*.snap`
7. Verified allowlisted `list` fallback path when `dist/cli.js` is missing
8. Ran `tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats`
9. Ran `./scripts/verify-pr-d1-list-command.sh`

---

## 8) Rollback

If regressions are found:

1. Revert PR-D1 commit.
2. Re-run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
tests/bats/bin/bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: behavior returns to PR-C1 baseline.

---

## References

- [Commander.js documentation](https://github.com/tj/commander.js)
- [Node.js child_process documentation](https://nodejs.org/api/child_process.html)
- [dependency-cruiser rules reference](https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md)
- [Bats-core documentation](https://bats-core.readthedocs.io/)
- [GNU diffutils manual](https://www.gnu.org/software/diffutils/manual/)

## Execution Log

### Slice 1: package-scripts-pr-d1
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: `npm run test:runtime-list` / `npm run verify:pr-d1-list-command` missing-script checks
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `package.json`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: dependency-cruiser-child-process-allowlist
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: targeted allowlist assertion on `dependency-cruiser.cjs`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `dependency-cruiser.cjs`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: low-level-process-and-flyctl-adapters
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/list-deployments.test.ts` (process/flyctl adapter contract tests)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/adapters/process.ts`, `src/adapters/flyctl.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: runtime-context-list-use-case-and-fly-registry
- [x] S4 ANALYZE_CRITERIA: 6 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/list-deployments.test.ts` (use-case + registry criteria)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/contexts/runtime/application/ports/deployment-registry.port.ts`, `src/contexts/runtime/application/use-cases/list-deployments.ts`, `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 5: ts-list-command-and-cli-wiring
- [x] S4 ANALYZE_CRITERIA: 6 criteria extracted
- [x] S5 WRITE_TEST: `tests/list-ts-hybrid.bats` (empty contract + seeded parity + fallback scenarios)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/commands/list.ts`, `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 6: runtime-and-hybrid-list-tests
- [x] S4 ANALYZE_CRITERIA: 8 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/list-deployments.test.ts`, `tests/list-ts-hybrid.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `tests-ts/runtime/list-deployments.test.ts`, `tests/list-ts-hybrid.bats`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 7: readme-ts-list-canary
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: missing subsection/content grep checks
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `README.md`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 8: pr-d1-verifier-script
- [x] S4 ANALYZE_CRITERIA: 5 criteria extracted
- [x] S5 WRITE_TEST: execute verifier script before creation (`ENOENT`)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `scripts/verify-pr-d1-list-command.sh` (executable), `package.json`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration)
- Criteria walk: all satisfied
