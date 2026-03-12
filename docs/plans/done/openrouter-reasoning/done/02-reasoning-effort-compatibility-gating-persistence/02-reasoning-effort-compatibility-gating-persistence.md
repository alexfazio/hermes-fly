# PR 2 Plan: Reasoning Effort UX + Compatibility Gating + Persistence

Date: 2026-03-10
Scope: `hermes-fly` repo implementation with explicit Hermes Agent upstream dependencies
Status: Ready for implementation

## Problem

The confirmed production failure was not model alias rejection; it was an invalid `reasoning.effort` value for the selected model path. Setup must let users choose reasoning effort safely, block known-invalid combinations, and persist the chosen value in a path Hermes Agent actually reads.

## Confirmed baseline

From the source investigation (`openrouter-gpt5-mini-reasoning-triage-20260309.md`):

- Confirmed failing pattern:
  - deployed runtime sent `reasoning.effort=xhigh`
  - provider rejected it for GPT-5 mini
  - supported values were `minimal|low|medium|high`
  - provider metadata in failing error path was `Azure`
  - failing snapshot example in investigation: `gpt-5-mini-2025-08-07`
- Confirmed live app state on 2026-03-09:
  - `/root/.hermes/.env` had `LLM_MODEL=openai/gpt-5-mini`
  - `/root/.hermes/.env` did not have `HERMES_REASONING_EFFORT`
  - `/root/.hermes/config.yaml` had `reasoning_effort: "xhigh"`
- Hermes Agent behavior (confirmed in source doc references):
  - accepted values include `xhigh|high|medium|low|minimal|none`
  - reads env `HERMES_REASONING_EFFORT` and config `agent.reasoning_effort` in `~/.hermes/config.yaml`
  - current upstream `main` default is `medium`
  - upstream config example includes `agent.reasoning_effort: "medium"`
- Decision-log root-cause finding:
  - failing commit `caab1cf4536f79f5b74552f47360e178e6d28ff9` defaulted reasoning to `xhigh` when not explicitly set
  - function-level source was `_load_reasoning_config()` in that commit path, where absence of explicit value could resolve to `xhigh`
- Provider docs mismatch confirmed:
  - OpenRouter reasoning docs discuss GPT-5-series reasoning broadly (including `xhigh`)
  - OpenAI/Azure GPT-5 mini docs constrain to `minimal|low|medium|high`
  - OpenRouter `/models` (`/api/v1/models`) exposes parameter names (for example `supported_parameters`, `default_parameters`), not model-specific effort-enum safety
- `hermes-fly` itself has no literal `xhigh`; failure came from runtime config/default behavior.
- In the inspected failing app, runtime source detail was:
  - `agent.reasoning_effort: "xhigh"` in deployed config
  - not `HERMES_REASONING_EFFORT` from runtime env

## Live OpenRouter API snapshot (queried 2026-03-10)

Live calls run during this planning session:

- `GET https://openrouter.ai/api/v1/models`
- `GET https://openrouter.ai/api/v1/models/openai/gpt-5-mini/endpoints`
- `GET https://openrouter.ai/api/v1/models/openai/gpt-5-chat/endpoints`
- `GET https://openrouter.ai/api/v1/models/openai/gpt-5.4/endpoints`
- `GET https://openrouter.ai/api/v1/models/anthropic/claude-sonnet-4/endpoints`
- `GET https://openrouter.ai/api/v1/models/openai/gpt-oss-120b/endpoints`

Observed facts from those responses:

- `/models` returned `346` models.
- `/models` currently includes `21` IDs matching `openai/gpt-5*`; `17` advertise `reasoning` support and `4` do not (`openai/gpt-5-chat`, `openai/gpt-5.1-chat`, `openai/gpt-5.2-chat`, `openai/gpt-5.3-chat`).
- `openai/gpt-5-mini` currently advertises `supported_parameters` including `reasoning|include_reasoning`.
- `openai/gpt-5-chat` currently advertises `supported_parameters` as `max_tokens|response_format|seed|structured_outputs` (no `reasoning`).
- `/models/openai/gpt-5-mini/endpoints` currently returns two provider routes (`OpenAI`, `Azure`), both listing `reasoning` and `include_reasoning`.
- Endpoint metadata exposes `supported_parameters` but no effort-enum field (no API field listing allowed values like `minimal|low|medium|high|xhigh|none`).
- Parameter naming is heterogeneous across model/provider routes: many endpoints expose `reasoning`, while some endpoints also expose `reasoning_effort` (observed on specific `openai/gpt-oss-120b` provider routes).

