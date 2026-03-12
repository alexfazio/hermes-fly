# PR-B1 Execution Plan: Domain Primitives + Port Contracts (Phase 0.5 Start)

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-20260311.md`  
Parent phase: Phase 0.5 (DDD Model Bootstrap), first implementation chunk  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-b1-domain-primitives` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-b1-domain-primitives-20260312-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Implement the first Phase 0.5 slice by adding the six required domain primitives and typed application/legacy contracts, with deterministic invariant tests and no user-facing CLI behavior changes.

This PR is foundational only: no command migration and no runtime routing changes.

---

## 2) Scope

### In scope (must ship in this PR)

1. Add domain primitives:
- `DeploymentIntent`
- `DeploymentPlan`
- `ProvenanceRecord`
- `DriftFinding`
- `MessagingPolicy`
- `ReleaseContract`

2. Add context-level port interfaces in `application/ports`.

3. Add anti-corruption adapter contracts for legacy fallback (types/interfaces only).

4. Add deterministic domain invariant tests (zero process/network/fs mocks).

5. Add one-command verifier script for this PR.

### Out of scope (do not do in this PR)

1. No `hermes-fly` dispatch changes.
2. No command handlers (`list`, `status`, etc.) in TS.
3. No `scripts/install.sh` changes.
4. No `scripts/release-guard.sh` changes.
5. No parity harness files.
6. No CI workflow file additions.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm anchors before edits:

1. `src/contexts/*` skeleton exists from PR-A2 (all `.gitkeep` leaves).
2. `package.json` scripts currently include:
- `build`
- `typecheck`
- `arch:ddd-boundaries`
3. `dependency-cruiser.cjs` exists and `npm run arch:ddd-boundaries` passes on clean tree.

If these are not true, stop and resolve PR-A2 drift first.

---

## 4) Exact File Changes

## 4.1 Update `package.json` for domain tests

Path: `package.json` (current scripts at `package.json:5-9`).  
Action: modify.

Required changes:

1. Add script:
- `"test:domain-primitives": "tsx --test tests-ts/domain/primitives.test.ts"`

2. Add dev dependency:
- `"tsx"` pinned to a stable major version.

3. Keep existing scripts unchanged:
- `build`
- `typecheck`
- `arch:ddd-boundaries`

## 4.2 Add deploy domain primitives

Create:

1. `src/contexts/deploy/domain/deployment-intent.ts`
2. `src/contexts/deploy/domain/deployment-plan.ts`
3. `src/contexts/deploy/domain/provenance-record.ts`

Required contracts:

### `deployment-intent.ts`

1. Export:
- `type DeployChannel = "stable" | "preview" | "edge"`
- `interface DeploymentIntentInput`
- `class DeploymentIntent`

2. `DeploymentIntent.create(input)` must:
- trim string fields,
- default `channel` to `"stable"`,
- reject empty `appName`, `region`, `vmSize`, `provider`, `model`,
- reject invalid channel values.

3. Errors must be deterministic `Error` messages:
- `DeploymentIntent.<field> must be non-empty`
- `DeploymentIntent.channel must be one of stable|preview|edge`

### `deployment-plan.ts`

1. Export:
- `interface DeploymentPlanInput`
- `class DeploymentPlan`

2. `DeploymentPlan.create(input)` must validate:
- `hermesAgentRef` non-empty,
- `compatPolicyVersion` matches `^v[0-9]+\\.[0-9]+\\.[0-9]+$`,
- `createdAtIso` parses as valid ISO timestamp,
- rule: if `intent.channel === "stable"`, `hermesAgentRef` must not be `"main"`.

3. Deterministic errors:
- `DeploymentPlan.hermesAgentRef must be non-empty`
- `DeploymentPlan.compatPolicyVersion must be semver with v prefix`
- `DeploymentPlan.createdAtIso must be valid ISO-8601`
- `DeploymentPlan.hermesAgentRef must be pinned for stable channel`

### `provenance-record.ts`

1. Export:
- `interface ProvenanceRecordInput`
- `class ProvenanceRecord`

2. `ProvenanceRecord.create(input)` validates non-empty:
- `hermesFlyVersion`
- `hermesAgentRef`
- `compatPolicyVersion`
- `reasoningEffort`
- `llmProvider`
- `llmModel`
- `writtenAt`

3. Validate `deployChannel` is one of `stable|preview|edge`.

4. Deterministic errors:
- `ProvenanceRecord.<field> must be non-empty`
- `ProvenanceRecord.deployChannel must be one of stable|preview|edge`

## 4.3 Add diagnostics/messaging/release domain primitives

Create:

1. `src/contexts/diagnostics/domain/drift-finding.ts`
2. `src/contexts/messaging/domain/messaging-policy.ts`
3. `src/contexts/release/domain/release-contract.ts`

Required contracts:

### `drift-finding.ts`

1. Export:
- `type DriftSeverity = "info" | "warn" | "error"`
- `type DriftKind = "missing" | "mismatch" | "unexpected"`
- `interface DriftFindingInput`
- `class DriftFinding`

