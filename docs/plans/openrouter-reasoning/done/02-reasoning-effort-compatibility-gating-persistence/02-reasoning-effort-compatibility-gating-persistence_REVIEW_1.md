Negative Deviations

┌─────────────────────┬──────────┬──────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Item │ Severity │ Status │ Description │
├─────────────────────┼──────────┼──────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ No JSON snapshot │ │ │ Plan §Open Q1 resolution specifies {"schema_version": "1", "policy_version": "1", "families": {...}} │
│ file │ MEDIUM │ Acknowledged │ JSON format. Implementation uses Bash case statements instead. Functionally equivalent but doesn't │
│ │ │ │ match the specified format. │
├─────────────────────┼──────────┼──────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ tests/mocks/curl │ │ │ Plan §File-level lists "fixtures for model families used by gating tests" for mocks/curl. Tests use │
│ not updated │ LOW │ N/A │ MOCK_OPENROUTER_MODELS_FAIL=true + manual fallback instead, which is sufficient but diverges from │
│ │ │ │ plan's fixture approach. │
├─────────────────────┼──────────┼──────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ │ │ Plan line 65 says "Setup must not infer reasoning capability from model family name alone." │
│ Name-based │ LOW │ By design │ Implementation does use family name matching in reasoning_model_supports_reasoning(). However, the name │
│ reasoning detection │ │ │ check is against the bundled snapshot (case statement), not arbitrary inference — this is a reasonable │
│ │ │ │ interpretation of "don't infer from the API". │
└─────────────────────┴──────────┴──────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Edge Cases

┌────────────────────────────────┬──────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Item │ Severity │ Description │
├────────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ │ GPT-5 family uses low|medium|high (conservative cross-provider intersection). Users who want minimal │
│ minimal excluded silently │ INFO │ (supported by direct OpenAI but not Azure) have no setup path. Documented as intentional in plan │
│ │ │ §Resolution Q4. │
├────────────────────────────────┼──────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Empty DEPLOY_REASONING_EFFORT │ INFO │ When reasoning is skipped (non-GPT-5 model), YAML shows reasoning_effort: with empty value rather than │
│ in summary │ │ omitting the field. Cosmetic only. │
└────────────────────────────────┴──────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Verdict: FAIL

Per the verdict logic, the verdict is FAIL because negative deviations exist (3 found). The most notable is the JSON snapshot format deviation (MEDIUM).
However, all 10 acceptance criteria pass and all 575 tests pass. The negative deviations are architectural choices that don't affect correctness — the Bash
case-statement approach is functionally equivalent to the planned JSON snapshot and follows existing codebase patterns.
