# PR-D1 REVIEW-1 Execution Plan: Commander Root Wiring Fix + Verification Hardening

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312.md`  
Context: Post-implementation mandatory review findings remediation  
Timebox: 90 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-d1-list-command-review-1` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (must exist after this remediation): `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Address all mandatory review findings from PR-D1 by fixing Commander root wiring regression, tightening parity behavior for allowlisted TS `list`, aligning HOME-empty config fallback semantics, and hardening verification so the regression class cannot pass gates again.

This remediation must not broaden migration scope. It only fixes correctness/parity gaps discovered during review.

---

## 2) Scope

### In scope (must ship in this review patch)

1. Fix Commander program construction so root command behavior (`--version`, `version`, `help`) is correct.
2. Preserve non-list command behavior in hybrid mode when TS is allowlisted and `dist/cli.js` is present.
3. Restore list-argument compatibility for TS `list` path (`--help` and unknown args/options should not introduce new behavior vs legacy).
4. Align runtime config-dir fallback semantics when `HERMES_FLY_CONFIG_DIR` is unset and `HOME` is empty/unset.
5. Add regression tests covering the above scenarios (dist-present routing + list arg compatibility + HOME-empty semantics).
6. Harden `scripts/verify-pr-d1-list-command.sh` to enforce new regression guards.
7. Create the missing implementation evidence report file referenced by the parent plan.

### Out of scope (do not do in this patch)

1. No migration of additional commands (`status`, `logs`, `doctor`, `destroy`, `resume`, `deploy`).
2. No changes to parity baseline snapshots in `tests/parity/baseline/`.
3. No changes to default dispatcher mode behavior.
4. No changes to `scripts/install.sh`.
5. No changes to `scripts/release-guard.sh`.
6. No CI workflow changes.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm the reviewed regressions are reproducible before fixes:

1. Dist CLI root wiring regression (current broken behavior):

```bash
npm run build
node dist/cli.js --version
node dist/cli.js version
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version
```

2. TS list argument divergence from legacy:

```bash
npm run build
HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --help
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --help
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --unknown-flag
```

3. HOME-empty fallback divergence exists in runtime registry path semantics.

4. Missing report file is currently absent:

```bash
test -f docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md
```

---

## 4) Exact File Changes

## 4.1 Fix Commander root program wiring

Path: `src/cli.ts`  
Action: modify.

Required changes:

1. `buildProgram()` must return the root `Command` object, not a subcommand.
2. Register `list` as a subcommand on the root command while preserving root-level contracts.
3. Ensure these dist CLI contracts hold:
- `node dist/cli.js --version` exits `0`, prints TS version line.
- `node dist/cli.js version` exits `0`, prints TS version line.
- `node dist/cli.js help` shows root help text (not list table output).

## 4.2 Preserve list parity for extra args/options

Paths:
1. `src/cli.ts`
2. `src/commands/list.ts` (if needed)

Action: modify.

Required changes:

1. TS `list` path must not introduce new argument semantics vs legacy contract.
2. `list --help` in allowlisted TS path must not render Commander help if legacy would execute list output.
3. Unknown list flags/args must not fail when legacy path would continue.

## 4.3 Add hybrid dispatch regression tests for dist-present routing

Path: `tests/hybrid-dispatch.bats`  
Action: modify.

Required tests:

1. Dist present + `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version` + `./hermes-fly version` returns exactly version output and no list table.
2. Dist present + direct TS entrypoint version checks:
- `node dist/cli.js --version`
- `node dist/cli.js version`

## 4.4 Add list argument parity tests on allowlisted TS path

Path: `tests/list-ts-hybrid.bats`  
Action: modify.

Required tests:

1. Under deterministic seeded config, `legacy list --help` and allowlisted TS `list --help` produce byte-identical stdout/stderr/exit.
2. Under deterministic seeded config, `legacy list --unknown-flag` and allowlisted TS `list --unknown-flag` produce byte-identical stdout/stderr/exit.

## 4.5 Align HOME-empty fallback semantics in runtime registry

Path: `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`  
Action: modify.

Required changes:

1. When `HERMES_FLY_CONFIG_DIR` is set, behavior remains unchanged.
2. When `HERMES_FLY_CONFIG_DIR` is unset and `HOME` is empty/unset, fallback must resolve to `/.hermes-fly` semantics (not relative `.hermes-fly`).
3. Keep existing region/platform/machine fallbacks unchanged.

## 4.6 Add runtime unit coverage for HOME-empty fallback

Path: `tests-ts/runtime/list-deployments.test.ts`  
Action: modify.

Required tests:

1. HOME-empty path fallback test that fails if relative `.hermes-fly` is used.
2. Existing runtime tests remain green.

## 4.7 Harden verifier script to catch reviewed regression class

Path: `scripts/verify-pr-d1-list-command.sh`  
Action: modify.

Required additions:

1. Keep all existing verification steps.
2. Add explicit dist-present routing assertions for:
- `node dist/cli.js --version`
- `node dist/cli.js version`
- `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version`
3. Add explicit parity assertions for:
- `list --help` legacy vs allowlisted TS path.
- `list --unknown-flag` legacy vs allowlisted TS path.
4. Keep success sentinel unchanged: print `PR-D1 verification passed.` only on success.

## 4.8 Create missing evidence report file

Create:

1. `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md`

Required content:

1. Brief summary of implemented review fixes.
2. Command log summary proving all deterministic criteria in section 5 passed.
3. Explicit statement that `scripts/install.sh` and `scripts/release-guard.sh` were not changed.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f src/cli.ts
test -f src/commands/list.ts
test -f src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts
test -f tests/hybrid-dispatch.bats
test -f tests/list-ts-hybrid.bats
test -f tests-ts/runtime/list-deployments.test.ts
test -f scripts/verify-pr-d1-list-command.sh
test -f docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md
```