Execution implications for this PR:

1. Setup must not infer reasoning capability from model family name alone.
2. Gating logic should treat both `reasoning` and `reasoning_effort` as capability signals, then apply snapshot allowlist for effort enums.
3. Chat aliases lacking reasoning support should bypass first-run reasoning-effort choice and stay on conservative defaults.
4. `/endpoints` is useful for route presence and parameter-name detection, but still cannot replace a Hermes-owned effort-compatibility snapshot.

## Product decisions carried into this PR

1. Setup asks for reasoning effort after model selection.
2. Choice is constrained by compatibility policy, not free-form input.
3. Conservative defaults when compatibility is unknown:
- default to `medium`
- hide advanced options or show conservative subset only
4. `none` is advanced-only and not shown in first-run wizard.
5. Persistence uses `HERMES_REASONING_EFFORT` env var as primary path.
6. `config.yaml` is not patched by default from `hermes-fly`; keep it as runtime/user fallback.

## Scope in this PR

1. Add reasoning-effort step to setup flow.
2. Implement setup-time compatibility lookup and option gating.
3. Block known-invalid combinations at selection time (example: GPT-5 mini + `xhigh`).
4. Persist selected value into Fly secrets as `HERMES_REASONING_EFFORT`.
5. Bridge that env var into runtime env in `templates/entrypoint.sh`.
6. Show effective selected reasoning effort in deploy summary.
7. Ship full regression tests in this repo.

## Out of scope (explicitly not in this PR)

- Runtime clamping and one-retry `unsupported_value` fallback in Hermes Agent code.
- Canonical compatibility-registry authoring inside Hermes Agent.
- Release-channel policy and drift detection.

## What remains unconfirmed (carried forward from source analysis)

