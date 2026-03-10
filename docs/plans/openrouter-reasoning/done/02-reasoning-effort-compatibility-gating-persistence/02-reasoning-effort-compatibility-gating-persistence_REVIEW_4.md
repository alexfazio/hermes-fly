# REVIEW_4: Findings with Implementer Instructions

## Workspace Constraint (must follow)
- Implement all code/test fixes only in the PR worktree:
  `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp`
- Do not implement fixes in the base checkout root path.
- This review file is planning guidance; implementation and validation must run in the worktree above.

## HIGH

### H1. `_reasoning_load_snapshot` can hard-exit under `set -euo pipefail` when `families` has no matched objects
- Location:
  - `lib/reasoning.sh` (`_reasoning_load_snapshot`, `family_names` extraction pipeline)
- Problem summary:
  `family_names` is assigned from a pipeline using `grep` inside command substitution.
  With `set -e` + `pipefail`, a no-match `grep` returns exit code `1`, which can abort the shell before graceful fallback logic runs.
- Impact:
  `hermes-fly` can fail at startup if snapshot top-level keys exist but `families` is empty (or otherwise yields no object matches).

### Actionable implementation instructions
1. Make family-name extraction non-fatal under `set -euo pipefail`.
   - In `_reasoning_load_snapshot`, replace the current `family_names="$( ...grep... )"` approach with a pattern that cannot hard-exit on no matches.
   - Acceptable approaches:
     - add `|| true` at the right boundary of the extraction command substitution,
     - or switch to parsing logic that naturally returns success with empty output (for example, `awk`/`sed` pipeline that does not rely on failing `grep` for control flow),
     - or wrap the extraction in an explicit conditional that safely handles zero matches.
2. Treat empty extracted families as validation failure, not shell failure.
   - If no family names are found:
     - emit a warning message,
     - set `_REASONING_SNAPSHOT_RAW=""`,
     - set `REASONING_SNAPSHOT_VERSION=""`,
     - return success from the loader function (do not crash caller), so downstream logic uses conservative defaults.
3. Keep current conservative fallback semantics unchanged.
   - `reasoning_get_allowed_efforts` should still return `low|medium|high` when snapshot is disabled.
   - `reasoning_get_default` should still return `medium` when snapshot is disabled.
   - `reasoning_model_supports_reasoning` should still return failure when snapshot is disabled.
4. Add targeted regression tests in `tests/reasoning.bats`.
   - Add a test that runs under `set -euo pipefail` with snapshot:
     `{"schema_version":"1","policy_version":"1.0.0","families":{}}`
   - Assert:
     - function does not crash process,
     - warning is emitted,
     - snapshot variables are cleared,
     - conservative fallback outputs are returned.
5. Add at least one additional no-match variant.
   - Example: a snapshot where top-level keys exist but family blocks are malformed such that family-name extraction yields zero.
   - Assert identical non-crashing fallback behavior.

---

## Highly Detailed Validation Criteria (Implementer Exit Gate)

Run all commands from the PR worktree:

`cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp`

### A. Workspace and change scope
1. Confirm you are in the worktree:
   - Command: `git rev-parse --abbrev-ref HEAD && pwd`
   - Expect:
     - branch is `worktree-steady-hugging-karp`
     - path is the `.claude/worktrees/steady-hugging-karp` directory.
2. Confirm changed files are relevant:
   - Command: `git status --short`
   - Expect: only `lib/reasoning.sh` and related tests/docs for this finding are modified.

### B. Static checks for the fix
1. Verify family extraction no longer has fatal no-match behavior:
   - Command: `rg -n "family_names=.*grep|for fname in \\$family_names|_reasoning_load_snapshot" lib/reasoning.sh`
   - Expect:
     - extraction path is visibly guarded against no-match failures (`|| true` or equivalent non-fatal flow),
     - loader handles empty extraction explicitly.
2. Verify explicit empty-family handling exists:
   - Command: `rg -n "no family|missing family|disabling|_REASONING_SNAPSHOT_RAW=\"\"|REASONING_SNAPSHOT_VERSION=\"\"" lib/reasoning.sh`
   - Expect:
     - clear disable/reset branch for zero extracted families.