Expected: all exit `0`.

## 5.2 Dist CLI root routing contracts

Run:

```bash
npm run build
node dist/cli.js --version
node dist/cli.js version
node dist/cli.js help
```

Expected:

1. `--version` and `version` exit `0` and print exactly one version line each.
2. `help` exits `0` and prints root usage/help text (not list table rows).

## 5.3 Hybrid dist-present non-list routing contract

Run:

```bash
npm run build
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version
```

Expected:

1. Exit `0`.
2. Output is exactly the version line contract.
3. No list table output.

## 5.4 List arg parity under allowlisted TS path

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; \
    HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --help >"${tmp}/legacy-help.out" 2>"${tmp}/legacy-help.err"; \
    printf "%s\n" "$?" >"${tmp}/legacy-help.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --help >"${tmp}/ts-help.out" 2>"${tmp}/ts-help.err"; \
    printf "%s\n" "$?" >"${tmp}/ts-help.exit"; \
    HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --unknown-flag >"${tmp}/legacy-unknown.out" 2>"${tmp}/legacy-unknown.err"; \
    printf "%s\n" "$?" >"${tmp}/legacy-unknown.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --unknown-flag >"${tmp}/ts-unknown.out" 2>"${tmp}/ts-unknown.err"; \
    printf "%s\n" "$?" >"${tmp}/ts-unknown.exit"'
diff -u "${tmp}/legacy-help.out" "${tmp}/ts-help.out"
diff -u "${tmp}/legacy-help.err" "${tmp}/ts-help.err"
diff -u "${tmp}/legacy-help.exit" "${tmp}/ts-help.exit"
diff -u "${tmp}/legacy-unknown.out" "${tmp}/ts-unknown.out"
diff -u "${tmp}/legacy-unknown.err" "${tmp}/ts-unknown.err"
diff -u "${tmp}/legacy-unknown.exit" "${tmp}/ts-unknown.exit"
```

Expected: all diffs exit `0`.

## 5.5 HOME-empty fallback semantics parity check

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/.hermes-fly" "${tmp}/logs"
cat > "${tmp}/.hermes-fly/config.yaml" <<'YAML'
apps:
  - name: should-not-be-read-from-relative-path
    region: ord
YAML
(
  cd "${tmp}"
  HOME='' HERMES_FLY_IMPL_MODE=legacy /Users/alex/Documents/GitHub/hermes-fly/hermes-fly list >legacy.out 2>legacy.err
  HOME='' HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list /Users/alex/Documents/GitHub/hermes-fly/hermes-fly list >ts.out 2>ts.err
)
diff -u "${tmp}/legacy.out" "${tmp}/ts.out"
diff -u "${tmp}/legacy.err" "${tmp}/ts.err"
```

Expected: both diffs exit `0`.

## 5.6 Existing PR-D1 regression gates remain green

