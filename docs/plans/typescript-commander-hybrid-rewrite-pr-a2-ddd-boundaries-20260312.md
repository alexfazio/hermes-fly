# PR-A2 Execution Plan: DDD Context Skeleton + Dependency Boundaries (Phase 0 Completion)

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-20260311.md`  
Parent phase: Phase 0 (Foundation and Safety Rails), remaining scope after PR-A1  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-a2-ddd-boundaries` (recommended)  
Implementation branch used: `main` (working tree implementation complete)

## Implementation Status

Status: Implemented  
Evidence report: `docs/plans/typescript-commander-hybrid-rewrite-pr-a2-ddd-boundaries-20260312-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Complete the remaining Phase 0 scope by adding:

1. a DDD context directory skeleton under `src/contexts/`, and
2. deterministic architecture boundary enforcement using `dependency-cruiser`.

This PR must preserve all user-facing CLI behavior and keep TS command routing unchanged from PR-A1.

---

## 2) Scope

### In scope (must ship in this PR)

1. Add `src/contexts/` bounded-context skeleton directories for:
- `deploy`
- `diagnostics`
- `messaging`
- `release`
- `runtime`

2. Add shared structure directories:
- `src/shared/core`
- `src/shared/infra`

3. Add dependency-boundary config using `dependency-cruiser`:
- new config file `dependency-cruiser.cjs`
- new `npm` script `arch:ddd-boundaries`

4. Add deterministic verification script:
- `scripts/verify-pr-a2-ddd-boundaries.sh`

5. Add minimal developer docs update:
- update `README.md` Developer Migration Flags section with architecture check command.

### Out of scope (do not do in this PR)

1. No new command implementations in TS.
2. No changes to `hermes-fly` dispatch logic.
3. No install/release guard changes.
4. No parity harness additions.
5. No domain primitives (`DeploymentIntent`, `DeploymentPlan`, etc.) yet. Those belong to PR-B1.
6. No CI workflow files yet.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm current key anchors before edits:

1. `package.json` currently has scripts at `package.json:5-8`.
2. `README.md` Developer Migration Flags section starts at `README.md:126`.
3. `src/` currently contains:
- `src/cli.ts`
- `src/version.ts`
- `src/legacy/bash-bridge.ts`

If any anchor differs materially, update line references in this plan before implementation.

---

## 4) Exact File Changes

## 4.1 Update `package.json` for architecture checks

Path: `package.json` (current file is lines `1-15`).  
Action: modify.

Required changes:

1. Add script:
- `"arch:ddd-boundaries": "depcruise --config dependency-cruiser.cjs src --output-type err-long"`

2. Add dev dependency:
- `"dependency-cruiser"` pinned to a stable major version.

3. Keep existing scripts unchanged:
- `"build"`
- `"typecheck"`

Do not add any postinstall hooks.

## 4.2 Add dependency-cruiser config

Path: `dependency-cruiser.cjs` (new file).  
Action: create.

Required rules (all severity `error`):

1. `domain` must not import `infrastructure` or `presentation` in any context.
2. `domain` must not import `src/legacy/*`.
3. Only `src/legacy/bash-bridge.ts` may import `child_process` / `node:child_process`.

Config requirements:

1. Include only `src`.
2. Use `tsconfig.json` for path/module resolution.
3. Do not follow `node_modules`.

## 4.3 Add bounded-context skeleton directories

Create these exact directory trees and place a `.gitkeep` in each leaf directory:

1. `src/contexts/deploy/domain/.gitkeep`
2. `src/contexts/deploy/application/ports/.gitkeep`
3. `src/contexts/deploy/infrastructure/.gitkeep`
4. `src/contexts/deploy/presentation/.gitkeep`

5. `src/contexts/diagnostics/domain/.gitkeep`
6. `src/contexts/diagnostics/application/ports/.gitkeep`
7. `src/contexts/diagnostics/infrastructure/.gitkeep`
8. `src/contexts/diagnostics/presentation/.gitkeep`

9. `src/contexts/messaging/domain/.gitkeep`
10. `src/contexts/messaging/application/ports/.gitkeep`
11. `src/contexts/messaging/infrastructure/.gitkeep`
12. `src/contexts/messaging/presentation/.gitkeep`

13. `src/contexts/release/domain/.gitkeep`
14. `src/contexts/release/application/ports/.gitkeep`
15. `src/contexts/release/infrastructure/.gitkeep`
16. `src/contexts/release/presentation/.gitkeep`

17. `src/contexts/runtime/domain/.gitkeep`
18. `src/contexts/runtime/application/ports/.gitkeep`
19. `src/contexts/runtime/infrastructure/.gitkeep`
20. `src/contexts/runtime/presentation/.gitkeep`

## 4.4 Add shared skeleton directories

Create:

1. `src/shared/core/.gitkeep`
2. `src/shared/infra/.gitkeep`

## 4.5 Update README developer section (minimal)

Path: `README.md`  
Current anchor: Developer section at `README.md:126-147`.

Action: append short subsection under Developer Migration Flags:

Title: `Architecture Boundary Check`

Required text:

1. One sentence explaining this check enforces DDD layering constraints.
2. Command:

```bash
npm run arch:ddd-boundaries
```

No changes to user-facing install/deploy instructions.

## 4.6 Add deterministic verifier script

Path: `scripts/verify-pr-a2-ddd-boundaries.sh` (new file).  
Action: create executable script.

Script must perform all checks in order:

1. File existence checks for:
- `dependency-cruiser.cjs`
- all skeleton `.gitkeep` paths listed above.

2. Run:
- `npm run arch:ddd-boundaries`

3. Negative boundary test (must fail):
- create temporary files:
  - `src/contexts/runtime/infrastructure/__tmp_boundary_target.ts`
  - `src/contexts/runtime/domain/__tmp_boundary_violation.ts`
- make domain file import the infrastructure temp file.
- run `npm run arch:ddd-boundaries` and assert non-zero exit.
- clean temp files.

4. Regression safety:
- run `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`

Output contract:

- print `PR-A2 verification passed.` only if all checks pass.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f dependency-cruiser.cjs
test -f src/contexts/deploy/domain/.gitkeep
test -f src/contexts/diagnostics/domain/.gitkeep
test -f src/contexts/messaging/domain/.gitkeep
test -f src/contexts/release/domain/.gitkeep
test -f src/contexts/runtime/domain/.gitkeep
test -f src/shared/core/.gitkeep
test -f src/shared/infra/.gitkeep
test -f scripts/verify-pr-a2-ddd-boundaries.sh
```

Expected: all exit `0`.

## 5.2 Boundary check passes

Run:

```bash
npm run arch:ddd-boundaries
```

Expected: exit `0`.

## 5.3 Boundary check negative test fails deterministically

Run:

```bash
tmp_target="src/contexts/runtime/infrastructure/__tmp_boundary_target.ts"
tmp_violation="src/contexts/runtime/domain/__tmp_boundary_violation.ts"
printf 'export const x = 1;\n' > "${tmp_target}"
printf 'import "../infrastructure/__tmp_boundary_target.js";\nexport const y = 2;\n' > "${tmp_violation}"
npm run arch:ddd-boundaries && exit 1 || true
rm -f "${tmp_target}" "${tmp_violation}"
```

Expected:

1. `npm run arch:ddd-boundaries` returns non-zero while temp violation exists.
2. After cleanup, `npm run arch:ddd-boundaries` returns `0`.

## 5.4 No-regression runtime checks

Run:

```bash
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: exit `0` with no failed tests.

## 5.5 One-command verifier

Run:

```bash
./scripts/verify-pr-a2-ddd-boundaries.sh
```

Expected: script exits `0` and prints `PR-A2 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. Context and shared skeleton directories exist exactly as defined.
2. `dependency-cruiser.cjs` enforces the required forbidden dependency directions.
3. `npm run arch:ddd-boundaries` passes on clean tree.
4. Negative boundary smoke test fails as expected and then passes after cleanup.
5. Existing bash CLI behavior remains unchanged (hybrid + integration suites green).
6. Verifier script is executable and succeeds.
7. No changes in:
- `hermes-fly`
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-A2: add DDD context skeleton and dependency boundary enforcement
```

Recommended PR title:

```text
PR-A2 Foundation: DDD skeleton + depcruise boundary checks
```

Recommended PR checklist text:

1. Ran `npm run arch:ddd-boundaries`
2. Ran `./scripts/verify-pr-a2-ddd-boundaries.sh`
3. Ran `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`

---

## 8) Rollback

If regressions are found:

1. Revert PR-A2 commit.
2. Re-run:

```bash
npm run typecheck
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: behavior returns to PR-A1 baseline.

---

## References

- [dependency-cruiser CLI documentation](https://github.com/sverweij/dependency-cruiser/blob/main/doc/cli.md)
- [dependency-cruiser options reference (tsConfig)](https://github.com/sverweij/dependency-cruiser/blob/main/doc/options-reference.md)
- [dependency-cruiser README](https://github.com/sverweij/dependency-cruiser/blob/main/README.md)
