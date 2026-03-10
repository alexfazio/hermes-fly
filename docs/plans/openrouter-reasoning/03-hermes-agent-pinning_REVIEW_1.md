# REVIEW_1: Findings with Implementer Instructions

Reference design document:
- `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/openrouter-reasoning/03-hermes-agent-pinning.md`

## Workspace Constraint (must follow)
- Implement all fixes only in the PR worktree:
  `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/hidden-cuddling-scroll`
- Do not implement code changes in the base checkout path:
  `/Users/alex/Documents/GitHub/hermes-fly`
- Run all validation commands from the worktree path above.

## Findings

## CRITICAL

### C1. `deploy_resolve_hermes_ref warns on non-default override` test is asserting the wrong stream
- Problem summary:
  The test currently checks warning text in captured output, but warning text is written via `ui_warn` (stderr). In this suite, current assertions effectively target stdout unless stderr is explicitly captured.
- Actionable implementation instructions:
  1. Update the test to intentionally capture stderr for this assertion.
  2. Preferred pattern:
     - execute through `bash -c '... deploy_resolve_hermes_ref 2>&1'`,
     - assert both override value and warning text in combined output.
  3. Ensure the test fails if warning is removed or routed incorrectly.
  4. Add a companion assertion (or separate test) that default path does not emit the non-reproducible warning.

## MEDIUM

### M1. `HERMES_AGENT_REF` override is not safe for `sed` replacement input
- Problem summary:
  `docker_generate_dockerfile` uses `sed` replacement with `|` as delimiter. A valid ref containing `|` (and potentially other replacement-significant characters) can break rendering.
- Actionable implementation instructions:
  1. Introduce safe replacement handling before `sed` substitution:
     - either escape replacement-significant characters in version input,
     - or switch to a rendering strategy that does not treat ref content as `sed` syntax.
  2. Preserve literal value in final Dockerfile (`ARG HERMES_VERSION=...`) after rendering.
  3. Keep support for normal refs:
     - commit SHA,
     - tags like `v1.5.0`,
     - branch-like names with `/`.
  4. Add at least one regression test proving a ref containing `|` does not break Dockerfile generation.
  5. Add one additional escaping test for another risky character pattern (for example `&`), and verify output is literal.

### M2. Redundant `>&2` redirect on `ui_warn` call
- Problem summary:
  `ui_warn` already writes to stderr; appending `>&2` is redundant and inconsistent.
- Actionable implementation instructions:
  1. Remove explicit `>&2` from the `ui_warn` call in `deploy_resolve_hermes_ref`.
  2. Keep warning text unchanged.
  3. Do not introduce new wrappers around `ui_warn`.

### M3. `DEPLOY_HERMES_AGENT_REF` is set only after first failure point in build-context creation
- Problem summary:
  If Dockerfile generation fails, the resolved ref may never be exported, limiting failure diagnostics and post-failure observability.
- Actionable implementation instructions:
  1. Set and export `DEPLOY_HERMES_AGENT_REF` immediately after resolving `hermes_ref`, before Dockerfile generation.
  2. Keep current success-path behavior unchanged.
  3. Add/adjust a test for failure path:
     - force `docker_generate_dockerfile` to fail,
     - assert `DEPLOY_HERMES_AGENT_REF` is still set for diagnostics.

## MINOR

### L1. Explicit `return 0` in `deploy_resolve_hermes_ref` is stylistically redundant
- Problem summary:
  The explicit success return is not harmful, but differs from common style in adjacent functions.
- Actionable implementation instructions:
  1. Choose one style and keep it consistent:
     - keep `return 0` with a brief comment about explicit contract,
     - or remove it if style guide prefers implicit success.
  2. No functional behavior change required.

### L2. Summary output allows empty `hermes_agent_ref` field
- Problem summary:
  `${DEPLOY_HERMES_AGENT_REF:-}` can render as empty (`hermes_agent_ref:`), which is valid YAML but ambiguous.
- Actionable implementation instructions:
  1. Ensure the field is always deterministic:
     - either guarantee variable is always populated before summary writing,
     - or emit explicit fallback token like `unknown`.
  2. Add test coverage for unset-path behavior if fallback token is used.
  3. Keep backward-compatible summary format otherwise.

### L3. Missing direct test for constant integrity
- Problem summary:
  Existing tests validate resolved output shape, but there is no explicit guard that the pinned constant itself is not reverted to a moving branch name.
- Actionable implementation instructions:
  1. Add a targeted test asserting:
     - `HERMES_AGENT_DEFAULT_REF` is exactly 40 lowercase hex chars,
     - value is not `main`.
  2. Place this near other pinning tests in `tests/deploy.bats`.

---

## Highly Detailed Validation Criteria (Implementer Exit Gate)