### C. Deterministic manual runtime validation
1. Reproduce previous crash case (must no longer crash):
   - Command:
     ```bash
     bash -lc '
       set -euo pipefail
       cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp
       source lib/ui.sh
       source lib/reasoning.sh
       tmpf="$(mktemp)"
       printf "%s\n" "{\"schema_version\":\"1\",\"policy_version\":\"1.0.0\",\"families\":{}}" > "$tmpf"
       _REASONING_SNAPSHOT_FILE="$tmpf"
       _reasoning_load_snapshot
       echo "LOADER_OK"
       echo "RAW=${_REASONING_SNAPSHOT_RAW:-empty}"
       echo "VER=${REASONING_SNAPSHOT_VERSION:-empty}"
       echo "ALLOWED=$(reasoning_get_allowed_efforts gpt-5)"
       echo "DEFAULT=$(reasoning_get_default gpt-5)"
     '
     ```
   - Expect:
     - command exits `0`,
     - output includes `LOADER_OK`,
     - `RAW=empty`,
     - `VER=empty`,
     - `ALLOWED=low|medium|high`,
     - `DEFAULT=medium`.
2. Validate a standard valid snapshot still works:
   - Command:
     ```bash
     bash -lc '
       set -euo pipefail
       cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp
       source lib/ui.sh
       source lib/reasoning.sh
       echo "ALLOWED=$(reasoning_get_allowed_efforts gpt-5)"
       echo "DEFAULT=$(reasoning_get_default gpt-5)"
     '
     ```
   - Expect:
     - `ALLOWED=low|medium|high`
     - `DEFAULT=medium`
     - no warnings for the bundled snapshot.

### D. Automated test validation
1. Run reasoning tests:
   - Command: `bats tests/reasoning.bats`
   - Expect: all tests pass, including new no-crash empty-families coverage.
2. Run dependent deploy tests:
   - Command: `bats tests/deploy.bats`
   - Expect: all tests pass (no regression in reasoning prompt integration).
3. Run install regression tests:
   - Command: `bats tests/install.bats`
   - Expect: all tests pass (ensures no collateral regression in prior fixes).

### E. Acceptance criteria for handoff
1. Previous crash reproduction no longer exits non-zero.
2. Snapshot loader now fails closed (disables snapshot) instead of failing hard.
3. Conservative fallback behavior remains unchanged and verified.
4. New tests cover:
   - empty `families` under `set -euo pipefail`,
   - at least one additional zero-family-match case.
5. PR notes include:
   - exact files changed,
   - brief root-cause explanation,
   - test commands run and pass counts.

---

## Additional Findings (Addendum, Non-Blocking Unless Elevated)

## MEDIUM

### M1. Family extraction regex can match future non-family top-level object keys
- Location:
  - `lib/reasoning.sh` (family-name extraction around current regex-based object-key scan)
- Problem summary:
  The extraction pattern matches keys whose values begin with `{`.
  Today this works with the current snapshot shape and explicit exclusions, but if a new top-level object-valued key (for example, `"metadata": {...}`) is added, it can be misclassified as a family and cause validation disable/failure.
- Actionable implementation instructions:
  1. Prefer extracting family keys from within the `"families"` object only, instead of scanning all top-level object-valued keys.
  2. If a full parser is intentionally avoided, add explicit exclusions for known non-family keys (including `"_constraint"`) and document this as an assumption.
  3. Add a regression test fixture with a non-family top-level object key and verify:
     - it is not treated as a family,
     - snapshot handling remains stable,
     - no false validation failure is triggered.
  4. Add a short code comment near extraction logic explaining scope and maintenance expectations for future snapshot schema changes.

### M2. `_reasoning_load_snapshot` runs at source time and can emit stderr on every invocation
- Location:
  - `lib/reasoning.sh` (source-time `_reasoning_load_snapshot` call)
- Problem summary:
  Validation warnings are emitted during sourcing. If snapshot content is corrupt, commands like `hermes-fly help` or `hermes-fly --version` may print warnings before command output.
  This is fail-visible and reasonable, but should be explicitly treated as a design choice.