2. `DriftFinding.create(input)` validates:
- non-empty `code`, `message`, `subject`,
- valid `severity`, `kind`.

3. Deterministic errors:
- `DriftFinding.<field> must be non-empty`
- `DriftFinding.severity must be info|warn|error`
- `DriftFinding.kind must be missing|mismatch|unexpected`

### `messaging-policy.ts`

1. Export:
- `type MessagingPolicyMode = "only_me" | "specific_users" | "anyone"`
- `class MessagingPolicy`

2. `MessagingPolicy.create(mode, allowedUsers)` rules:
- `only_me`: exactly 1 numeric user id.
- `specific_users`: one or more unique numeric user ids.
- `anyone`: no user ids allowed.

3. Deterministic errors:
- `MessagingPolicy.mode must be only_me|specific_users|anyone`
- `MessagingPolicy.only_me requires exactly one numeric user id`
- `MessagingPolicy.specific_users requires one or more numeric user ids`
- `MessagingPolicy.anyone must not include user ids`

### `release-contract.ts`

1. Export:
- `interface ReleaseContractInput`
- `class ReleaseContract`

2. `ReleaseContract.create(input)` validates:
- `tag` matches `^v[0-9]+\\.[0-9]+\\.[0-9]+$`,
- `hermesFlyVersion` matches `^[0-9]+\\.[0-9]+\\.[0-9]+$`,
- `tag.slice(1) === hermesFlyVersion`.

3. Deterministic errors:
- `ReleaseContract.tag must be semver with v prefix`
- `ReleaseContract.hermesFlyVersion must be semver`
- `ReleaseContract.tag must match hermesFlyVersion`

## 4.4 Add context application port interfaces

Create:

1. `src/contexts/deploy/application/ports/deployment-plan-writer.port.ts`
2. `src/contexts/diagnostics/application/ports/drift-finding-reader.port.ts`
3. `src/contexts/messaging/application/ports/messaging-policy-repository.port.ts`
4. `src/contexts/release/application/ports/release-contract-checker.port.ts`
5. `src/contexts/runtime/application/ports/legacy-command-runner.port.ts`

Required shape (typed only, no implementations):

1. Deploy writer accepts `DeploymentPlan`.
2. Diagnostics reader returns `DriftFinding[]`.
3. Messaging repository saves/loads `MessagingPolicy`.
4. Release checker validates `ReleaseContract`.
5. Runtime runner executes legacy command contract and returns `{ exitCode, stdout, stderr }`.

All ports must be `export interface ...`.

## 4.5 Add anti-corruption legacy contracts

Create:

1. `src/legacy/bash-bridge-contract.ts`

Required exports:

1. `type LegacyFallbackReason = "ts_unavailable" | "fallback_signal" | "runtime_error"`
2. `interface LegacyCommandInvocation`
3. `interface LegacyCommandResult`
4. `interface LegacyBashBridge`

Constraints:

1. `LegacyBashBridge` is an interface only (no process execution here).
2. Keep `src/legacy/bash-bridge.ts` unchanged in this PR.

## 4.6 Add domain invariant tests (zero IO mocks)

Create:

1. `tests-ts/domain/primitives.test.ts`

Test runner:

1. Use Node test runner via `tsx --test`.
2. Use `node:assert/strict`.
3. No mocks for process/network/fs.

Required test cases:

1. `DeploymentIntent` valid + invalid channel/empty fields.
2. `DeploymentPlan` stable-channel pin requirement + invalid compat version.
3. `ProvenanceRecord` invalid channel + empty required fields.
4. `DriftFinding` invalid severity/kind.
5. `MessagingPolicy` mode/user-id invariants for all three modes.
6. `ReleaseContract` tag/version regex and exact-match invariants.

## 4.7 Update README developer section

Path: `README.md`  
Current anchor: `README.md` Developer Migration Flags section around lines `126-155`.

Action: append subsection:

Title: `Domain Primitive Tests`

Required content:

```bash
npm run test:domain-primitives
```

One sentence: these tests validate domain invariants with zero IO mocks.

## 4.8 Add deterministic verifier script

Create:

1. `scripts/verify-pr-b1-domain-primitives.sh` (executable)

Script steps:

1. Verify required new files exist (all domain primitives, ports, legacy contract, test file).
2. Run:
- `npm run typecheck`
- `npm run arch:ddd-boundaries`
- `npm run test:domain-primitives`
3. Run regression safety:
- `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`
4. Print `PR-B1 verification passed.` only on success.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f src/contexts/deploy/domain/deployment-intent.ts
test -f src/contexts/deploy/domain/deployment-plan.ts
test -f src/contexts/deploy/domain/provenance-record.ts
test -f src/contexts/diagnostics/domain/drift-finding.ts
test -f src/contexts/messaging/domain/messaging-policy.ts
test -f src/contexts/release/domain/release-contract.ts
test -f src/contexts/deploy/application/ports/deployment-plan-writer.port.ts
test -f src/contexts/diagnostics/application/ports/drift-finding-reader.port.ts
test -f src/contexts/messaging/application/ports/messaging-policy-repository.port.ts
test -f src/contexts/release/application/ports/release-contract-checker.port.ts
test -f src/contexts/runtime/application/ports/legacy-command-runner.port.ts
test -f src/legacy/bash-bridge-contract.ts
test -f tests-ts/domain/primitives.test.ts
test -f scripts/verify-pr-b1-domain-primitives.sh
```

Expected: all exit `0`.

## 5.2 Domain invariant tests

Run:

```bash
npm run test:domain-primitives
```

Expected: exit `0` and all test cases pass.

## 5.3 Boundary and type checks

Run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
```

