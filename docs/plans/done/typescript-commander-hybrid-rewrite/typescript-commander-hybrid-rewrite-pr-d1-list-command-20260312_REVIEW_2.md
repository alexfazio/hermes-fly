# PR-D1 REVIEW-2 Execution Plan: Version Command Parity Closure + Verification Gate Completion

Date: 2026-03-12  
Parent plans:  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312.md`  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_1.md`  
Context: Mandatory post-REVIEW-1 follow-up for remaining non-list compatibility gaps  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-d1-list-command-review-2` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-2-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Close the remaining behavioral gap where allowlisted TS `version` still diverges from legacy when extra args/options are passed (`--help`, unknown flags). Harden tests and verifier so this regression class cannot pass again.

This review patch is narrow and corrective. No new command migrations.

---

## 2) Scope

### In scope (must ship in this review patch)

1. Align allowlisted TS `version` behavior with legacy for extra args/options.
2. Add regression tests for `version --help` and `version --unknown-flag` in hybrid dist-present routing.
3. Add direct `dist/cli.js version` extra-arg/option contract checks.
4. Harden `scripts/verify-pr-d1-list-command.sh` with the new version parity assertions.
5. Create review-2 implementation evidence report.

### Out of scope (do not do in this patch)

1. No migration of additional commands (`status`, `logs`, `doctor`, `destroy`, `resume`, `deploy`).
2. No changes to list baseline snapshots (`tests/parity/baseline/list.*.snap`).
3. No default dispatch behavior changes.
4. No changes to `scripts/install.sh`.
5. No changes to `scripts/release-guard.sh`.
6. No CI workflow changes.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Reproduce current divergence before patching:

```bash
npm run build
HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help
HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag
```

Expected pre-fix signal:

1. Legacy prints `hermes-fly <version>` for both invocations.
2. Allowlisted TS path currently diverges for `--help` and unknown flag behavior.

---

## 4) Exact File Changes

## 4.1 Normalize TS `version` subcommand argument semantics to legacy

Path: `src/cli.ts`  
Action: modify.

Required changes:

1. Keep root program wiring fix intact.
2. Keep `--version` and bare `version` contracts intact.
3. For TS `version` subcommand, ensure extra args/options do not change behavior versus legacy:
- `version --help` prints version line, exits `0`.
- `version --unknown-flag` prints version line, exits `0`.
4. Do not change `list` behavior introduced in REVIEW-1.

## 4.2 Add hybrid dispatch tests for version option/arg parity

Path: `tests/hybrid-dispatch.bats`  
Action: modify.

Required tests:

1. `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help` matches legacy `version --help` output and success.
2. `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag` matches legacy `version --unknown-flag` output and success.

## 4.3 Add dist entrypoint checks for version with extra args/options

Path: `tests/hybrid-dispatch.bats`  
Action: modify.

Required tests:

1. `node dist/cli.js version --help` prints exactly version line and exits `0`.
2. `node dist/cli.js version --unknown-flag` prints exactly version line and exits `0`.
3. No stderr output for both paths.

## 4.4 Harden one-command verifier with version parity checks

Path: `scripts/verify-pr-d1-list-command.sh`  
Action: modify.

Required additions:

1. Keep all existing checks from REVIEW-1 unchanged.
2. Add deterministic parity assertions for wrapper path:
- legacy vs allowlisted TS for `version --help`
- legacy vs allowlisted TS for `version --unknown-flag`
3. Add direct dist assertions:
- `node dist/cli.js version --help`
- `node dist/cli.js version --unknown-flag`
4. Keep success sentinel unchanged: print `PR-D1 verification passed.` only on success.

## 4.5 Create review-2 implementation report

Create:

1. `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-2-implementation-report.md`

Required content:

1. Brief summary of REVIEW-2 fixes.
2. Command log summary showing all section 5 criteria passed.
3. Explicit statement that `scripts/install.sh` and `scripts/release-guard.sh` were not changed.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f src/cli.ts
test -f tests/hybrid-dispatch.bats
test -f scripts/verify-pr-d1-list-command.sh
test -f docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-2-implementation-report.md
```

Expected: all exit `0`.

## 5.2 Wrapper version parity with extra args/options

Run:

```bash
npm run build
tmp="$(mktemp -d)"
HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help >"${tmp}/legacy-help.out" 2>"${tmp}/legacy-help.err"
printf "%s\n" "$?" >"${tmp}/legacy-help.exit"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${tmp}/ts-help.out" 2>"${tmp}/ts-help.err"
printf "%s\n" "$?" >"${tmp}/ts-help.exit"
HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag >"${tmp}/legacy-unknown.out" 2>"${tmp}/legacy-unknown.err"
printf "%s\n" "$?" >"${tmp}/legacy-unknown.exit"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${tmp}/ts-unknown.out" 2>"${tmp}/ts-unknown.err"
printf "%s\n" "$?" >"${tmp}/ts-unknown.exit"
diff -u "${tmp}/legacy-help.out" "${tmp}/ts-help.out"
diff -u "${tmp}/legacy-help.err" "${tmp}/ts-help.err"
diff -u "${tmp}/legacy-help.exit" "${tmp}/ts-help.exit"
diff -u "${tmp}/legacy-unknown.out" "${tmp}/ts-unknown.out"
diff -u "${tmp}/legacy-unknown.err" "${tmp}/ts-unknown.err"
diff -u "${tmp}/legacy-unknown.exit" "${tmp}/ts-unknown.exit"
```

