# REVIEW_2: Findings with Implementer Instructions

Reference design document:
- `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/openrouter-reasoning/03-hermes-agent-pinning.md`

## Workspace Constraint (must follow)
- Implement all code/test changes only in:
  `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/hidden-cuddling-scroll`
- Do not implement fixes in the base checkout path:
  `/Users/alex/Documents/GitHub/hermes-fly`
- Run all validation commands from the PR worktree path above.

## Findings

## LOW

### L1. Failure-path regression test does not assert that failure path actually happened
- Location:
  - `tests/deploy.bats` (failure-path test around `deploy_create_build_context`)
- Problem summary:
  The test forces an invalid template directory and checks that `DEPLOY_HERMES_AGENT_REF` is set, but does not assert that `deploy_create_build_context` returned failure. The test can pass even if the function unexpectedly succeeds.
- Actionable implementation instructions:
  1. Update the test to explicitly capture and assert non-zero return code from `deploy_create_build_context`.
  2. Recommended pattern:
     - run function in a subshell/script block,
     - capture `rc=$?`,
     - print `RC=${rc}`,
     - assert `RC=1` (or expected non-zero) in test output.
  3. Keep existing assertion that `DEPLOY_HERMES_AGENT_REF` is still populated after failure.
  4. Ensure the test fails if either condition is false:
     - function does not fail,
     - ref variable is empty.

## INFO / DESIGN-CHOICE

### I1. `HERMES_AGENT_DEFAULT_REF` is not `readonly`
- Location:
  - `lib/deploy.sh` constant declaration.
- Problem summary:
  Constant can be overridden at runtime. This is currently consistent with other project-level constants and covered by integrity tests.
- Actionable implementation instructions:
  1. Decide explicitly whether to keep project convention or harden with `readonly`.
  2. If keeping current behavior (recommended for consistency with existing module style):
     - add a short in-code comment explaining why it is intentionally not `readonly`,
     - keep the existing test guard that enforces SHA shape and non-`main`.
  3. If switching to `readonly`:
     - verify no tests or flows intentionally override it,
     - update any impacted tests accordingly.
  4. In either case, record the decision in PR notes for maintainers.

### I2. `assert_output --partial "REF="` in M3 test is weak/redundant
- Location:
  - `tests/deploy.bats` M3 failure-path test.
- Problem summary:
  `assert_output --partial "REF="` is satisfied by both valid values and `REF=EMPTY`. The real guard is `refute_output --partial "REF=EMPTY"`.
- Actionable implementation instructions:
  1. Strengthen the assertion to a value-shape check instead of generic presence.
  2. Suggested options:
     - assert partial `REF=[0-9a-f]` with regex-based check in shell,
     - or parse/refute exact bad sentinel and assert expected SHA/tag format.
  3. Keep the negative assertion against `REF=EMPTY` if useful for readability.
  4. Ensure the final test intent is explicit in a one-line comment.

---

## Highly Detailed Validation Criteria (Implementer Exit Gate)

Run from:
`cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/hidden-cuddling-scroll`

### A. Workspace and scope checks
1. Confirm correct worktree:
   - Command: `git rev-parse --abbrev-ref HEAD && pwd`
   - Expect:
     - branch is `worktree-hidden-cuddling-scroll`,
     - working directory is the worktree path above.
2. Confirm change scope:
   - Command: `git status --short`
   - Expect: changes are limited to review-driven files (typically `tests/deploy.bats`, and possibly `lib/deploy.sh` if documenting/adjusting constant decision).

### B. Static checks by finding
1. L1 failure-path assertion hardening:
   - Command: `rg -n "deploy_create_build_context.*failure|RC=|refute_output --partial \"REF=EMPTY\"|M3" tests/deploy.bats`
   - Expect:
     - test asserts explicit non-zero return code,
     - test still asserts non-empty ref value after failure.
2. I1 constant decision clarity:
   - Command: `rg -n "HERMES_AGENT_DEFAULT_REF|readonly|not readonly|constant" lib/deploy.sh tests/deploy.bats`
   - Expect:
     - either explicit `readonly` enforcement and compatible tests,
     - or explicit rationale comment plus integrity guard test.
3. I2 assertion strength:
   - Command: `rg -n "REF=|REF=EMPTY|regex|40-char|[0-9a-f]{40}" tests/deploy.bats`
   - Expect:
     - no weak presence-only assertion as primary check,
     - at least one value-quality assertion exists.

### C. Deterministic manual validation snippets
1. Failure-path behavior (L1):
   - Run a shell snippet that:
     - sets invalid `DOCKER_HELPERS_TEMPLATE_DIR`,
     - invokes `deploy_create_build_context`,
     - prints `RC` and `DEPLOY_HERMES_AGENT_REF`.
   - Expect:
     - `RC` is non-zero,
     - `DEPLOY_HERMES_AGENT_REF` is non-empty.
2. Constant guard behavior (I1):
   - Run:
     - `source lib/deploy.sh`,
     - print `HERMES_AGENT_DEFAULT_REF`,
     - verify it is 40 lowercase hex and not `main`.
   - Expect:
     - pinned SHA shape remains valid.

### D. Automated test validation
1. Run focused suite:
   - Command: `bats tests/deploy.bats`
   - Expect: all tests pass, including strengthened M3 failure-path assertions.
2. Optional companion run:
   - Command: `bats tests/docker-helpers.bats`
   - Expect: all pinning-related rendering tests pass.

### E. Handoff acceptance criteria
1. Each finding (`L1`, `I1`, `I2`) has either:
   - concrete code/test change, or
   - explicit documented no-change rationale.
2. Failure-path test now proves both:
   - failure occurred,
   - diagnostics ref is preserved.
3. Pinned-ref constant decision is explicit and traceable in code and/or PR notes.
4. Final PR note includes:
   - files changed,
   - brief summary of test-hardening changes,
   - exact test commands run and pass counts.