Expected: both exit `0`.

## 5.4 No-regression runtime checks

Run:

```bash
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: exit `0` with no failed tests.

## 5.5 One-command verifier

Run:

```bash
./scripts/verify-pr-b1-domain-primitives.sh
```

Expected: exit `0`, prints `PR-B1 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. All six domain primitives exist and enforce deterministic invariants.
2. Context-level port interfaces exist and compile.
3. Legacy anti-corruption contracts exist as types/interfaces only.
4. Domain tests pass with no IO mocks.
5. `typecheck` and `arch:ddd-boundaries` pass.
6. Existing CLI behavior remains unchanged (hybrid + integration suites green).
7. No changes in:
- `hermes-fly`
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-B1: add domain primitives, port contracts, and invariant tests
```

Recommended PR title:

```text
PR-B1 Phase 0.5: domain primitives + anti-corruption contracts
```

Recommended PR checklist text:

1. Ran `npm run test:domain-primitives`
2. Ran `npm run typecheck`
3. Ran `npm run arch:ddd-boundaries`
4. Ran `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`
5. Ran `./scripts/verify-pr-b1-domain-primitives.sh`

---

## 8) Rollback

If regressions are found:

1. Revert PR-B1 commit.
2. Re-run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: behavior returns to PR-A2 baseline.

---

## References

- [Node.js test runner documentation](https://nodejs.org/api/test.html)
- [tsx GitHub repository (privatenumber/tsx)](https://github.com/privatenumber/tsx)
- [dependency-cruiser options reference](https://github.com/sverweij/dependency-cruiser/blob/main/doc/options-reference.md)
- [Node.js assert module documentation](https://nodejs.org/api/assert.html)
- [tsx test runner enhancement docs](https://github.com/privatenumber/tsx/blob/master/docs/node-enhancement.md)

## Execution Log

### Slice 1: domain-primitive invariant suite bootstrap
- [x] S4 ANALYZE_CRITERIA: 6 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/domain/primitives.test.ts`
- [x] S6 CONFIRM_RED: test fails as expected (`ERR_MODULE_NOT_FOUND` on primitive imports)
- [x] S7 IMPLEMENT: `package.json`, `tests-ts/domain/primitives.test.ts`
- [x] S8 RUN_TESTS: pass (2 iterations)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: deploy domain primitives
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/domain/primitives.test.ts` (`DeploymentIntent`/`DeploymentPlan`/`ProvenanceRecord` cases)
- [x] S6 CONFIRM_RED: test fails as expected prior to implementation
- [x] S7 IMPLEMENT: `src/contexts/deploy/domain/deployment-intent.ts`, `src/contexts/deploy/domain/deployment-plan.ts`, `src/contexts/deploy/domain/provenance-record.ts`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: diagnostics messaging release domain primitives
- [x] S4 ANALYZE_CRITERIA: 3 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/domain/primitives.test.ts` (`DriftFinding`/`MessagingPolicy`/`ReleaseContract` cases)
- [x] S6 CONFIRM_RED: test fails as expected prior to implementation
- [x] S7 IMPLEMENT: `src/contexts/diagnostics/domain/drift-finding.ts`, `src/contexts/messaging/domain/messaging-policy.ts`, `src/contexts/release/domain/release-contract.ts`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: context application ports and legacy anti-corruption contracts
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: compile-time contract checks via `npm run typecheck`
- [x] S6 CONFIRM_RED: contract references were unresolved before creation
- [x] S7 IMPLEMENT: `src/contexts/deploy/application/ports/deployment-plan-writer.port.ts`, `src/contexts/diagnostics/application/ports/drift-finding-reader.port.ts`, `src/contexts/messaging/application/ports/messaging-policy-repository.port.ts`, `src/contexts/release/application/ports/release-contract-checker.port.ts`, `src/contexts/runtime/application/ports/legacy-command-runner.port.ts`, `src/legacy/bash-bridge-contract.ts`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 5: docs and deterministic verifier
- [x] S4 ANALYZE_CRITERIA: 2 criteria extracted
- [x] S5 WRITE_TEST: verifier file-existence and command checks in `scripts/verify-pr-b1-domain-primitives.sh`
- [x] S6 CONFIRM_RED: criteria not satisfiable before README subsection/verifier creation
- [x] S7 IMPLEMENT: `README.md`, `scripts/verify-pr-b1-domain-primitives.sh`
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: used shell-based edit for `README.md` after patch tool path resolution failed in this environment (S7)

### VERIFY_ALL
- Test suite: pass (1 iteration)
- Criteria walk: all satisfied