Run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
npm run test:runtime-list
tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats
npm run parity:check
```

Expected: all exit `0`.

## 5.7 One-command verifier

Run:

```bash
./scripts/verify-pr-d1-list-command.sh
```

Expected: exit `0`, prints `PR-D1 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. Commander root wiring regression is fixed (`--version`, `version`, `help` contracts hold on dist CLI).
2. Hybrid allowlisted non-list command routing no longer leaks into list execution.
3. TS allowlisted `list` does not introduce argument semantics divergence vs legacy for `--help` and unknown flags.
4. HOME-empty config fallback semantics match legacy behavior.
5. All section 5 verification criteria pass.
6. Existing baseline snapshots remain unchanged.
7. Missing implementation report file exists with evidence summary.
8. No changes in:
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-D1 REVIEW-1: fix commander root wiring regression and harden parity gates
```

Recommended PR title:

```text
PR-D1 Review 1: commander root fix + list parity/verification hardening
```

Recommended PR checklist text:

1. Fixed `src/cli.ts` to return root Commander program correctly
2. Verified `node dist/cli.js --version` and `node dist/cli.js version`
3. Verified hybrid allowlisted `version` route with dist present
4. Added/updated tests for list arg parity (`--help`, unknown flag)
5. Added HOME-empty fallback parity coverage
6. Ran `npm run typecheck`
7. Ran `npm run arch:ddd-boundaries`
8. Ran `npm run test:domain-primitives`
9. Ran `npm run test:runtime-list`
10. Ran `tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats`
11. Ran `npm run parity:check`
12. Ran `./scripts/verify-pr-d1-list-command.sh`
13. Created `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md`

---

## 8) Rollback

If regressions are found:

1. Revert this review-fix commit.
2. Re-run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
npm run test:runtime-list
tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats
npm run parity:check
```

Expected: behavior returns to prior PR-D1 baseline.

---

## References

- [Commander.js documentation](https://github.com/tj/commander.js)
- [Node.js child_process documentation](https://nodejs.org/api/child_process.html)
- [dependency-cruiser rules reference](https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md)
- [Bats-core documentation](https://bats-core.readthedocs.io/)
- [GNU diffutils manual](https://www.gnu.org/software/diffutils/manual/)

## Execution Log

### Slice 1: commander-root-program-wiring
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: dist CLI contract check (`node dist/cli.js --version`, `node dist/cli.js version`, `node dist/cli.js help`)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: list-arg-parity-runtime-behavior
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: deterministic legacy-vs-TS diff for `list --help` and `list --unknown-flag`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: hybrid-dispatch-dist-present-regression-tests
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: `tests/hybrid-dispatch.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `tests/hybrid-dispatch.bats`, `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: list-arg-parity-bats-tests
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: `tests/list-ts-hybrid.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `tests/list-ts-hybrid.bats`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 5: home-empty-fallback-semantics-fix
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: HOME-empty legacy-vs-TS parity diff check
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 6: runtime-home-empty-unit-coverage
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/list-deployments.test.ts`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `tests-ts/runtime/list-deployments.test.ts`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: red-state behavior was first demonstrated by Slice 5 deterministic parity failure; unit test added to lock the fix.

### Slice 7: verifier-script-hardening
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted
- [x] S5 WRITE_TEST: missing-assertion checks in `scripts/verify-pr-d1-list-command.sh`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `scripts/verify-pr-d1-list-command.sh`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 8: implementation-report-file
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: file existence check for implementation report path
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-implementation-report.md`
- [x] S8 RUN_TESTS: pass (1 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration)
- Criteria walk: all satisfied

## Historical TDD Addendum

This addendum records the historical process deviation and its closure path.

1. Historical deviation:
- Slice 7 (`verifier-script-hardening`) logged S5 as a missing-assertion/presence check workflow.
- Slice 8 (`implementation-report-file`) logged S5 as file existence check.
2. Closure evidence (behavioral/content assertions now enforced):
- `scripts/verify-pr-d1-list-command.sh` asserts runtime behavior contracts for version/list parity and fallback scenarios.
- `scripts/verify-pr-d1-list-command.sh` asserts review report content markers for REVIEW-3 evidence quality.
- `tests/hybrid-dispatch.bats` contains deterministic behavior checks for dist-present and dist-missing version permutations.
3. Conclusion:
- Historical log entries remain immutable as execution history.
- The regression-prevention surface is now behavioral/content-based in active gates.
