# PR 4 Plan: Deployment Provenance Capture (Local + Runtime)

Date: 2026-03-10
Scope: `hermes-fly` repo only
Status: Ready for implementation

## Problem

During the incident, operators had to SSH into the live app to discover key runtime facts (model, reasoning source, Hermes Agent commit). This is slow, error-prone, and hard to scale for support.

This PR adds explicit provenance recording so the answer to "what exactly is running?" is available both locally and inside the deployed app.

## Confirmed baseline

From the source investigation (`openrouter-gpt5-mini-reasoning-triage-20260309.md`):

- `deploy_write_summary()` already writes local YAML/Markdown deploy summaries.
- line-range reference from source plan: `lib/deploy.sh:1109-1138`
- live inspection on 2026-03-09 confirmed:
  - app inspected: `hermes-sprite-981`
  - model: `openai/gpt-5-mini`
  - no `HERMES_REASONING_EFFORT` env var
  - config had `reasoning_effort: "xhigh"`
  - live Hermes Agent commit: `caab1cf...`
- temporary mitigation changed config to `medium` on disk.

Operational lesson captured in source plan:

- avoid `python3` + `import yaml` for first-line diagnostics in the current container image because `yaml` module may not be installed (`PyYAML` is not guaranteed present there).
- no repository code changes are required to run live checks directly; if productized, primary files are `lib/doctor.sh`, `templates/entrypoint.sh`, `tests/doctor.bats`, and `tests/scaffold.bats`.

## Product decision carried into this PR

Provenance should exist in both locations:

- local deploy summary files (release-to-deploy correlation)
- runtime app artifact (live-state inspection without reconstruction)

## In scope (this PR)

1. Extend local deploy summary fields for provenance.
2. Write runtime provenance manifest in deployed app.
3. Expose equivalent metadata via env vars where useful.
4. Add tests for summary and runtime manifest write path.
5. Keep manual inspection commands documented for operational fallback.

## Out of scope (deferred)

- Full drift-detection comparison logic (local vs live mismatch checks).
- Release channel policy behavior.
- Runtime safety clamp/retry logic in Hermes Agent.

## Provenance schema (minimum)

Record these fields per deploy:

- `hermes_fly_version`
- `hermes_agent_ref`
- deploy channel (`stable|preview|edge` when available)
- compatibility policy version
- selected reasoning effort
- selected provider/model
- generated Dockerfile source ref
- deploy timestamp

Runtime location:

- `/root/.hermes/deploy-manifest.json` (machine-readable)
- runtime provenance/config artifacts are expected under `/root/.hermes/`

Local outputs:

- deploy summary YAML/Markdown (existing outputs, extended fields)

## File-level implementation plan

- `lib/deploy.sh`
  - extend summary writer data model and emitted fields
  - thread provenance values through deploy flow
- `templates/entrypoint.sh`
  - write runtime manifest file on boot using environment/deploy inputs
  - ensure idempotent write behavior across restarts
- `lib/docker-helpers.sh` and `templates/Dockerfile.template` (if needed)
  - ensure manifest/source metadata required at runtime is available in image/environment
- `tests/deploy.bats`
  - assert summary includes new provenance keys
- `tests/scaffold.bats`
  - assert runtime manifest exists and contains expected keys/values

## Test plan

1. Summary contract tests:
- all required provenance keys present
- values match deploy input state

2. Runtime manifest tests:
- manifest file written on boot
- expected keys present and parseable
- repeated startup does not corrupt format

3. Backward-compat checks:
- existing deploy summary consumers continue to function

## Operational baseline appendix (from source plan)

These commands remain valid for manual verification and should be preserved as fallback diagnostics:

1. Check effective model and reasoning config:

```bash
fly ssh console --app <APP> -C 'sh -lc '"'"'grep -n "^LLM_MODEL=" /root/.hermes/.env; grep -n "^HERMES_REASONING_EFFORT=" /root/.hermes/.env; grep -n "reasoning_effort" /root/.hermes/config.yaml'"'"''
```

2. Dump safe config snippet without PyYAML dependency:

```bash
fly ssh console --app <APP> -C 'sh -lc '"'"'printf "LLM_MODEL_env=%s\n" "${LLM_MODEL-}"; printf "HERMES_REASONING_EFFORT_env=%s\n" "${HERMES_REASONING_EFFORT-}"; grep -n -B 4 -A 4 "reasoning_effort" /root/.hermes/config.yaml'"'"''
```

3. Verify Hermes Agent ref present in container:

```bash
fly ssh console --app <APP> -C 'sh -lc '"'"'if [ -d /opt/hermes/hermes-agent/.git ]; then git -C /opt/hermes/hermes-agent rev-parse HEAD; else echo "no git metadata"; fi'"'"''
```

Safe temporary workaround if `xhigh` is detected unexpectedly:

```bash
fly ssh console --app <APP> -C 'sh -lc '"'"'sed -i.bak "s/^  reasoning_effort: \"xhigh\"$/  reasoning_effort: \"medium\"/" /root/.hermes/config.yaml && grep -n "reasoning_effort" /root/.hermes/config.yaml'"'"''
```

Then restart or redeploy if runtime does not hot-reload config.

Operational command note carried from source:

- `hermes-fly doctor` is the intended long-term surface for these checks once productized drift/provenance reporting is in place.
- runtime provenance and reasoning checks still depend on upstream `hermes-agent` behavior being surfaced consistently.

## Risk assessment

- Risk: provenance fields drift between local summary and runtime manifest format.
- Mitigation: define explicit schema contract and test both outputs.

- Risk: sensitive values accidentally written.
- Mitigation: exclude secrets from manifest by design; include refs/config identity only.

## Resolved decision item captured here

- Provenance should live in both local deploy records and runtime app metadata.

## Acceptance criteria

- Local deploy summary includes provenance keys needed for support.
- Runtime manifest is written and inspectable in deployed app.
- Tests validate schema and value wiring end-to-end within this repo.
- Manual fallback inspection commands are documented and still usable.

## References

- `openrouter-gpt5-mini-reasoning-triage-20260309.md`
- https://docs.docker.com/build/metadata/attestations/slsa-provenance/
- https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/building_running_and_managing_containers/introduction-to-reproducible-container-builds