1. Full code-path provenance for how `reasoning_effort: "xhigh"` was first written in every historical failing deploy (resolved for one inspected commit, not exhaustively for all timelines).
2. Whether OpenRouter metadata can ever provide complete enum-level compatibility for all model/provider paths.
   - **Finding** [HIGH]: OpenRouter `/models` returns `supported_parameters` arrays with reasoning-style signals (`reasoning` on GPT-5 family snapshots, `reasoning_effort` on some other families) as boolean-level present/absent indicators, not an enum of valid effort values. The `/endpoints` API provides per-provider parameter support but also lacks effort-value enumeration. OpenRouter silently maps unsupported effort levels to the nearest supported level rather than rejecting. ([OpenRouter Models API](https://openrouter.ai/docs/api/api-reference/models/get-models), [OpenRouter Endpoints API](https://openrouter.ai/docs/api/api-reference/endpoints/list-endpoints)). **Recommendation**: Confirm the plan's bundled snapshot approach; use `/endpoints` API as supplementary per-provider detection signal.
3. Whether compatibility varies by effective backend route under OpenRouter (`OpenAI-served`, `Azure-served`, others) for the same logical model alias.
   - **Finding** [HIGH]: Yes, compatibility varies by route. OpenRouter's `/endpoints` API returns per-provider `supported_parameters` arrays that can differ for the same model. Azure OpenAI documents `low|medium|high` (plus `minimal`) for GPT-5 reasoning models. The `providers.require_parameters: true` flag forces routing only to providers supporting all requested parameters. ([OpenRouter Provider Routing](https://openrouter.ai/docs/guides/routing/provider-selection), [Azure Reasoning Models](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning)). **Recommendation**: Use `require_parameters: true` when reasoning_effort is set; make bundled snapshot provider-aware for known Azure/OpenAI divergences.
4. How much compatibility behavior can vary by Hermes Agent commit when deploy inputs track moving upstream refs.
   - **Finding** [MEDIUM]: Materially -- confirmed by the caab1cf commit defaulting to `xhigh` vs current `main` defaulting to `medium`. LiteLLM uses `drop_params=True` and `supports_reasoning()` as patterns for proxy-layer compatibility decoupling. ([LiteLLM Reasoning Content](https://docs.litellm.ai/docs/reasoning_content)). **Recommendation**: Pin Hermes Agent to versioned releases; the `HERMES_REASONING_EFFORT` env var approach correctly decouples setup-time choice from runtime defaults.

## Scope status carried forward

This split PR plan preserves the original scope framing:

- fully covers:
  - confirmed GPT-5 mini failure class
  - `hermes-fly` setup reasoning-choice/product gap
  - compatibility-gated setup behavior and persistence path in this repo
- does not yet fully cover:
  - exhaustive all-model/all-provider compatibility matrix
  - exhaustive proof for every historical `xhigh` write path beyond resolved inspected commit evidence
  - complete backend-route variance matrix under OpenRouter
- practical interpretation:
  - one concrete failure was deeply investigated
  - strategy is generalized to the broader class
  - unresolved points remain explicitly open pending proof

## Compatibility policy model for setup

### Initial policy requirements

- unknown model family -> `medium`
- `xhigh` only for explicit allowlist families
- GPT-5 mini must not expose `xhigh`
- never auto-surface `none` in first-run menu

### Policy source-of-truth direction

Long-term decision retained from source plan:

- Hermes Agent owns canonical machine-readable compatibility registry
- `hermes-fly` consumes a versioned exported snapshot for setup gating

Short-term implementation in this PR (repo-local):

- consume a bundled versioned snapshot artifact suitable for deterministic setup behavior
- do not infer effort enum safety directly from OpenRouter `/models`

### Cross-family notes from resolved decision log

These details remain relevant when defining first-release policy data:

- GPT-5 family is not uniform:
  - `openai/gpt-5-mini` observed limits: `minimal|low|medium|high`
  - `openai/gpt-5` observed limits: `minimal|low|medium|high` in referenced docs
  - `openai/gpt-5-nano` should remain explicit in registry modeling, not assumed identical by name similarity alone
  - GPT-5/GPT-5-mini observed limits: `minimal|low|medium|high`
  - newer GPT-5.* variants may include broader tiers depending on model/provider
- Anthropic reasoning behavior uses different thinking controls (not a direct `reasoning.effort` match).
- Google Gemini thinking controls use provider-specific levels (`minimal|low|medium|high` via `thinkingLevel`, variants by model generation).
- Compatibility policy must remain family-aware and provider-aware, with conservative fallback for unknowns.

## Detailed setup behavior

1. Model selected (from OpenRouter picker path).
2. Normalize model to family key.
3. Resolve allowed efforts from compatibility snapshot.
4. Render prompt with only allowed first-run options.
5. Default selection to `medium` when present; otherwise safest allowed value.
6. On unknown family:
- default to `medium`
- optionally hide menu and continue with `medium`
7. Persist selected effort to deploy state.
8. Export to Fly secrets as `HERMES_REASONING_EFFORT`.
9. Include effective effort in deploy summary output.

## File-level implementation plan

- `lib/deploy.sh`
  - add reasoning-effort prompt step after model selection
  - add compatibility lookup/validation helpers
  - write `HERMES_REASONING_EFFORT=${DEPLOY_REASONING_EFFORT}` in secrets flow
  - include effective reasoning effort in summary YAML/markdown
- `templates/entrypoint.sh`
  - add `HERMES_REASONING_EFFORT` to env bridge loop into `/root/.hermes/.env`
  - avoid direct YAML patching for reasoning by default
- `tests/deploy.bats`
  - selected model -> expected allowed options
  - risky model excludes `xhigh`
  - unknown model conservative fallback
  - summary contains effective effort
  - invalid combination blocked at selection time
- `tests/scaffold.bats`
  - runtime env bridge includes `HERMES_REASONING_EFFORT`
- `tests/mocks/curl`
  - fixtures for model families used by gating tests

## Upstream dependency notes (Hermes Agent)

These are required for end-to-end resilience but are dependency-only for this repo PR:

1. Pre-send clamp by model family:
- downgrade ladder `xhigh -> high -> medium -> low -> minimal`
- unknown family clamp directly to `medium`
- never auto-downgrade to `none`

2. Recovery for provider 400 `unsupported_value`:
- retry once with downgraded effort
- log downgrade
- no retry loops
- if retry fails again, surface error

3. Runtime defaults:
- unknown family remains conservative
- no auto-upgrade to `xhigh` without allowlist

Hermes Agent test expectations (dependency-only, from source Workstream 4):

- GPT-5 mini rejects `xhigh` path but succeeds with downgraded effort.
- known allowlisted model keeps high-effort tier where explicitly allowed.
- unknown family defaults to `medium`.
- provider 400 retry path runs once only.
- downgrade ladder does not auto-drop to `none`.

## Test plan for this PR

Deterministic suites to run after implementation:

1. `uv run bats tests/deploy.bats`
Pass condition: exit code `0`.
2. `uv run bats tests/scaffold.bats`
Pass condition: exit code `0`.
3. `uv run bats tests/integration.bats`
Pass condition: exit code `0` or explicitly skipped in CI with documented skip reason.

Required new/updated assertions in those suites:

1. Reasoning-gated menu assertions for OpenRouter models, including explicit negative checks for disallowed values.
2. Persistence assertions for Fly secret composition and deploy summary fields.
3. Runtime env-bridge assertions proving `HERMES_REASONING_EFFORT` reaches `/root/.hermes/.env`.
4. Regression assertions for non-OpenRouter flow stability.

## Risk assessment

- Risk: policy snapshot drifts from Hermes Agent runtime behavior.
- Mitigation: version policy artifact and record version in deploy outputs.

- Risk: users expect `none` in setup.
- Mitigation: document as advanced-only path and keep first-run UI simple.

- Risk: setup validation gives false confidence if provider behavior changes.
- Mitigation: keep upstream runtime clamp/retry as explicit dependency.

## Resolved decision items captured here

- `/models` metadata is insufficient for effort enum safety by itself.
- Persistence should use env var first (`HERMES_REASONING_EFFORT`).
- `none` should be advanced-only in first-run UX.
- Compatibility registry ownership belongs to Hermes Agent long term.

## Open questions resolved for first-ship scope (2026-03-10)

1. Exact registry export format from Hermes Agent to `hermes-fly`.
   - **Finding** [MEDIUM]: Open-source registries (RubyLLM, llm-registry, LiteLLM) use JSON/YAML with family-keyed objects containing capability arrays. A minimal first-ship format: `{"schema_version": "1", "families": {"gpt-5-mini": {"allowed_efforts": [...], "default": "medium"}}}`. ([llm-registry](https://github.com/yamanahlawat/llm-registry), [LiteLLM model config](https://docs.litellm.ai/docs/reasoning_content)). **Recommendation**: Use minimal family-keyed JSON with `allowed_efforts` arrays and `schema_version` field; defer full alignment with Hermes Agent canonical registry.
   - **Resolution**: Adopt a minimal bundled JSON snapshot in `hermes-fly` for this PR scope:
     - top-level required keys: `schema_version`, `policy_version`, `families`
     - per-family required keys: `allowed_efforts`, `default`
     - unknown family behavior remains hard-conservative (`medium`)
2. Exact first-release family list and provider-path overrides beyond confirmed GPT-5 constraints.
   - **Finding** [HIGH]: Confirmed matrix -- GPT-5/mini/nano: `minimal|low|medium|high`; GPT-5.1: `none|low|medium|high`; GPT-5.2+: all six levels including `xhigh`; GPT-5-pro: `high` only; GPT-5-codex: no `minimal`. Azure constrains to `low|medium|high` (plus `minimal` for GPT-5). Anthropic/Gemini use different mechanisms entirely. ([OpenAI Reasoning Guide](https://developers.openai.com/api/docs/guides/reasoning/), [Azure Reasoning Models](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning), [OpenAI GPT-5.4 Guide](https://developers.openai.com/api/docs/guides/latest-model/)). **Recommendation**: Ship with GPT-5 family (minimal|low|medium|high), GPT-5.1 (none|low|medium|high), GPT-5.2+ (all six), GPT-5-pro (high only); default unknowns to medium.
   - **Resolution**: First ship uses a conservative OpenRouter-targeted family policy:
     - `openai/gpt-5*` (including mini/nano/5.1/5.2/codex aliases): `low|medium|high`, default `medium`
     - `openai/gpt-5-pro`: `high` only, default `high`
     - all other/unknown families: conservative fallback `medium`
     - `xhigh` and `none` remain excluded from first-run setup UX
3. Whether setup should treat some provider routes under one model alias as distinct compatibility targets from day one.
   - **Finding** [HIGH]: Provider routes ARE distinct at the API level -- OpenRouter `/endpoints` returns per-provider `supported_parameters`. Azure GPT-5 supports `low|medium|high` vs direct OpenAI `minimal|low|medium|high`. OpenRouter silently maps unsupported levels to nearest supported. `providers.require_parameters: true` forces compatible routing. ([OpenRouter Endpoints API](https://openrouter.ai/docs/api/api-reference/endpoints/list-endpoints), [Azure Reasoning](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning)). **Recommendation**: Do NOT expose provider-route distinction in setup UI; use most conservative intersection per family in snapshot; set `require_parameters: true` at runtime.
   - **Resolution**: Do not expose provider-route distinctions in setup UI for first ship. Use family-level conservative intersection in setup gating and keep provider-route awareness as internal policy logic only.
4. Whether family-level policy should encode explicit OpenAI-served vs Azure-served overrides at first ship.
   - **Finding** [HIGH]: Azure GPT-5 documents `low|medium|high` (plus `minimal` for some GPT-5 models); direct OpenAI supports `minimal|low|medium|high`. Key divergence is `minimal`. Safe intersection through OpenRouter is `low|medium|high`. ([Azure Reasoning Models](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning), [OpenAI Reasoning Guide](https://developers.openai.com/api/docs/guides/reasoning/)). **Recommendation**: Do NOT encode per-provider overrides at first ship; use conservative intersection (`low|medium|high` for GPT-5 via OpenRouter) to avoid Azure `minimal` edge case.
   - **Resolution**: No explicit OpenAI-vs-Azure split in the first shipped snapshot. Apply conservative cross-route intersection now; defer provider-specific overrides to a later registry version once runtime/provider telemetry is in place.

## Acceptance criteria

The following criteria are pass/fail and must be demonstrably verifiable from test output or deterministic file checks.

1. `AC-01` Model-aware gating for known restricted model.
Verification:
Run test scenario with OpenRouter model `openai/gpt-5-mini`.
Pass when:
The displayed/returned allowed first-run options are exactly `low|medium|high`; `xhigh` and `none` are not offered.

2. `AC-02` Deterministic default selection behavior.
Verification:
Run test scenario where user accepts default effort for a reasoning-capable OpenRouter model.
Pass when:
Resolved value is `medium` and persisted in deploy state as `DEPLOY_REASONING_EFFORT=medium`.

3. `AC-03` Unknown-family conservative fallback.
Verification:
Run test scenario with an unknown or unlisted model family through manual model path.
Pass when:
Resolved effort is `medium`, advanced efforts are not exposed, and flow continues without crash.

4. `AC-04` Known-invalid combination is rejected pre-deploy.
Verification:
Run test scenario attempting `openai/gpt-5-mini` with invalid effort (`xhigh`) via interactive/manual selection path.
Pass when:
Selection is rejected before deploy execution and user is reprompted or forced onto valid set.

5. `AC-05` Persistence through Fly secrets is explicit.
Verification:
Inspect captured deploy command in tests and source.
Pass when:
`fly secrets set` payload includes `HERMES_REASONING_EFFORT=<selected_value>` alongside existing LLM/OpenRouter secrets.

6. `AC-06` Runtime env bridge carries reasoning value.
Verification:
Run scaffold/entrypoint test with `HERMES_REASONING_EFFORT` set.
Pass when:
Generated `/root/.hermes/.env` contains `HERMES_REASONING_EFFORT=<selected_value>`.

7. `AC-07` Default flow does not patch `config.yaml` for reasoning.
Verification:
Run deploy + scaffold path with reasoning value set and inspect side effects.
Pass when:
Reasoning persistence is via env bridge path only; no default sed/mutation step rewrites `agent.reasoning_effort` in `config.yaml`.

8. `AC-08` Deploy summary exposes effective reasoning effort.
Verification:
Inspect generated deploy summary artifacts (YAML/Markdown) in test run.
Pass when:
Each summary includes explicit reasoning field/value for the selected deployment.

9. `AC-09` Non-OpenRouter provider flow regression guard.
Verification:
Run existing non-OpenRouter deploy tests.
Pass when:
No reasoning-effort prompt/gating regression occurs for providers outside the OpenRouter path, and prior behavior remains intact.

10. `AC-10` Upstream dependency boundary remains explicit.
Verification:
Inspect plan/docs and PR notes.
Pass when:
Runtime clamp/retry behavior is still documented as Hermes Agent upstream dependency and not misrepresented as implemented in this repo PR.

## Bottom-line carry-forward

- this is not only a GPT-5 mini one-off
- dynamic `/models` discovery must not be treated as enum-level safety proof
- setup gating plus conservative defaults are required in `hermes-fly`
- runtime clamping/retry remains mandatory upstream in Hermes Agent
- previously open questions in this PR scope now have explicit first-ship resolutions

## Literal artifacts preserved from source

To keep exact source fidelity for implementation and grep-based traceability, these literals are intentionally retained:

- `gpt-5-mini`
- `reasoning_effort`
- `reasoning_effort: "medium"`
- `https://github.com/NousResearch/hermes-agent/blob/main/cli.py`
- `https://github.com/NousResearch/hermes-agent/blob/main/gateway/run.py`
- `https://github.com/NousResearch/hermes-agent/blob/main/run_agent.py`
- `https://github.com/NousResearch/hermes-agent/blob/main/cli-config.yaml.example`

## References

- `openrouter-gpt5-mini-reasoning-triage-20260309.md`
- [OpenRouter Models API (GET /models)](https://openrouter.ai/docs/api/api-reference/models/get-models)
- [OpenRouter List Endpoints API](https://openrouter.ai/docs/api/api-reference/endpoints/list-endpoints)
- [OpenRouter Reasoning Tokens Guide](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [OpenRouter Provider Routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [OpenRouter API Parameters Reference](https://openrouter.ai/docs/api/reference/parameters)
- [OpenAI Reasoning Models Guide](https://developers.openai.com/api/docs/guides/reasoning/)
- [OpenAI GPT-5 Model Page](https://developers.openai.com/api/docs/models/gpt-5)
- [OpenAI GPT-5.4 (Latest Model) Guide](https://developers.openai.com/api/docs/guides/latest-model/)
- [OpenAI GPT-5 model page](https://platform.openai.com/docs/models/gpt-5)
- [OpenAI GPT-5 mini model page](https://platform.openai.com/docs/models/gpt-5-mini)
- https://platform.openai.com/docs/models/gpt-5.2
- [Azure OpenAI Reasoning Models Documentation](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/reasoning)
- [OpenAI Community: Compatibility Matrix Request](https://community.openai.com/t/request-for-compatibility-matrix-reasoning-effort-sampling-parameters-across-gpt-5-series/1371738)
- [LiteLLM Reasoning Content Docs](https://docs.litellm.ai/docs/reasoning_content)
- [llm-registry (Open Source Model Capability Registry)](https://github.com/yamanahlawat/llm-registry)
- [RubyLLM Model Registry](https://rubyllm.com/models/)
- [VS Code xhigh reasoning effort issue](https://github.com/microsoft/vscode/issues/281371)
- [Anthropic Claude extended thinking docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking)
- [Anthropic Claude adaptive thinking docs](https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking)
- [Google Gemini Thinking API docs](https://ai.google.dev/gemini-api/docs/thinking)
- https://github.com/NousResearch/hermes-agent/blob/main/cli.py#L106-L120
- https://github.com/NousResearch/hermes-agent/blob/main/gateway/run.py#L360-L387
- https://github.com/NousResearch/hermes-agent/blob/main/run_agent.py#L2364-L2375
- https://github.com/NousResearch/hermes-agent/blob/main/cli-config.yaml.example#L345-L348
- https://github.com/NousResearch/hermes-agent/blob/main/scripts/install.sh#L786-L790
- https://raw.githubusercontent.com/NousResearch/hermes-agent/main/gateway/run.py
- https://raw.githubusercontent.com/NousResearch/hermes-agent/caab1cf4536f79f5b74552f47360e178e6d28ff9/gateway/run.py
- https://raw.githubusercontent.com/NousResearch/hermes-agent/main/cli-config.yaml.example
