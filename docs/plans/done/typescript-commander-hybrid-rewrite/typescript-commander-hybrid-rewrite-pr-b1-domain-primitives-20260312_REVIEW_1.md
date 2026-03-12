# PR-B1 Review Plan 1: Strict ISO-8601 Validation + Coverage Closure

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-pr-b1-domain-primitives-20260312.md`  
Review source: `PR-B1 implementation verification findings (2026-03-12)`  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-b1-review-1` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-b1-domain-primitives-20260312_REVIEW_1-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Close all PR-B1 review findings by enforcing strict ISO-8601 timestamp validation in `DeploymentPlan.create(...)` and adding deterministic tests that fail on non-ISO inputs.

This review PR is a corrective patch only. No command routing, release flow, installer, or dispatch behavior changes are allowed.

---

## 2) Findings To Address (must all be closed)

1. `DeploymentPlan.createdAtIso` currently accepts non-ISO strings (example accepted: `March 12, 2026`).
2. Domain invariant tests do not include a negative case for invalid/non-ISO `createdAtIso`.

---

## 3) Scope

### In scope (must ship in this PR)

1. Add strict timestamp format validation in:
- `src/contexts/deploy/domain/deployment-plan.ts`

2. Add deterministic tests for timestamp validation in:
- `tests-ts/domain/primitives.test.ts`

3. Re-run all PR-B1 verification commands and confirm no regressions.

### Out of scope (do not do in this PR)

1. No new domain primitives.
2. No new ports or legacy contracts.
3. No updates to `scripts/verify-pr-b1-domain-primitives.sh` unless required to pass with unchanged semantics.
4. No changes in:
- `hermes-fly`
- `scripts/install.sh`
- `scripts/release-guard.sh`
- `src/legacy/bash-bridge.ts`

---

## 4) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Verify current baseline:

```bash
npm run test:domain-primitives
npm run typecheck
npm run arch:ddd-boundaries
```

Expected: all pass before patching.

---

## 5) Exact File Changes

## 5.1 Tighten `createdAtIso` validation logic

Path: `src/contexts/deploy/domain/deployment-plan.ts`  
Current anchor: validation block around lines `36-40`.

Action: modify `DeploymentPlan.create(input)` timestamp validation.

Required behavior:

1. Trim `createdAtIso` first (existing behavior preserved).
2. Reject empty string with existing deterministic error:
- `DeploymentPlan.createdAtIso must be valid ISO-8601`
3. Enforce strict ISO-8601 UTC millisecond format:
- Required accepted shape: `YYYY-MM-DDTHH:mm:ss.sssZ`
- Regex to enforce: `^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$`
4. Parse date and reject invalid calendar/time values.
5. Require round-trip equality:
- `new Date(createdAtIso).toISOString() === createdAtIso`
6. Keep error message unchanged for all failures:
- `DeploymentPlan.createdAtIso must be valid ISO-8601`

Implementation note (deterministic):

- Introduce a file-local constant `ISO_8601_UTC_MILLIS` for the regex.
- Validation must fail for examples like:
  - `March 12, 2026`
  - `2026-03-12`
  - `2026-03-12T12:34:56Z` (missing milliseconds)
  - `2026-13-12T12:34:56.000Z` (invalid month)

## 5.2 Add failing-then-passing timestamp tests

Path: `tests-ts/domain/primitives.test.ts`  
Current anchor: `DeploymentPlan` test block around lines `63-94`.

Action: modify tests to include strict timestamp checks.

Required test additions:

1. Add a negative assertion that non-ISO textual date is rejected:
- Input: `createdAtIso: "March 12, 2026"`
- Expected error: `DeploymentPlan.createdAtIso must be valid ISO-8601`

2. Add a negative assertion for malformed ISO shape (missing milliseconds):
- Input: `createdAtIso: "2026-03-12T12:34:56Z"`
- Expected error: `DeploymentPlan.createdAtIso must be valid ISO-8601`

3. Keep existing positive timestamp case intact (`2026-03-12T12:34:56.000Z`) in at least one plan creation path.

4. Keep existing stable pin and compat version assertions intact.

TDD requirement:

1. Write/adjust tests first.
2. Confirm red (`npm run test:domain-primitives` fails for new assertions).
3. Implement minimal fix in `deployment-plan.ts`.
4. Confirm green.

---

## 6) Deterministic Verification Criteria

All checks are required.

## 6.1 Targeted timestamp behavior checks

Run:

```bash
npm run test:domain-primitives
```

