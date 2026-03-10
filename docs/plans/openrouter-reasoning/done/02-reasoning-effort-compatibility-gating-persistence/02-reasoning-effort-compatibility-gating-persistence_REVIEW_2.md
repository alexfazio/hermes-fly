1. High: Installed releases miss data/reasoning-snapshot.json, so reasoning gating is effectively disabled outside a source checkout.
   install_files:174 copies only hermes-fly, lib/, and templates/ (no data/).
   reasoning snapshot path:34 expects ../data/reasoning-snapshot.json; when missing, \_reasoning_load_snapshot:50 clears data, and
   reasoning_model_supports_reasoning:193 always returns false.
   Result: deploy reasoning prompt path:847 is skipped for installed users.
   I reproduced this by calling install_files into a temp dir; data/reasoning-snapshot.json was missing.
2. Medium: Invalid reasoning menu input is silently converted to default effort instead of re-prompting or failing.
   reasoning_prompt_effort:255 returns failure on invalid choice, but deploy_collect_llm_config:850 treats any failure as “cancel/EOF” and force-sets default.
   In practice, entering 99 at the effort prompt still completes with DEPLOY_REASONING_EFFORT=medium.

3. reasoning_prompt_effort doesn't retry on invalid input
   lib/reasoning.sh:255 — If the user types 99, the function returns 1 immediately. Every other interactive prompt in the codebase (e.g., ui_select,
   openrouter_build_model_menu) loops on invalid input. The deploy.sh caller silently falls back to the default, so the user gets no feedback that their choice
   was ignored — they just see "medium" in the summary.

Suggestion: Loop with a max-attempt guard (consistent with openrouter_manual_fallback), or at minimum print a message before falling back in
deploy_collect_llm_config.

1. sed-based JSON block extraction is fragile to format changes
   lib/reasoning.sh:104 — sed -n "/\"${family}\"/,/}/p" assumes each family block ends at the first }. If someone later adds a nested object inside a family
   (e.g., "constraints": {}), the sed would terminate early. The current snapshot is simple enough that this works, but it's a latent issue as the snapshot
   grows.

Suggestion: Add a comment to data/reasoning-snapshot.json or lib/reasoning.sh documenting the flat-structure constraint that the parser depends on. Or use the
existing tr -d '\n' + grep -oE pattern from fly-helpers.sh which is less format-dependent.

1. Adding new reasoning model families requires TWO changes
   reasoning_normalize_family() uses a hardcoded case statement (line 79), AND the snapshot needs a new entry. If someone adds a family to the snapshot but
   forgets the case pattern (or vice versa), things silently fail. This couples the snapshot to the code in a way the PR description ("runtime lookups read from
   the parsed JSON, not hardcoded case statements") somewhat understates.

Suggestion: Document this dual-update requirement. Consider adding a comment at the top of reasoning_normalize_family listing which families it handles and
pointing to the snapshot.

LOW

1. No integration test for non-default effort selection through deploy flow
   The deploy.bats test for AC-01 sends \n (empty line = accept default). There's no integration test verifying that selecting "1" (low) or "3" (high) through
   deploy_collect_llm_config propagates correctly to DEPLOY_REASONING_EFFORT. The unit tests in reasoning.bats cover this, but an integration gap exists.

2. Duplicate module guard test
   reasoning.bats:144 and scaffold.bats:233 both test lib/reasoning.sh exits 1 when executed directly. Intentional (different test scopes) but redundant.

3. deploy_provision_resources test doesn't assert the secret was actually received
   deploy.bats test at line ~1376 ("includes HERMES_REASONING_EFFORT in secrets") mocks fly_set_secrets and asserts success but doesn't check the captured
   secrets contain the effort. The next test (line ~1393) does check the payload — so the first test is effectively a weaker duplicate.

INFO

1. Snapshot scope is GPT-5-only
   Only GPT-5 and GPT-5-pro families are in the snapshot. Other models with reasoning capabilities (DeepSeek-R1, future Claude reasoning modes) would need
   snapshot updates. This is appropriate for the scope of the PR but worth noting for future work.

2. YAML indentation is correct
   The reasoning_effort field in the YAML summary sits under llm: at the right indent level (2 spaces). The { cat <<EOF ; if; cat <<EOF; } > file refactoring in
   deploy_write_summary is clean.
