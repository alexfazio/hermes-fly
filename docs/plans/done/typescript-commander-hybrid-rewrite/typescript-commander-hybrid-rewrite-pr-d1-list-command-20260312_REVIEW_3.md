# PR-D1 REVIEW-3 Execution Plan: Edge-Case Parity Closure + Negative Deviation Remediation

Date: 2026-03-12  
Parent plans:  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312.md`  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_1.md`  
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_2.md`  
Context: Mandatory post-REVIEW-2 follow-up for remaining negative deviations and uncovered edge cases  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-d1-list-command-review-3` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

REVIEW-2 closed the primary functional parity gap for `version --help` and unknown flags.  
Remaining mandatory follow-up is limited to:

1. Closing negative process deviations where slice-level evidence relied on presence/existence checks instead of behavioral/content assertions.
2. Adding deterministic guards for uncovered `version` edge cases so future regressions cannot pass verification.

No scope-expansion remediation is included in this patch.

---

## 2) Scope

### In scope (must ship in this review patch)

1. Add missing `version` edge-case parity tests in `tests/hybrid-dispatch.bats`.
2. Add missing dist-missing fallback tests for `version --help` and `version --unknown-flag`.
3. Harden `scripts/verify-pr-d1-list-command.sh` with deterministic assertions for the same edge cases.
4. Add deterministic content checks for the implementation evidence report requirements.
5. Create review-3 implementation evidence report.

### Out of scope (do not do in this patch)

1. No migration of additional commands (`status`, `logs`, `doctor`, `destroy`, `resume`, `deploy`).
2. No behavior changes for `list` migration scope.
3. No scope-expansion remediation from REVIEW-2 findings.
4. No changes to parity baseline snapshots (`tests/parity/baseline/list.*.snap`).
5. No changes to `scripts/install.sh`.
6. No changes to `scripts/release-guard.sh`.
7. No CI workflow changes.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm current functional baseline is green:

```bash
npm run build
./scripts/verify-pr-d1-list-command.sh
```

Confirm edge-case coverage gaps before patching:

```bash
rg -n "version -h|version -V|--help --unknown-flag|--unknown-flag --help" tests/hybrid-dispatch.bats
rg -n "ts mode allowlisted version --help|ts mode allowlisted version unknown flag" tests/hybrid-dispatch.bats
rg -n "version --help.*falling back to legacy|version --unknown-flag.*falling back to legacy" tests/hybrid-dispatch.bats
rg -n "review-3-implementation-report|Section 5 Verification Command Log Summary|scripts/install.sh|scripts/release-guard.sh" scripts/verify-pr-d1-list-command.sh
```

Expected pre-fix signal:

1. Edge-case tests for the above scenarios are missing or incomplete.
2. Verifier does not yet enforce review-3 report content requirements.

---

## 4) Exact File Changes

## 4.1 Add TS/hybrid `version` edge-case parity tests

Path: `tests/hybrid-dispatch.bats`  
Action: modify.

Required tests:

1. Dist present + `HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version`:
- `./hermes-fly version --help` matches legacy stdout/stderr/exit.
- `./hermes-fly version --unknown-flag` matches legacy stdout/stderr/exit.
2. Dist present + `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version`:
- `./hermes-fly version -h` matches legacy stdout/stderr/exit.
- `./hermes-fly version -V` matches legacy stdout/stderr/exit.
- `./hermes-fly version --help --unknown-flag` matches legacy stdout/stderr/exit.
- `./hermes-fly version --unknown-flag --help` matches legacy stdout/stderr/exit.

## 4.2 Add dist-missing fallback edge-case tests

Path: `tests/hybrid-dispatch.bats`  
Action: modify.

Required tests:

1. Dist missing + `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version` + `version --help`:
- exit `0`
- stdout exactly version line
- stderr exactly one warning line (fallback warning)
2. Dist missing + `HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version` + `version --unknown-flag`:
- exit `0`
- stdout exactly version line
- stderr exactly one warning line (fallback warning)

## 4.3 Harden one-command verifier for review-3 edge cases

Path: `scripts/verify-pr-d1-list-command.sh`  
Action: modify.

Required additions:

1. Keep all existing checks unchanged.
2. Add deterministic wrapper parity assertions for:
- ts allowlisted `version --help` vs legacy
- ts allowlisted `version --unknown-flag` vs legacy
- hybrid allowlisted `version -h` vs legacy
- hybrid allowlisted `version -V` vs legacy
- hybrid allowlisted `version --help --unknown-flag` vs legacy
- hybrid allowlisted `version --unknown-flag --help` vs legacy
3. Add deterministic dist-missing fallback assertions for:
- hybrid allowlisted `version --help`
- ts allowlisted `version --unknown-flag`
4. Add deterministic content assertions for:
- `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md`
- required sections/strings listed in 4.4 below.
5. Keep success sentinel unchanged: print `PR-D1 verification passed.` only on success.

