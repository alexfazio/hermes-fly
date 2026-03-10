# PR 1 Plan: Dynamic OpenRouter Model Fetch + Provider-First Picker

Date: 2026-03-10
Scope: `hermes-fly` repo only
Status: Ready for implementation

## Problem

`hermes-fly deploy` currently validates an OpenRouter key and then shows a hardcoded static model table. That blocks broad model coverage and creates drift between setup UX and live provider availability.

This PR isolates one deliverable: dynamic model discovery and provider-first selection for OpenRouter, with deterministic behavior and manual fallback.

## Confirmed baseline

From the source investigation (`openrouter-gpt5-mini-reasoning-triage-20260309.md`):

- Incident context:
  - provider selected: OpenRouter
  - model selected: `openai/gpt-5-mini`
  - runtime error rejected `reasoning.effort=xhigh` (supported: `minimal|low|medium|high`)
- Current setup behavior in this repo:
  - `deploy_collect_llm_config()` uses an inline static model list
  - no live `/models` fetch exists
  - no provider grouping exists
  - there is a manual entry option
- Current persistence behavior in this repo:
  - stores `OPENROUTER_API_KEY`
  - stores `LLM_MODEL`
  - `templates/entrypoint.sh` bridges `LLM_MODEL` into `/root/.hermes/.env` and patches `config.yaml`
- Confirmed code refs:
  - `lib/deploy.sh:654-788` (`deploy_collect_llm_config` static table)
  - `lib/deploy.sh:817-868` (`deploy_collect_config` calling flow)
  - `lib/deploy.sh:945` and `lib/deploy.sh:1129` (secrets + summary paths)
  - `templates/entrypoint.sh:17-30` (env/config bridge)
- OpenRouter `/models` is useful for discovery, but not sufficient to infer allowed `reasoning.effort` enum values.

## Product decision carried into this PR

For OpenRouter setup UX:

- fetch `https://openrouter.ai/api/v1/models` only after API-key validation
- derive provider groups from model IDs (examples: `openai/...`, `anthropic/...`, `google/...`)
- prompt provider first, then model list within provider
- keep manual model-ID entry as escape hatch
- if `/models` fetch fails or yields no parseable IDs, warn and fall back to manual-only mode

## In scope (this PR)

1. Replace static OpenRouter model table with live `/models` fetch.
2. Parse and normalize fetched entries:
- ignore entries without parseable `id`
- deduplicate exact IDs
- derive provider prefix from model ID
- stable sort providers alphabetically
- stable sort models by display name, then exact ID
3. Add provider-first interactive selection.
4. Preserve manual model-ID path.
5. Add deterministic fallback mode when fetch is unavailable/empty.
6. Add tests and mocks for all branches above.

## Out of scope (deferred)

- Reasoning-effort compatibility gating and persistence.
- Runtime clamping/retry in Hermes Agent.
- Hermes Agent pinning policy.
- Deployment provenance manifests.
- Release channel and drift detection.

## Detailed behavior

### Setup flow for OpenRouter

1. Validate OpenRouter API key.
2. Call `GET https://openrouter.ai/api/v1/models` with `--max-time 30` and a loading animation during the fetch.
3. Cache the full JSON response in a temp file for the wizard's duration (cleaned up via `trap EXIT`).
4. Build candidate list by lazy-parsing the cached response with grep/sed:
- keep records with non-empty `id`
- derive provider = prefix before first `/` when present (split on first `/` only — preserve remainder verbatim, including any further slashes or colon suffixes)
- for IDs without `/`, provider group = `other`
- model IDs with colon suffixes (`:free`, `:nitro`, `:thinking`, `:extended`, `:floor`, `:exacto`) are kept as distinct full entries — the complete ID must be passed to the API verbatim
- the `openrouter/` prefix is a valid provider like any other — do not strip it
5. Deduplicate by exact `id`.
6. Prompt **provider menu** in three tiers:
   1. Curated common providers (in this order): `openai`, `anthropic`, `google`, `meta-llama`, `deepseek`, `mistralai`, `z-ai`, `minimax`, `qwen`
   2. "Other providers" — shows remaining providers alphabetically, excluding the common list
   3. "Enter model ID manually" — last option, skips model sub-menu entirely
