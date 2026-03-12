# Release Operations: Channels, Drift, and Rollback

This runbook defines promotion and rollback requirements for `stable`, `preview`, and `edge`.

## Channel Policy

- `stable`: default, pinned Hermes Agent ref, reproducible path.
- `preview`: opt-in validation channel, currently pinned to the same ref as `stable` until a dedicated preview stream is published.
- `edge`: expert-only, tracks moving `main`, explicitly non-reproducible.

CLI surface:

- Deploy: `hermes-fly deploy --channel stable|preview|edge`
- Env: `HERMES_FLY_CHANNEL=stable|preview|edge`
- Precedence: deploy flag overrides env var.

## Stable Promotion Gates

Promotion to `stable` requires all checks below:

1. OpenRouter restricted family (example: `openai/gpt-5-mini`)
- Setup does not offer unsupported high tiers.
- Deploy succeeds.
- One real chat round-trip succeeds without `unsupported_value`.

2. OpenRouter allowlisted high-effort family
- Setup offers allowlisted high tier.
- Deploy succeeds.
- One real chat round-trip succeeds without downgrade loops.

3. OpenRouter unknown/not-yet-allowlisted family
- Setup falls back conservatively.
- Deploy succeeds.
- One real chat round-trip succeeds with conservative defaults.

4. Non-OpenRouter sanity deploy
- Deploy succeeds for non-OpenRouter provider path.

5. Provenance + drift checks
- Runtime manifest reports expected ref/channel/policy version.
- `hermes-fly doctor` drift check passes for canary app.

## Rollback Contract

Rollback must support all three dimensions independently:

1. `hermes-fly` release version
- Reinstall pinned release (`HERMES_FLY_VERSION=vX.Y.Z ... install.sh`) and redeploy.

2. Hermes Agent ref
- Override deploy ref with `HERMES_AGENT_REF=<ref>` for emergency mitigation.
- Revert to channel canonical ref after incident resolution.

3. Compatibility policy version
- Revert bundled snapshot/policy version and redeploy.
- Confirm `compatibility_policy_version` matches in local summary and runtime manifest.

Post-rollback verification:

1. `hermes-fly status -a <app>`
2. `hermes-fly doctor -a <app>`
3. one real model round-trip for target provider/model class

## External Dependency Contracts

Dependencies that may drift and how hermes-fly handles them:

1. OpenRouter `/models`
- Minimum contract: response contains `data`; selectable records require `id`.
- Safe failure: fetch/shape issues fall back to manual model entry.
- Coverage: `tests/openrouter.bats` (malformed payload, missing `data`, missing `id` fallback).

2. Fly.io APIs
- Minimum contract: best-effort extraction for org/region/vm fields.
- Safe failure: deploy wizard falls back to static region/vm defaults when metadata is missing or unreadable.
- Coverage: `tests/deploy.bats` parsing/fallback cases and `tests/fly-helpers.bats` wrapper behavior.

3. Telegram Bot API
- Minimum contract: `getMe` must return `ok=true` and `result.username`.
- Safe failure: token validation fails closed and prompts for re-entry.
- Coverage: `tests/messaging.bats` valid/invalid token API checks and missing-username failure.

4. Hermes Agent install entrypoint
- Minimum contract: Docker build installs from `.../${HERMES_VERSION}/scripts/install.sh`.
- Safe failure: deterministic channel/ref selection and channel/policy metadata in generated Dockerfile.
- Coverage: `tests/docker-helpers.bats` template and render checks.

## Regression Suite

Run before release promotion:

```bash
tests/bats/bin/bats \
  tests/deploy.bats \
  tests/doctor.bats \
  tests/docker-helpers.bats \
  tests/install.bats \
  tests/integration.bats \
  tests/openrouter.bats \
  tests/messaging.bats
```
