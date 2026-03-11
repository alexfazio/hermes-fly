Issues Found

MEDIUM

1. Runtime manifest schema is incomplete/inconsistent with local summary schema
`templates/entrypoint.sh:111-114` writes runtime keys:
- `compat_policy_version`
- `llm_model`

`lib/deploy.sh:1324-1336` writes local summary keys:
- `compatibility_policy_version`
- `llm.provider` / `llm.model`

This creates a schema mismatch between local and runtime provenance surfaces and makes direct comparisons fragile.

References:
- `templates/entrypoint.sh:111`
- `templates/entrypoint.sh:113`
- `lib/deploy.sh:1325`
- `lib/deploy.sh:1334`

Actionable instructions for implementer:
1. Align runtime manifest key names with local summary naming where fields represent the same concept.
2. Rename runtime `compat_policy_version` to `compatibility_policy_version` in `templates/entrypoint.sh`.
3. Add provider to runtime manifest (`llm_provider`) so runtime captures both provider and model, matching local summary intent.
4. Ensure runtime manifest uses the same deploy-channel semantics and default as local summary (`stable` fallback unless explicitly set).
5. Update `deploy_provision_resources` to pass any newly required runtime manifest field(s) via secrets (for example provider and compatibility policy version), using existing env naming conventions.
6. Add or update tests to validate actual key names and values in runtime manifest content, not just string presence in template.
7. Keep backwards compatibility decision explicit:
   - either support both old and new keys temporarily with a comment and deprecation note, or
   - switch atomically and update all tests in the same PR.

2. Runtime manifest JSON writing is not escaped for arbitrary values
`templates/entrypoint.sh:106-116` builds JSON with raw `printf` interpolation. If any field contains `"` or `\`, the JSON can become invalid.

References:
- `templates/entrypoint.sh:106`
- `templates/entrypoint.sh:116`

Actionable instructions for implementer:
1. Replace raw string interpolation JSON assembly with a safe serializer approach.
2. Preferred approach: use `python3 - <<'PYEOF'` (already used elsewhere in entrypoint) to build a dict from env vars and write JSON via `json.dump(...)`.
3. If Python-based writer is used:
   - read env vars with defaults mirroring current behavior,
   - write to `/root/.hermes/deploy-manifest.json`,
   - ensure stable key set and valid JSON regardless of special characters.
4. If shell-only approach is kept, introduce a robust JSON-escape helper and cover quote/backslash/newline cases in tests; avoid ad hoc escaping.
5. Preserve idempotent “write on every boot” behavior.
6. Add tests that validate manifest validity under special-character inputs (at minimum quotes and backslashes in one or more fields).

LOW

3. Provenance secret tests are implementation-presence checks, not behavior checks
`tests/deploy.bats:1941-1958` greps source code for strings (`HERMES_FLY_VERSION`, `HERMES_AGENT_REF`, `HERMES_DEPLOY_CHANNEL`) rather than validating the actual secret payload passed by `deploy_provision_resources`.

References:
- `tests/deploy.bats:1941`
- `tests/deploy.bats:1948`
- `tests/deploy.bats:1954`
- `lib/deploy.sh:1147-1153`

Actionable instructions for implementer:
1. Replace source-grep tests with behavior tests that execute `deploy_provision_resources` and inspect the secrets passed to `fly_set_secrets`.
2. Reuse the existing secret-capture pattern used in this repo (temporary log file + mocked `fly_set_secrets` appending args).
3. Assert exact key-value pairs for provenance secrets:
   - `HERMES_FLY_VERSION=...`
   - `HERMES_AGENT_REF=...`
   - `HERMES_DEPLOY_CHANNEL=...`
   - and compatibility policy secret when set.
4. Add default-path coverage:
   - channel defaults to `stable` when unset,
   - optional compatibility policy key is omitted when unset (or asserted as empty only if intentionally designed that way).
5. Keep one lightweight structural test (optional), but behavioral assertions must be primary and sufficient on their own.

Notes

- Static review only; tests were not rerun in this review pass.

Validation Criteria (Implementer Sign-off)

1. Schema alignment is complete and consistent
1. Runtime manifest key `compatibility_policy_version` exactly matches local summary key naming.
2. Runtime manifest includes both model and provider fields (or an explicitly documented equivalent schema that is consistent across local and runtime outputs).
3. Local summary and runtime manifest can be compared field-by-field without ad hoc key translation for shared concepts.
4. Any intentional schema difference is documented inline in code comments and reflected in tests.

2. JSON validity is guaranteed for arbitrary content
1. Manifest writing path cannot emit invalid JSON when values include:
   - double quotes (`"`),
   - backslashes (`\`),
   - spaces and punctuation.
2. At least one test covers special-character value input and confirms manifest parseability.
3. Manifest generation still succeeds when optional fields are unset.
4. Idempotent write behavior remains: manifest is rewritten on each boot without first-boot guard.

3. Provenance secret wiring is behavior-tested end-to-end
1. Tests execute `deploy_provision_resources` with mocked `fly_set_secrets`.
2. Tests assert secrets payload contains expected provenance keys/values, not just source text matches.
3. Tests cover explicit-value and default-value paths (for channel and compatibility policy behavior).
4. Tests fail if a key is renamed, removed, or not passed to `fly_set_secrets`.

4. Regression safety for existing behavior
1. Existing non-provenance deploy behaviors remain unchanged:
   - model/reasoning secret wiring,
   - messaging secret wiring,
   - app/volume provisioning flow.
2. Existing PR-03 pinning behavior remains intact:
   - Hermes ref selection and summary output still function.
3. Entrypoint still boots gateway successfully after manifest changes.

5. Reviewer-verifiable evidence in diff
1. Diff shows replacement of raw JSON interpolation with safe serialization logic.
2. Diff shows schema key alignment updates in both runtime writer and tests.
3. Diff shows conversion of grep-based tests to payload-behavior tests.
4. Test additions clearly map to each finding in this review document.