7. Prompt **model menu** within the selected provider:
   - display uses the full `name` field as-is (e.g., "OpenAI: GPT-5.4 Pro")
   - show the top 15 models sorted by `created` timestamp (most recent first)
   - if the provider has more than 15 models, add a "Show all N models" option at the end
   - for providers with 15 or fewer models, show all directly
8. If fetch fails or resolves to 0 valid IDs:
- print explicit, non-technical warning explaining that model list could not be loaded
- provide step-by-step manual fallback instructions:
  1. direct the user to `https://openrouter.ai/models` to find and copy a model ID
  2. prompt for the model ID with input validation
- skip provider/model menus entirely

### Determinism requirements

- No random ordering in menus.
- Duplicate and malformed entries are ignored consistently.
- Same fixture input must produce identical menu ordering across runs.

### Safety and UX requirements

- This PR does not claim effort-level safety from `/models` metadata.
- No compatibility assumptions should be derived here beyond model discovery.
- Warnings must explain fallback clearly so users understand why manual mode appears.

## File-level implementation plan

- **`lib/openrouter.sh`** (new module)
  - OpenRouter `/models` fetch with 30s timeout and loading animation.
  - Response caching in temp file.
  - Lazy grep/sed parsing: provider prefix extraction, model filtering per provider.
  - Provider menu builder (curated common list + Other + Manual entry).
  - Model menu builder (top 15 by recency + "Show all" threshold).
  - Deduplication and deterministic sorting helpers.
  - Manual fallback flow with step-by-step instructions.
  - Module guard to prevent re-sourcing (consistent with existing `lib/*.sh` pattern).
- `lib/deploy.sh`
  - Source `lib/openrouter.sh` and call into it from the OpenRouter path in `deploy_collect_llm_config()`.
  - Replace inline static model menu with call to new module's provider-first dynamic menu.
  - Keep manual entry fallback path.
- `tests/mocks/curl`
  - Add fixtures for:
    - successful `/models` payload (representative subset, not full 346-model response)
    - malformed entries (missing `id`, empty `id`, no `/` in ID)
    - duplicate IDs
    - colon-variant IDs (`:free`, `:nitro`, etc.)
    - `openrouter/`-prefixed model IDs
    - empty/invalid payload
    - transport failure (timeout, connection refused)
- **`tests/openrouter.bats`** (new test file)
  - Add coverage for:
    - provider prefix extraction (including `openrouter/` prefix, colon variants)
    - curated common provider list ordering
    - "Other providers" alphabetical ordering
    - top-15-by-recency model sorting
    - "Show all" threshold behavior
    - model ordering within provider
    - duplicate/malformed filtering
    - manual escape-hatch path (provider-level)
    - fetch-failure manual-only fallback with step-by-step instructions
    - temp file caching and cleanup

## PR test plan

1. Unit-like shell tests in `tests/openrouter.bats`:
- valid payload -> expected provider/model menus (curated first, then Other)
- duplicate IDs -> single rendered option
- malformed entries (missing `id`, no `/`) -> ignored
- colon-variant IDs (`:free`, `:nitro`) -> shown as separate full entries
- `openrouter/`-prefixed IDs -> treated as `openrouter` provider, not stripped
- deterministic ordering -> exact menu snapshot assertions
- top 15 by recency -> correct subset shown, "Show all" present for larger providers
- manual entry from provider menu -> skips model sub-menu
- fetch failure -> warning + step-by-step manual-only path with `openrouter.ai/models` URL
- temp file cleanup on exit

2. Mock contract coverage in `tests/mocks/curl`:
- verify parser behavior against representative OpenRouter payload shapes
- fixture uses a representative subset (not the full 346-model response)

3. Regression check:
- non-OpenRouter providers continue using existing behavior unchanged

## Dependencies and sequencing

- No upstream Hermes Agent code changes required for this PR.
- This PR is intentionally independent and can merge first.
- Follow-on PRs consume the selected model output from this flow.

## Open questions captured (from source plan, relevant here)

1. Should model entries without a standard provider prefix be grouped as `other` or shown only in manual mode?
   - **Resolved**: grouped as `other` provider, shown in the "Other providers" tier of the provider menu.
2. Should we include a "refresh models" action in the wizard or keep single fetch per setup run?
   - **Deferred**: single fetch per setup run for this PR. Refresh can be added later.
3. Should provider/model menus surface metadata (context length, pricing) now or later?
   - **Deferred**: later. This PR focuses on model discovery and selection only.