Expected:

1. Test suite passes.
2. Includes explicit coverage for rejecting non-ISO `createdAtIso`.
3. No weakened assertions or removed prior invariants.

## 6.2 Full static and boundary checks

Run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
```

Expected: both exit `0`.

## 6.3 Runtime no-regression checks

Run:

```bash
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: exit `0`, no failed tests.

## 6.4 One-command verifier

Run:

```bash
./scripts/verify-pr-b1-domain-primitives.sh
```

Expected:

1. Exit `0`.
2. Prints `PR-B1 verification passed.`

## 6.5 Explicit bug repro closure check

Run:

```bash
npx tsx -e 'import { DeploymentIntent } from "./src/contexts/deploy/domain/deployment-intent.ts"; import { DeploymentPlan } from "./src/contexts/deploy/domain/deployment-plan.ts"; const intent=DeploymentIntent.create({appName:"a",region:"iad",vmSize:"s",provider:"p",model:"m",channel:"preview"}); try { DeploymentPlan.create({intent,hermesAgentRef:"refs/tags/v1.2.3",compatPolicyVersion:"v1.2.3",createdAtIso:"March 12, 2026"}); console.log("BUG: accepted"); } catch (e) { console.log((e as Error).message); }'
```

Expected output:

- `DeploymentPlan.createdAtIso must be valid ISO-8601`
- Must NOT print `BUG: accepted`

---

## 7) Definition of Done (PR acceptance)

PR is done only when all are true:

1. `DeploymentPlan.create(...)` rejects non-ISO timestamp strings deterministically.
2. `DeploymentPlan.create(...)` still accepts valid canonical ISO timestamp strings used in existing tests.
3. Domain tests include explicit negative coverage for non-ISO/malformed timestamp input.
4. `npm run test:domain-primitives` passes.
5. `npm run typecheck` and `npm run arch:ddd-boundaries` pass.
6. Hybrid/integration BATS suites remain green.
7. `./scripts/verify-pr-b1-domain-primitives.sh` passes unchanged.
8. No changes in:
- `hermes-fly`
- `scripts/install.sh`
- `scripts/release-guard.sh`
- `src/legacy/bash-bridge.ts`

---

## 8) Commit and PR Metadata

Recommended commit message:

```text
PR-B1 REVIEW-1: enforce strict ISO-8601 createdAtIso validation
```

Recommended PR title:

```text
PR-B1 Review-1: fix createdAtIso strict ISO validation and coverage
```

Recommended PR checklist text:

1. Added failing test for non-ISO `createdAtIso`
2. Added failing test for malformed ISO shape `YYYY-MM-DDTHH:mm:ssZ`
3. Ran `npm run test:domain-primitives`
4. Ran `npm run typecheck`
5. Ran `npm run arch:ddd-boundaries`
6. Ran `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`
7. Ran `./scripts/verify-pr-b1-domain-primitives.sh`
8. Confirmed repro command rejects `March 12, 2026`

---

## 9) Rollback

If regressions are found:

1. Revert the review-fix commit.
2. Re-run:

```bash
npm run test:domain-primitives
npm run typecheck
npm run arch:ddd-boundaries
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: behavior returns to pre-review baseline.

---

## References

- [Node.js Date object documentation](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date)
- [Node.js test runner documentation](https://nodejs.org/api/test.html)
- [Node.js assert module documentation](https://nodejs.org/api/assert.html)

## Execution Log

### Slice 1: strict createdAtIso negative coverage
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/domain/primitives.test.ts` (DeploymentPlan timestamp assertions)
- [x] S6 CONFIRM_RED: test fails as expected (`AssertionError [ERR_ASSERTION]: Missing expected exception.`)
- [x] S7 IMPLEMENT: `tests-ts/domain/primitives.test.ts`
- [x] S8 RUN_TESTS: pass (2 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: `apply_patch` path resolution failed in this environment; switched to deterministic file rewrite for the same referenced file (S7)

### Slice 2: strict ISO-8601 UTC millis validation in DeploymentPlan
- [x] S4 ANALYZE_CRITERIA: 6 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/domain/primitives.test.ts` (non-ISO and missing-millis cases)
- [x] S6 CONFIRM_RED: test fails as expected before validator change
- [x] S7 IMPLEMENT: `src/contexts/deploy/domain/deployment-plan.ts`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration)
- Criteria walk: all satisfied (domain tests, typecheck, arch boundaries, BATS regressions, one-command verifier, explicit repro closure)
