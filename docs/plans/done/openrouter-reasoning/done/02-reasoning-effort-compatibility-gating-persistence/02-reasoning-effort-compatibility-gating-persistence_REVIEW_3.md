# REVIEW_3: Findings with Implementer Instructions

## Workspace Constraint (must follow)
- Implement all code and test changes only in:
  `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp`
- Do not implement fixes in the base checkout path:
  `/Users/alex/Documents/GitHub/hermes-fly`
- This review file can live in the base checkout for planning, but implementation and validation must run from the PR worktree above.

## MEDIUM

### M1. Redundant `>&2` on `ui_warn` call
- Location: `lib/deploy.sh` fallback path for reasoning effort default.
- Problem summary:
  `ui_warn` already writes to stderr; appending `>&2` is redundant and inconsistent with usage elsewhere.
- Actionable implementation instructions:
  1. In worktree file `lib/deploy.sh`, remove `>&2` from:
     `ui_warn "Using default reasoning effort: ${DEPLOY_REASONING_EFFORT}" >&2`
  2. Keep the warning message text unchanged.
  3. Do not add any additional stdout/stderr redirection wrappers around `ui_warn`.
  4. If needed, add/update one assertion in `tests/deploy.bats` that still matches the warning text in stderr output when fallback occurs.

### M2. `default_idx` readability regression (two-pass iteration)
- Location: `lib/reasoning.sh` `reasoning_prompt_effort()`.
- Problem summary:
  The code now computes `default_idx` in one loop, then re-loops for display and selection. It is functionally correct but harder to follow.
- Actionable implementation instructions:
  1. Refactor `reasoning_prompt_effort()` so `default_idx` is established in the same rendering flow, not via a separate pre-pass.
  2. Preserve current behavior exactly:
     - max attempts remains bounded,
     - default marker still appears on the recommended option,
     - numeric validation remains strict,
     - return codes/flow remain deterministic.
  3. Keep output text stable unless tests intentionally update expected strings.
  4. Add an inline comment only if needed to explain retry-loop control flow.

## LOW

### L1. `local` declarations inside retry loop
- Location: `lib/reasoning.sh` inside the `while` retry loop.
- Problem summary:
  `local marker` and `local choice` are declared repeatedly inside loop body. In Bash, `local` is function-scoped, so this is redundant.
- Actionable implementation instructions:
  1. Move loop-variable `local` declarations (`marker`, `choice`, and similar loop-reused locals) to the function scope before entering the loop.
  2. Assign/reset them inside the loop without re-declaring.
  3. Keep behavior and printed output unchanged.

### L2. Inconsistent test plumbing for secrets log path
- Location: `tests/deploy.bats` AC-05 tests.
- Problem summary:
  One test uses exported `HERMES_SECRETS_LOG`, another hardcodes `BATS_TEST_TMPDIR`; mixed style in adjacent tests is confusing.
- Actionable implementation instructions:
  1. Standardize both related AC-05 tests to one mechanism.
  2. Preferred: keep explicit injected env var (`HERMES_SECRETS_LOG`) for both tests, since it avoids hidden path coupling.
  3. Ensure both tests still verify exact `HERMES_REASONING_EFFORT=<value>` lines in captured secret payloads.
  4. Remove unused variables after standardization.

### L3. Retry-attempt test is tightly coupled to hardcoded attempt count
- Location: `tests/reasoning.bats` invalid-input retry test.
- Problem summary:
  The test hardcodes exactly three invalid inputs (`99`, `abc`, `0`), implicitly coupled to `max_attempts=3`.
- Actionable implementation instructions:
  1. Introduce a single source of truth for max attempts in `lib/reasoning.sh` (for example, a readonly variable or clearly named constant).
  2. Use that constant in `reasoning_prompt_effort()` instead of a magic number.
  3. Update `tests/reasoning.bats` to derive invalid-input count from the same constant when practical; if dynamic generation is too noisy, add an explicit comment referencing the shared constant and why the count must match.
  4. Keep test intent explicit: failure occurs only after exhausting configured attempts.

### L4. Snapshot parsing lacks enforceable shape validation
- Location: `lib/reasoning.sh`, `data/reasoning-snapshot.json`.
- Problem summary:
  Parsing uses `sed` and assumes flat family objects. The new `_constraint` comment documents this, but there is no runtime schema validation.
- Actionable implementation instructions:
  1. Add lightweight runtime validation during `_reasoning_load_snapshot`:
     - verify top-level required keys exist (`schema_version`, `policy_version`, `families`);
     - verify each family block contains `allowed_efforts` and `default`;
     - reject clearly nested family blocks that would break current `sed` extraction.
  2. On validation failure:
     - emit a clear warning (`ui_warn` if available, otherwise stderr),
     - disable snapshot usage safely (empty raw/version) so behavior is conservative.
  3. Add/extend tests in `tests/reasoning.bats` with malformed snapshot fixtures to confirm:
     - validation failure is detected,
     - fallback behavior remains safe (`unknown`/conservative defaults),
     - no shell error/exit due to malformed content.