## 4.4 Create review-3 implementation report

Create:

1. `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md`

Required content:

1. Brief summary of REVIEW-3 fixes.
2. Command log summary showing all section 5 criteria passed.
3. Explicit statement that `scripts/install.sh` and `scripts/release-guard.sh` were not changed.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f tests/hybrid-dispatch.bats
test -f scripts/verify-pr-d1-list-command.sh
test -f docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md
```

Expected: all exit `0`.

## 5.2 Wrapper `version` edge-case parity matrix

Run:

```bash
npm run build
tmp="$(mktemp -d)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help >"${tmp}/legacy-ts-help.out" 2>"${tmp}/legacy-ts-help.err"
printf "%s\n" "$?" >"${tmp}/legacy-ts-help.exit"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${tmp}/ts-help.out" 2>"${tmp}/ts-help.err"
printf "%s\n" "$?" >"${tmp}/ts-help.exit"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag >"${tmp}/legacy-ts-unknown.out" 2>"${tmp}/legacy-ts-unknown.err"
printf "%s\n" "$?" >"${tmp}/legacy-ts-unknown.exit"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${tmp}/ts-unknown.out" 2>"${tmp}/ts-unknown.err"
printf "%s\n" "$?" >"${tmp}/ts-unknown.exit"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version -h >"${tmp}/legacy-hybrid-h.out" 2>"${tmp}/legacy-hybrid-h.err"
printf "%s\n" "$?" >"${tmp}/legacy-hybrid-h.exit"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -h >"${tmp}/hybrid-h.out" 2>"${tmp}/hybrid-h.err"
printf "%s\n" "$?" >"${tmp}/hybrid-h.exit"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version -V >"${tmp}/legacy-hybrid-v.out" 2>"${tmp}/legacy-hybrid-v.err"
printf "%s\n" "$?" >"${tmp}/legacy-hybrid-v.exit"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -V >"${tmp}/hybrid-v.out" 2>"${tmp}/hybrid-v.err"
printf "%s\n" "$?" >"${tmp}/hybrid-v.exit"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help --unknown-flag >"${tmp}/legacy-hybrid-m1.out" 2>"${tmp}/legacy-hybrid-m1.err"
printf "%s\n" "$?" >"${tmp}/legacy-hybrid-m1.exit"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help --unknown-flag >"${tmp}/hybrid-m1.out" 2>"${tmp}/hybrid-m1.err"
printf "%s\n" "$?" >"${tmp}/hybrid-m1.exit"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag --help >"${tmp}/legacy-hybrid-m2.out" 2>"${tmp}/legacy-hybrid-m2.err"
printf "%s\n" "$?" >"${tmp}/legacy-hybrid-m2.exit"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag --help >"${tmp}/hybrid-m2.out" 2>"${tmp}/hybrid-m2.err"
printf "%s\n" "$?" >"${tmp}/hybrid-m2.exit"

diff -u "${tmp}/legacy-ts-help.out" "${tmp}/ts-help.out"
diff -u "${tmp}/legacy-ts-help.err" "${tmp}/ts-help.err"
diff -u "${tmp}/legacy-ts-help.exit" "${tmp}/ts-help.exit"
diff -u "${tmp}/legacy-ts-unknown.out" "${tmp}/ts-unknown.out"
diff -u "${tmp}/legacy-ts-unknown.err" "${tmp}/ts-unknown.err"
diff -u "${tmp}/legacy-ts-unknown.exit" "${tmp}/ts-unknown.exit"
diff -u "${tmp}/legacy-hybrid-h.out" "${tmp}/hybrid-h.out"
diff -u "${tmp}/legacy-hybrid-h.err" "${tmp}/hybrid-h.err"
diff -u "${tmp}/legacy-hybrid-h.exit" "${tmp}/hybrid-h.exit"
diff -u "${tmp}/legacy-hybrid-v.out" "${tmp}/hybrid-v.out"
diff -u "${tmp}/legacy-hybrid-v.err" "${tmp}/hybrid-v.err"
diff -u "${tmp}/legacy-hybrid-v.exit" "${tmp}/hybrid-v.exit"
diff -u "${tmp}/legacy-hybrid-m1.out" "${tmp}/hybrid-m1.out"
diff -u "${tmp}/legacy-hybrid-m1.err" "${tmp}/hybrid-m1.err"
diff -u "${tmp}/legacy-hybrid-m1.exit" "${tmp}/hybrid-m1.exit"
diff -u "${tmp}/legacy-hybrid-m2.out" "${tmp}/hybrid-m2.out"
diff -u "${tmp}/legacy-hybrid-m2.err" "${tmp}/hybrid-m2.err"
diff -u "${tmp}/legacy-hybrid-m2.exit" "${tmp}/hybrid-m2.exit"
```

Expected: all diffs exit `0`.

## 5.3 Dist-missing fallback edge-case contracts

Run:

```bash
npm run build
tmp="$(mktemp -d)"
dist_backup="${tmp}/cli.js.bak"
mv dist/cli.js "${dist_backup}"
trap 'mv "${dist_backup}" dist/cli.js' EXIT

HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${tmp}/hybrid-help.out" 2>"${tmp}/hybrid-help.err"
printf "%s\n" "$?" >"${tmp}/hybrid-help.exit"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${tmp}/ts-unknown.out" 2>"${tmp}/ts-unknown.err"
printf "%s\n" "$?" >"${tmp}/ts-unknown.exit"

expected_version="$(sed -n 's/^HERMES_FLY_VERSION=\"\\([0-9][0-9]*\\.[0-9][0-9]*\\.[0-9][0-9]*\\)\"$/\\1/p' ./hermes-fly | head -1)"
test "$(cat "${tmp}/hybrid-help.out")" = "hermes-fly ${expected_version}"
test "$(cat "${tmp}/ts-unknown.out")" = "hermes-fly ${expected_version}"
test "$(cat "${tmp}/hybrid-help.exit")" = "0"
test "$(cat "${tmp}/ts-unknown.exit")" = "0"
test "$(wc -l < "${tmp}/hybrid-help.err" | tr -d '[:space:]')" = "1"
test "$(wc -l < "${tmp}/ts-unknown.err" | tr -d '[:space:]')" = "1"
rg -n "^Warning: TS implementation unavailable for command 'version'; falling back to legacy$" "${tmp}/hybrid-help.err"
rg -n "^Warning: TS implementation unavailable for command 'version'; falling back to legacy$" "${tmp}/ts-unknown.err"
```

Expected: all assertions exit `0`.

## 5.4 Existing REVIEW-2 gates remain green

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

## 5.6 Review-3 implementation report content checks

Run:

```bash
report="docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md"
test -f "${report}"
rg -n "^## Summary$" "${report}"
rg -n "^## Section 5 Verification Command Log Summary$" "${report}"
rg -n "scripts/install\\.sh" "${report}"
rg -n "scripts/release-guard\\.sh" "${report}"
```

Expected: all exit `0`.

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. No functional regressions are introduced to existing REVIEW-2 behavior.
2. All review-identified `version` edge cases are covered by deterministic automated checks.
3. Negative deviation is remediated by behavioral/content assertions (not only presence/existence checks) for addressed items.
4. All section 5 criteria pass.
5. Existing list parity and fallback behavior remains unchanged.
6. Existing baseline snapshots remain unchanged.
7. Review-3 implementation report exists.
8. No changes in:
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-D1 REVIEW-3: close version edge-case parity gaps and tighten verification evidence
```

Recommended PR title:

```text
PR-D1 Review 3: version edge-case parity tests + verification hardening
```

Recommended PR checklist text:

1. Added TS/hybrid `version` edge-case parity tests (`-h`, `-V`, mixed option order, ts-mode allowlisted parity)
2. Added dist-missing fallback tests for `version --help` and `version --unknown-flag`
3. Hardened `scripts/verify-pr-d1-list-command.sh` with review-3 edge-case assertions
4. Added deterministic implementation report content checks
5. Ran `npm run typecheck`
6. Ran `npm run arch:ddd-boundaries`
7. Ran `npm run test:domain-primitives`
8. Ran `npm run test:runtime-list`
9. Ran `tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats`
10. Ran `npm run parity:check`
11. Ran `./scripts/verify-pr-d1-list-command.sh`
12. Created `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md`

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

Expected: behavior returns to prior REVIEW-2 baseline.

---

## References

- [Commander.js documentation](https://github.com/tj/commander.js)
- [Node.js child_process documentation](https://nodejs.org/api/child_process.html)
- [Bats-core documentation](https://bats-core.readthedocs.io/)
- [GNU diffutils manual](https://www.gnu.org/software/diffutils/manual/)

## Execution Log

### Slice 1: Add TS/hybrid `version` edge-case parity tests
- [x] S4 ANALYZE_CRITERIA: 6 criteria extracted
- [x] S5 WRITE_TEST: `tests/hybrid-dispatch.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `tests/hybrid-dispatch.bats`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: Add dist-missing fallback edge-case tests
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: `tests/hybrid-dispatch.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `tests/hybrid-dispatch.bats`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: Harden one-command verifier for review-3 edge cases
- [x] S4 ANALYZE_CRITERIA: 5 criteria extracted
- [x] S5 WRITE_TEST: `scripts/verify-pr-d1-list-command.sh`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: modified `scripts/verify-pr-d1-list-command.sh`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: Create review-3 implementation report
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: file existence/content checks for `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: created `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration)
- Criteria walk: all satisfied