Expected: all diffs exit `0`.

## 5.3 Dist CLI version option/arg contract

Run:

```bash
npm run build
node dist/cli.js version --help > /tmp/review2-dist-help.out 2>/tmp/review2-dist-help.err
node dist/cli.js version --unknown-flag > /tmp/review2-dist-unknown.out 2>/tmp/review2-dist-unknown.err
```

Expected:

1. Both commands exit `0`.
2. Each stdout is exactly one version line matching `hermes-fly <version>`.
3. Both stderr files are empty.

## 5.4 Existing REVIEW-1 gates remain green

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

## 5.5 One-command verifier

Run:

```bash
./scripts/verify-pr-d1-list-command.sh
```

Expected: exit `0`, prints `PR-D1 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. Allowlisted TS `version` no longer diverges from legacy for `--help` and unknown flags.
2. Dist `version` subcommand handles `--help` and unknown flags without introducing non-legacy behavior.
3. All section 5 criteria pass.
4. Existing list parity and fallback behavior remains unchanged.
5. Existing baseline snapshots remain unchanged.
6. Review-2 implementation report exists.
7. No changes in:
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-D1 REVIEW-2: close version parity gaps and harden verifier coverage
```

Recommended PR title:

```text
PR-D1 Review 2: version arg parity fix + verification hardening
```

Recommended PR checklist text:

1. Updated `src/cli.ts` version subcommand arg handling to match legacy
2. Added hybrid dispatch tests for `version --help` parity
3. Added hybrid dispatch tests for `version --unknown-flag` parity
4. Added dist `version --help` and `version --unknown-flag` checks
5. Hardened `scripts/verify-pr-d1-list-command.sh` with version parity assertions
6. Ran `npm run typecheck`
7. Ran `npm run arch:ddd-boundaries`
8. Ran `npm run test:domain-primitives`
9. Ran `npm run test:runtime-list`
10. Ran `tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats`
11. Ran `npm run parity:check`
12. Ran `./scripts/verify-pr-d1-list-command.sh`
13. Created `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-2-implementation-report.md`

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

Expected: behavior returns to prior REVIEW-1 baseline.

---

## References

- [Commander.js documentation](https://github.com/tj/commander.js)
- [Node.js child_process documentation](https://nodejs.org/api/child_process.html)
- [dependency-cruiser rules reference](https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md)
- [Bats-core documentation](https://bats-core.readthedocs.io/)
- [GNU diffutils manual](https://www.gnu.org/software/diffutils/manual/)

## Execution Log

### Slice 1: Normalize TS `version` subcommand argument semantics to legacy
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted
- [x] S5 WRITE_TEST: section 5.2 parity command block (legacy vs allowlisted TS `version --help` and `version --unknown-flag`)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: Add hybrid dispatch tests for version option/arg parity
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: `tests/hybrid-dispatch.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `tests/hybrid-dispatch.bats`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: Add dist entrypoint checks for version with extra args/options
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: `tests/hybrid-dispatch.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `tests/hybrid-dispatch.bats`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: Harden one-command verifier with version parity checks
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted
- [x] S5 WRITE_TEST: `scripts/verify-pr-d1-list-command.sh` (presence checks for new `version --help` / `version --unknown-flag` assertions)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `scripts/verify-pr-d1-list-command.sh`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 5: Create review-2 implementation report
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: file existence check for `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-2-implementation-report.md`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: created `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-2-implementation-report.md`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration)
- Criteria walk: all satisfied

## Historical TDD Addendum

This addendum records the historical process deviation and its closure path.

1. Historical deviation:
- Slice 4 (`Harden one-command verifier with version parity checks`) logged S5 as a presence-check style workflow.
- Slice 5 (`Create review-2 implementation report`) logged S5 as file existence check.
2. Closure evidence (behavioral/content assertions now enforced):
- `scripts/verify-pr-d1-list-command.sh` enforces version parity and dist-missing fallback behavior with explicit stdout/stderr/exit assertions.
- `tests/hybrid-dispatch.bats` includes deterministic version parity and fallback behavior checks for hybrid and ts modes.
- REVIEW-3 verifier checks require report-content assertions, including the section-5 pass sentence.
3. Conclusion:
- Historical log entries remain immutable as execution history.
- The active verification surface is now behavior-first and content-assertive.
