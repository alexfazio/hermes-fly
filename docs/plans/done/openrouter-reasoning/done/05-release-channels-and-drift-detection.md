# PR 5 Plan: Release Channels + Drift Detection + Stability Operations

Date: 2026-03-10
Scope: `hermes-fly` repo only
Status: Implemented (2026-03-12)

## Problem

Fixing one incident is not enough if deploy behavior remains nondeterministic and difficult to verify after release. We need explicit channel policy, drift visibility, and operational guardrails so stable releases stay reproducible and supportable.

## Confirmed baseline

From the source investigation (`openrouter-gpt5-mini-reasoning-triage-20260309.md`):

- runtime behavior drift occurred across time because upstream Hermes Agent input moved
- setup-time checks alone cannot guarantee provider behavior stability
- support required live SSH investigation to reconstruct active runtime inputs

## Product decisions carried into this PR

1. User-facing channel policy:
- `stable`: pinned, reproducible, default
- `preview`: opt-in for broader pre-release validation
- `edge`: expert-only, moving targets (for example upstream `main`)

2. UX policy:
- standard wizard stays on `stable` by default
- non-default channels via explicit advanced input (flags and/or env)
- do not add extra first-run interactive question for most users

3. Drift detection policy:
- detect mismatch between intended release manifest and deployed runtime manifest
- surface unexpected ref/channel/policy-version states in doctor output

4. Conservative-default policy:
- unknown model family -> `medium`
- unknown compatibility -> hide advanced options
- unknown upstream ref -> loud warning
- unknown channel/provenance -> fail closed for stable flows

## In scope (this PR)

1. Define and implement channel selection surface (advanced-only for non-default).
2. Wire channel into deploy/build resolution path.
3. Add drift-detection checks in diagnostics (`doctor`).
4. Add staged rollout + rollback operational contract.
5. Add external dependency contract coverage strategy and safe-failure behavior.
6. Ship regression tests for channel behavior and drift reporting.

## Out of scope (deferred)

- Hermes Agent runtime clamp/retry implementation (upstream).
- Broad provider-specific compatibility expansion beyond initial registry.

## Deterministic input contract

Each `stable` deploy should resolve to a stable input set, including:

- `hermes_fly_version`
- `hermes_agent_ref`
- compatibility policy version
- default runtime policy version
- template revision

Moving refs should appear only in explicit non-stable channels.

## Channel behavior details

### `stable`

- default mode
- uses pinned upstream refs
- intended reproducible path

### `preview`

- explicit opt-in
- intended for pre-release validation breadth
- can include controlled newer refs while preserving manifest traceability

### `edge`

- expert-only
- may track moving upstream refs
- explicitly non-reproducible
- omitted from first-run interactive wizard

## Drift detection checks

`doctor` should detect and report:

- local deploy summary vs intended release manifest mismatch
- runtime manifest vs local summary mismatch
- unexpected upstream ref
- unexpected channel
- unknown compatibility policy version

## Staged rollout and rollback contract

Promotion to `stable` requires minimum smoke matrix:

1. OpenRouter restricted family (example `openai/gpt-5-mini`):
- setup does not offer `xhigh`
- deploy succeeds
- one real chat round-trip succeeds without `unsupported_value`

2. OpenRouter allowlisted high-effort family:
- setup offers allowlisted high tier
- deploy succeeds
- one real chat round-trip succeeds without downgrade loops

3. OpenRouter unknown/not-yet-allowlisted family:
- setup falls back conservatively
- deploy succeeds
- one real chat round-trip succeeds with conservative default

4. Non-OpenRouter sanity deploy:
- verify no regression outside OpenRouter path

5. Provenance + drift check pass:
- app reports expected ref/channel/policy version
- doctor reports coherent values for canary app

Rollback plan must cover all three dimensions:

- `hermes-fly` release version
- Hermes Agent ref
- compatibility policy version

## External dependency contract handling