## Acceptance criteria

- OpenRouter setup no longer depends on a hardcoded model table.
- Provider-first picker is deterministic and tested.
- Manual model-ID path remains available.
- Fetch failures degrade safely to manual-only mode.
- Original incident context is preserved, but no reasoning-effort logic is implemented in this PR.

## Implementation clarifications (from review, 2026-03-10)

### JSON parsing strategy

hermes-fly is pure Bash 3.2+ with no jq dependency. The `/models` response contains ~346 models.

Approach: **lazy parsing per stage against a cached temp file**.

1. Fetch the full response once, store in a temp file under the build context.
2. For provider extraction (stage 1): `grep '"id":' | sed` to extract unique prefixes before the first `/`.
3. For model listing (stage 2): `grep` for the selected provider prefix, extract `id`, `name`, and `created` fields with sed.
4. Sort models by `created` timestamp (numeric, descending) for recency ordering.
5. Clean up the temp file via `trap EXIT`.

This avoids introducing jq as a dependency while keeping the parsing robust for the known response shape.

### API response shape (confirmed live, 2026-03-10)

The `/models` endpoint returns `{"data": [...]}` with ~346 model objects. Key fields per model:

- `id`: full model identifier, e.g. `"openai/gpt-5-mini"` (required for API calls)
- `name`: human-readable display name, e.g. `"OpenAI: GPT-5 Mini"` (used for display)
- `created`: Unix timestamp (used for recency sorting)
- `canonical_slug`: stable identifier that never changes. Not used in this PR because `canonical_slug` cannot be used in API requests — only `id` is accepted in the `model` parameter of chat/completion calls. However, model IDs do change over time (OpenRouter has silently removed 39+ model IDs with no deprecation notice). A future PR could store `canonical_slug` alongside `id` in the deploy config to enable re-resolution on redeploy: if the stored `id` no longer exists, look up the current `id` via `canonical_slug` from a fresh `/models` fetch.

No pagination — all models returned in a single response. The endpoint is edge-cached.

Provider counts observed: openai (61), qwen (50), google (27), mistralai (25), meta-llama (17), anthropic (13), deepseek (12), z-ai (11), nvidia (8), x-ai (8), minimax (6), and others.

### Model ID edge cases

Two documented pitfalls that the parser must handle:

1. **Colon suffixes**: IDs like `google/gemini-2.0-flash-exp:free` or `openai/gpt-oss-120b:exacto` must be preserved verbatim. The colon suffix denotes a semantically distinct variant (`:free` = free tier, `:nitro` = high throughput, `:thinking` = extended reasoning, `:extended` = extended context).

2. **`openrouter/` prefix**: OpenRouter hosts native models under its own namespace (e.g., `openrouter/aurora-alpha`). The provider prefix extraction must treat `openrouter` as a regular provider — do not strip or special-case it.

Safe extraction pattern:
```bash
provider="${model_id%%/*}"    # everything before first /
model_name="${model_id#*/}"   # everything after first / (may contain more slashes or colons)
```

### Timeout and loading UX

- Fetch timeout: `--max-time 30` (longer than the existing `--max-time 10` for key validation, because the response is larger)
- Display a loading animation during the fetch, consistent with existing hermes-fly loading patterns
- On timeout: fall back to manual-only mode with step-by-step instructions

### Manual fallback UX

When the `/models` fetch fails (timeout, network error, malformed response):

1. Print a non-technical warning explaining that the model list could not be loaded.
2. Direct the user to `https://openrouter.ai/models` to browse and copy a model ID.
3. Prompt for the model ID with input validation (non-empty, contains `/`).
4. Reasoning effort is NOT collected in this PR — that is deferred to PR 2.

### Remaining open questions (low priority, not blocking)

- Whether the curated common provider list should be refreshed periodically as provider popularity shifts.
- Whether `canonical_slug` should be stored alongside `id` for redeploy re-resolution. `canonical_slug` cannot replace `id` in API calls, but model IDs are silently removed/renamed by OpenRouter (39+ documented removals, no deprecation notices). Storing `canonical_slug` would let a future redeploy flow re-resolve the current `id` when the original one disappears.

## References

- `openrouter-gpt5-mini-reasoning-triage-20260309.md`
- https://openrouter.ai/docs/api/api-reference/models/get-models
- https://openrouter.ai/docs/api/reference/parameters
