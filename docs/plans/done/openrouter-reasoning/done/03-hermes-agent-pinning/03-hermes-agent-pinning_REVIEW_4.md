1. LOW: Override-path test does not enforce exact stdout contract
   In tests/deploy.bats:1707, `assert_output --partial "custom-branch"` permits extra stdout content.
   The test comment states stdout should contain only the resolved ref value, so the assertion is weaker than the documented contract.

   Actionable fix:
   1. Edit the test block named `deploy_resolve_hermes_ref warns on non-default override (stderr)`.
   2. Replace partial stdout assertion with an exact stdout assertion:
      - from: `assert_output --partial "custom-branch"`
      - to: `assert_output "custom-branch"` (or exact value variable if made dynamic).
   3. Keep the existing guard that warning text must not appear on stdout:
      - `refute_output --partial "non-reproducible build"`
   4. Keep stderr assertions proving warning routing:
      - `[[ "$stderr" == *"non-reproducible build"* ]]`
      - `[[ "$stderr" == *"custom-branch"* ]]`
   5. If trailing newline behavior makes exact string brittle in your Bats version, normalize comparison explicitly (for example compare a trimmed/normalized variable), but still enforce equality semantics, not substring semantics.
   6. Update the nearby comment if needed so code and comment describe the same strictness level.

2. LOW: Default-path stderr emptiness is documented but not strictly asserted
   In tests/deploy.bats:1715 and tests/deploy.bats:1726, the comment claims stderr must be empty, but assertion only checks absence of one phrase.

   Actionable fix:
   1. Edit the test block named `deploy_resolve_hermes_ref default path does not emit warning`.
   2. Keep the existing success + stdout shape check:
      - `assert_success`
      - `[[ "$output" =~ ^[0-9a-f]{40}$ ]]`
   3. Add strict empty stderr assertion:
      - `[[ -z "$stderr" ]]`
   4. Retain or remove the current phrase-specific stderr check based on preference:
      - If retaining, keep it as a secondary guard.
      - If removing, strict empty stderr already subsumes it.
   5. Ensure the test comment and assertions are fully aligned:
      - either assert empty stderr and keep “stderr must be empty”
      - or relax comment language if strict emptiness is intentionally not required.
   6. Do not weaken this to substring-only checks; the goal is to lock the stream contract and catch unrelated stderr regressions.

Validation criteria (implementer sign-off checklist):
1. Finding 1 resolution (override-path exact stdout):
   1. `deploy_resolve_hermes_ref warns on non-default override (stderr)` contains exact stdout assertion (not `--partial`) for the resolved ref.
   2. The same test still asserts warning text is absent from stdout.
   3. The same test still asserts warning text is present on stderr.
   4. The same test still asserts override ref value appears in stderr warning context.
   5. No new logic in this test reintroduces merged-stream capture (`2>&1`) inside the command body.
2. Finding 2 resolution (default-path strict stderr):
   1. `deploy_resolve_hermes_ref default path does not emit warning` includes strict emptiness assertion for `$stderr` (`[[ -z "$stderr" ]]`).
   2. The test continues to check success return code.
   3. The test continues to validate default ref shape (40-char lowercase hex).
   4. Comment text in the test matches assertion strength exactly.
3. Cross-test consistency:
   1. Both warning-path and default-path tests use `run --separate-stderr`.
   2. Neither test uses inline stream merging (`2>&1`) in the command under test.
   3. Both tests continue to source the same modules (`lib/ui.sh`, `lib/deploy.sh`) to preserve execution context.
4. Scope and safety:
   1. Changes are limited to test assertions/comments (no production code changes required for these findings).
   2. No unrelated tests or helper behavior are modified.
   3. Existing guarantees from prior review rounds remain intact:
      - default ref remains pinned SHA contract
      - override path remains explicit and warns as non-reproducible
5. Reviewer-verifiable evidence:
   1. Diff clearly shows `--partial` to exact assertion change for override stdout.
   2. Diff clearly shows strict empty stderr assertion added for default path.
   3. Final notes summarize that stream contract is now strictly enforced on both paths:
      - override: stdout exact ref, warning on stderr
      - default: stdout pinned ref, stderr empty