Dependencies that can drift and require explicit contracts:

- OpenRouter `/models`
- Fly.io APIs
- Telegram Bot API responses
- Hermes Agent install entrypoint

Required controls:

- fixture coverage for known payload shapes
- contract tests for minimum required fields
- safe failure behavior when metadata is missing/incomplete

## File-level implementation plan

- `lib/deploy.sh`
  - resolve/apply channel and associated input policy
  - include channel and policy details in deploy outputs
- `lib/doctor.sh`
  - implement drift checks and operator-facing mismatch reporting
- `lib/docker-helpers.sh`
  - ensure deterministic build input flow by channel
- `templates/Dockerfile.template`
  - support channel/ref metadata labeling where required
- `scripts/install.sh`
  - align installer defaults and channel semantics with deploy behavior
- `hermes-fly`
  - expose advanced channel inputs and help text as needed
- test coverage:
  - `tests/deploy.bats` (channel selection and summary)
  - `tests/doctor.bats` (drift detection/reporting)
  - `tests/docker-helpers.bats` (deterministic input generation)
  - `tests/install.bats` (installer channel behavior)
  - `tests/integration.bats` (stable vs preview vs edge end-to-end)

## Test plan

1. Channel resolution tests:
- default path resolves to `stable`
- explicit preview/edge inputs only active when requested
- wizard path does not prompt extra channel question by default

2. Drift diagnostics tests:
- mismatched ref/channel/policy produce clear doctor findings
- matching manifests produce clean status

3. End-to-end contract tests:
- stable and non-stable paths produce expected provenance and behavior

## Risk assessment

- Risk: channel complexity leaks into first-run UX.
- Mitigation: keep non-default channels advanced-only.

- Risk: false positives from drift checks due to schema mismatch.
- Mitigation: strict manifest schema and versioned comparison logic.

- Risk: unstable upstream dependencies break edge path unexpectedly.
- Mitigation: explicit messaging and no stable guarantees for edge.

## Resolved decision items captured here

- User-facing policy should be `stable` default plus opt-in `preview`/`edge`.
- Minimum smoke-test matrix must include restricted, allowlisted, unknown, non-OpenRouter, and provenance/drift coverage.

## Resolved: CLI Surface for Channel Selection

1. Exact advanced CLI surface for channel selection and advanced reasoning options: flags, env vars, or both.
   - **Finding** [HIGH]: Industry best practices (CLI Guidelines, 12-Factor App) recommend using BOTH flags and environment variables for configuration that varies between invocations. The CLI Guidelines specify precedence: flags > shell env vars > project config. Fly.io's flyctl demonstrates this pattern with flags like `--strategy` and env vars like `NO_COLOR`. **Recommendation**: Implement `--channel stable|preview|edge` flag plus `HERMES_FLY_CHANNEL` environment variable, with flags taking precedence over env vars. This enables interactive use (flags) and CI/automation (env vars) while following established patterns from the deployment target platform. ([clig.dev](https://clig.dev/#configuration), [12factor.net](https://12factor.net/config))

## Acceptance criteria

- Channel policy is explicit and implemented with `stable` default.
- Drift detection exists and reports actionable mismatches.
- Release promotion and rollback expectations are documented and test-backed.
- External dependency contracts are represented in tests with safe-failure behavior.

## References

- `openrouter-gpt5-mini-reasoning-triage-20260309.md`
- [CLI Guidelines - Configuration](https://clig.dev/#configuration)
- [12-Factor App - Config](https://12factor.net/config)
- [Fly.io flyctl deploy docs](https://fly.io/docs/flyctl/deploy/)
- https://docs.docker.com/build/metadata/attestations/slsa-provenance/
- https://helm.sh/docs/chart_best_practices/dependencies/
- https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/building_running_and_managing_containers/introduction-to-reproducible-container-builds
- https://openrouter.ai/docs/api/api-reference/models/get-models