- Actionable implementation instructions:
  1. Keep current fail-visible behavior unless product direction changes.
  2. Document the behavior in module header comments:
     - loader runs at source time,
     - warnings are expected on corrupt snapshots,
     - conservative fallback is applied.
  3. Add a brief note in PR description/release notes so maintainers understand why warnings can appear on non-deploy commands.
  4. Optional (only if desired by maintainers): gate warning emission behind a documented environment flag, defaulting to current visible behavior.

## LOW

### L1. `for fname in $family_names` relies on word splitting
- Location:
  - `lib/reasoning.sh` (family loop in `_reasoning_load_snapshot`)
- Problem summary:
  Current regex-constrained names make this safe in practice, but iteration relies on unquoted splitting.
- Actionable implementation instructions:
  1. Replace splitting loop with newline-safe iteration (for example, `while IFS= read -r fname; do ... done`).
  2. Ensure empty-line handling is explicit and harmless.
  3. Keep behavior identical for current valid names.
  4. Add/update tests to confirm normal family keys still validate.

### L2. Exit code `2` contract should be documented at module level
- Location:
  - `lib/reasoning.sh` (module header vs function-level docs)
- Problem summary:
  `reasoning_prompt_effort` documents exit code semantics at function level, but module-level docs do not summarize this contract for external callers.
- Actionable implementation instructions:
  1. Add a concise module-header note describing `reasoning_prompt_effort` return codes:
     - `0` success,
     - `1` EOF/cancel,
     - `2` retry exhaustion.
  2. Mention that callers must distinguish `1` and `2` if they need different control flow (as `deploy.sh` does).
  3. Keep docs synchronized when contracts change.

### L3. Snapshot validation is intentionally all-or-nothing
- Location:
  - `lib/reasoning.sh` (`_reasoning_load_snapshot` family validation policy)
- Problem summary:
  A single malformed family disables the entire snapshot. This is conservative and acceptable for a small bundled snapshot, but should be explicit.
- Actionable implementation instructions:
  1. Keep all-or-nothing policy unless there is a deliberate product decision to support partial acceptance.
  2. Add an in-code comment stating the rationale:
     - safety over partial tolerance,
     - easier reasoning and deterministic fallback.
  3. Add/update one test that demonstrates this behavior:
     - one valid family + one malformed family => snapshot disabled globally.

---

## Observations (No Action Needed)
- `REASONING_MAX_PROMPT_ATTEMPTS=3` as module-scoped (not readonly/exported) is appropriate.
- Distinct exit codes (`2` exhaustion vs `1` EOF) are clean and caller handling in `deploy.sh` is correct.
- The test for valid choice after invalid input confirms retry-loop behavior, not only failure behavior.
- The malformed-snapshot fallback test provides strong end-to-end fallback coverage.

## Test Coverage Snapshot (As Reported)

| Suite | Count | Status |
|---|---:|---|
| `reasoning.bats` | 73 (was 65) | All pass |
| `deploy.bats` | 151 (was 147) | All pass |
| Affected suites | 0 failures | Pass |

---

## Additional Validation Criteria (Addendum)

Run from:
`cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/steady-hugging-karp`

1. Validate top-level object-key misclassification protection (`M1`):
   - Add a temporary snapshot fixture containing:
     - valid `families`,
     - extra top-level object key (for example `metadata`).
   - Expect:
     - loader does not treat `metadata` as a family,
     - snapshot remains enabled when family blocks are valid.
2. Validate source-time warning behavior is explicitly documented (`M2`):
   - Check module header comments in `lib/reasoning.sh`.
   - Expect:
     - source-time load behavior is documented,
     - warning/fallback behavior is described.
3. Validate robust family iteration (`L1`):
   - Inspect loop implementation (no unquoted `for fname in $family_names`).
   - Expect:
     - newline-safe iteration approach,
     - behavior unchanged for current snapshot.
4. Validate module-level exit-code contract docs (`L2`):
   - Confirm module header includes `0/1/2` semantics.
   - Confirm function-level docs are consistent.
5. Validate all-or-nothing policy coverage (`L3`):
   - Run a test with one valid and one malformed family.
   - Expect:
     - snapshot disabled globally,
     - conservative defaults used.
6. Run affected test suites:
   - `bats tests/reasoning.bats tests/deploy.bats tests/install.bats`
   - Expect: all pass with no regressions.