Run from:
`cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/hidden-cuddling-scroll`

### A. Workspace and scope checks
1. Confirm worktree context:
   - Command: `git rev-parse --abbrev-ref HEAD && pwd`
   - Expect:
     - branch `worktree-hidden-cuddling-scroll`
     - current path is the worktree path above.
2. Confirm only expected files changed:
   - Command: `git status --short`
   - Expect: changes limited to relevant implementation/test files (for example `lib/deploy.sh`, `lib/docker-helpers.sh`, `tests/deploy.bats`, `tests/docker-helpers.bats`).

### B. Static checks by finding
1. C1 stream-capture test correctness:
   - Command: `rg -n "deploy_resolve_hermes_ref warns on non-default override|2>&1|stderr" tests/deploy.bats`
   - Expect:
     - warning test explicitly captures stderr or combined streams before asserting warning text.
2. M1 escaping/render safety:
   - Command: `rg -n "docker_generate_dockerfile|HERMES_VERSION|sed|escape" lib/docker-helpers.sh lib/deploy.sh`
   - Expect:
     - explicit handling for replacement-sensitive characters in ref input,
     - no unguarded direct interpolation vulnerable to delimiter/meta breakage.
3. M2 redundant redirect cleanup:
   - Command: `rg -n 'ui_warn "Using custom Hermes Agent ref:.*>&2' lib/deploy.sh`
   - Expect: no matches.
4. M3 ref export timing:
   - Command: `rg -n "DEPLOY_HERMES_AGENT_REF|deploy_create_build_context|docker_generate_dockerfile" lib/deploy.sh`
   - Expect:
     - `DEPLOY_HERMES_AGENT_REF` assigned/exported before first failure-prone generation call.
5. L3 constant guard test presence:
   - Command: `rg -n "HERMES_AGENT_DEFAULT_REF|40-char|not main|[0-9a-f]{40}" tests/deploy.bats`
   - Expect:
     - an explicit constant-integrity regression test exists.

### C. Deterministic manual repro checks
1. Repro for problematic `|` ref must succeed:
   - Command:
     ```bash
     bash -lc '
       set -euo pipefail
       cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/hidden-cuddling-scroll
       source lib/ui.sh
       source lib/fly-helpers.sh
       source lib/docker-helpers.sh
       source lib/messaging.sh
       source lib/config.sh
       source lib/status.sh
       source lib/reasoning.sh
       source lib/openrouter.sh
       source lib/deploy.sh
       export DEPLOY_APP_NAME=test DEPLOY_REGION=ord DEPLOY_VM_SIZE=shared-cpu-1x DEPLOY_VM_MEMORY=256mb DEPLOY_VOLUME_SIZE=5
       export HERMES_AGENT_REF="feature|pipe"
       deploy_create_build_context
       grep -n "HERMES_VERSION=feature|pipe" "${DEPLOY_BUILD_DIR}/Dockerfile"
     '
     ```
   - Expect:
     - command exits `0`,
     - no `sed` parsing error,
     - Dockerfile contains literal `HERMES_VERSION=feature|pipe`.
2. Default path warning behavior:
   - Command:
     ```bash
     bash -lc '
       set -euo pipefail
       cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/hidden-cuddling-scroll
       source lib/ui.sh
       source lib/fly-helpers.sh
       source lib/docker-helpers.sh
       source lib/messaging.sh
       source lib/config.sh
       source lib/status.sh
       source lib/reasoning.sh
       source lib/openrouter.sh
       source lib/deploy.sh
       unset HERMES_AGENT_REF
       out="$(deploy_resolve_hermes_ref 2>/tmp/pr3_warn.err)"
       echo "OUT=$out"
       if grep -q "non-reproducible build" /tmp/pr3_warn.err; then echo "WARNED"; else echo "NO_WARN"; fi
     '
     ```
   - Expect:
     - output has 40-char SHA,
     - `NO_WARN` in default path.

### D. Automated test validation
1. Run affected suites:
   - Command: `bats tests/deploy.bats tests/docker-helpers.bats`
   - Expect: all tests pass.
2. Optional confidence run:
   - Command: `bats tests/deploy.bats tests/docker-helpers.bats tests/install.bats`
   - Expect: all pass, no regressions.

### E. Handoff acceptance criteria
1. Each finding C1, M1, M2, M3, L1, L2, L3 has a corresponding code/test action or explicit no-change rationale.
2. Manual `feature|pipe` reproduction no longer fails.
3. Warning test verifies actual warning emission path (stderr/combined stream), not only stdout.
4. Ref metadata remains deterministic and visible in success/summary outputs.
5. PR note includes:
   - files changed,
   - explicit mention of ref-input escaping strategy,
   - test commands run and pass counts.