### L5. Retry exhaustion still auto-falls back to default effort
- Location: `lib/reasoning.sh` + `lib/deploy.sh` integration path.
- Problem summary:
  After max invalid attempts, flow still sets default effort and continues deployment. This can mask persistent user input failure.
- Actionable implementation instructions:
  1. Differentiate failure reasons from `reasoning_prompt_effort()`:
     - success (selected value),
     - user cancel/EOF,
     - retry exhaustion.
  2. In `deploy_collect_llm_config()`, handle retry exhaustion as a hard failure for configuration (return non-zero) instead of silently continuing with default.
  3. Keep cancel/EOF policy explicit and documented in code comments.
  4. Add `tests/deploy.bats` coverage for:
     - exhaustion path aborts config collection,
     - default is not injected on exhaustion unless policy explicitly allows it.

---

## Highly Detailed Validation Criteria (Implementer Exit Gate)

Run all commands from the PR worktree only:

`cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp`

### A. Workspace and diff hygiene
1. Confirm branch and root:
   - Command: `git rev-parse --abbrev-ref HEAD && pwd`
   - Expect: branch `worktree-steady-hugging-karp` and worktree path, not base checkout.
2. Confirm only intended files changed:
   - Command: `git status --short`
   - Expect: changes limited to `lib/reasoning.sh`, `lib/deploy.sh`, `tests/reasoning.bats`, `tests/deploy.bats`, and any minimal directly related files.

### B. Finding-by-finding static checks
1. M1 (`ui_warn` redirect cleanup):
   - Command: `rg -n 'ui_warn "Using default reasoning effort:.*>&2' lib/deploy.sh`
   - Expect: no matches.
2. M2/L1 (prompt-loop readability and local declarations):
   - Command: `nl -ba lib/reasoning.sh | sed -n '220,340p'`
   - Expect:
     - no separate pre-pass loop solely for `default_idx`,
     - loop locals declared once at function scope (not re-`local` each retry iteration).
3. L2 (test consistency for secret log path):
   - Command: `rg -n 'HERMES_SECRETS_LOG|secrets_log|BATS_TEST_TMPDIR' tests/deploy.bats`
   - Expect: one consistent pattern across both AC-05 tests.
4. L3 (shared max-attempts source):
   - Command: `rg -n 'max_attempts|REASONING_.*ATTEMPTS' lib/reasoning.sh tests/reasoning.bats`
   - Expect: test dependency on attempt count is explicit and traceable to one authoritative source.
5. L4 (snapshot validation present):
   - Command: `rg -n '_reasoning_load_snapshot|validate|schema_version|families' lib/reasoning.sh`
   - Expect: explicit runtime validation path before accepting snapshot content.
6. L5 (retry exhaustion policy):
   - Command: `rg -n 'retry exhaustion|Too many invalid attempts|return [0-9]|DEPLOY_REASONING_EFFORT' lib/reasoning.sh lib/deploy.sh`
   - Expect: exhaustion is distinguishable and handled per policy (prefer abort path).

### C. Automated test validation
1. Run targeted suites:
   - Command: `bats tests/reasoning.bats tests/deploy.bats`
   - Expect: all tests pass.
2. Run install regression suite (ensures prior packaging fix remains intact):
   - Command: `bats tests/install.bats`
   - Expect: all tests pass, including `data/reasoning-snapshot.json` install coverage.
3. Optional broader confidence run:
   - Command: `bats tests/reasoning.bats tests/deploy.bats tests/scaffold.bats`
   - Expect: all pass without new failures.

### D. Behavioral validation snippets (manual but deterministic)
1. Retry exhaustion must not silently continue (L5):
   - Run a shell snippet that feeds invalid reasoning choices repeatedly during `deploy_collect_llm_config`.
   - Expect:
     - function returns non-zero on exhaustion,
     - no silent success with injected default unless policy explicitly permits and is documented.
2. Snapshot malformed fixture (L4):
   - Use temporary malformed JSON fixture with nested family object.
   - Call `_reasoning_load_snapshot` + `reasoning_get_allowed_efforts`.
   - Expect:
     - warning about invalid shape,
     - conservative fallback values returned,
     - no crash.
3. Non-exhausted retry still works:
   - Feed one invalid value then one valid value.
   - Expect:
     - selected valid effort returned,
     - no forced default warning.

### E. Acceptance criteria for handoff
1. Every finding M1, M2, L1, L2, L3, L4, L5 has a corresponding concrete code/test change.
2. All validation commands above executed successfully in the PR worktree.
3. Final PR note includes:
   - exact files changed,
   - summary of policy decision for retry exhaustion,
   - test command output summary (pass counts).
