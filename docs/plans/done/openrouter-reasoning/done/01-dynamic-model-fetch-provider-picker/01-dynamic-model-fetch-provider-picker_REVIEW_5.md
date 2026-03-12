• Findings

1. High: EOF is handled in openrouter_manual_fallback, but the caller still treats fallback failure as success and continues with an
   empty model.
   openrouter_manual_fallback now correctly returns non-zero on EOF (lib/openrouter.sh:333, lib/openrouter.sh:335).
   But openrouter_setup_with_models ignores that return code in all fallback branches and always return 0 (lib/openrouter.sh:367, lib/
   openrouter.sh:372, lib/openrouter.sh:378, lib/openrouter.sh:389, lib/openrouter.sh:398, lib/openrouter.sh:405).
   That propagates as empty DEPLOY_MODEL via command substitution (lib/deploy.sh:854, lib/deploy.sh:856) and then sets LLM_MODEL= in
   secrets (lib/deploy.sh:1051).
   I reproduced this: deploy_collect_llm_config exited 0 with MODEL='' when fetch failed and stdin ended.
2. Medium: the new EOF regression test does not assert success/failure and will always pass.
   The test runs timeout ... || true and contains no assertion afterward, so it cannot fail even if behavior regresses.
   Ref: tests/openrouter.bats:553.

CRITICAL: 9 deploy.bats tests broken

The PR replaced deploy_collect_model's old static-list + jq implementation with openrouter_setup_with_models, but did not update
tests/deploy.bats. These 9 tests exercise the old behavior:

┌───────────────────────────────────────────────────────────────────┬──────┬──────────────────────────────────────────────────────┐
│ Test │ Line │ Issue │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_llm_config stores API key and default model │ 371 │ Expects MODEL=anthropic/claude-sonnet from static │
│ │ │ list │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_llm_config OpenRouter shows model table │ 409 │ Expects "Select model" / "Claude" from old static │
│ │ │ table │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_llm_config OpenRouter model choice 1 picks default │ 417 │ Expects MODEL=anthropic/claude-sonnet │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_llm_config re-prompts on invalid model choice │ 1034 │ Expects old static list re-prompt behavior │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_llm_config model choice 1 yields OpenRouter Sonnet │ 1041 │ Expects MODEL=anthropic/claude-sonnet-4 │
│ 4 ID │ │ │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_llm_config model choice 2 yields OpenRouter Haiku │ 1047 │ Expects MODEL=anthropic/claude-haiku-4.5 │
│ 4.5 ID │ │ │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_model shows models grouped by provider with jq │ 1270 │ Old API signature (deploy_collect_model │
│ │ │ MODEL_RESULT) │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_model falls back to static list without jq │ 1278 │ Expects old static list fallback │
├───────────────────────────────────────────────────────────────────┼──────┼──────────────────────────────────────────────────────┤
│ deploy_collect_model Other accepts manual model ID │ 1287 │ Expects old "Other" option │
└───────────────────────────────────────────────────────────────────┴──────┴──────────────────────────────────────────────────────┘

All 9 tests use the old deploy_collect_model interface (1 arg: RESULT_VAR) vs the new interface (2 args: API_KEY RESULT_VAR) and
expect the old static model list behavior. They also set MOCK_OPENROUTER_MODELS_FAIL=true expecting the old jq-dependent fallback, not
the new openrouter_setup_with_models flow.

Fix: Update tests/deploy.bats to:

- Source lib/openrouter.sh in the bash one-liners
- Use the new deploy_collect_model API_KEY RESULT_VAR signature
- Mock ui_select to simulate provider + model selection
- Or delete these tests and rely on openrouter.bats for model selection coverage, keeping only deploy_collect_llm_config tests that
  verify the integration wiring

Remaining Minor Issues

┌──────────┬───────────────────────────────────────────────────────┬─────────────────────────┐
│ Category │ Finding │ Status │
├──────────┼───────────────────────────────────────────────────────┼─────────────────────────┤
│ MINOR │ Two weak [[-n "$result"]] assertions in tests 14-15 │ Unchanged from REVIEW_3 │
├──────────┼───────────────────────────────────────────────────────┼─────────────────────────┤
│ MINOR │ grep -A 3 fragile JSON parsing │ Acceptable deferral │
└──────────┴───────────────────────────────────────────────────────┴─────────────────────────┘
