# PR 3 Plan: Make Hermes Agent Pinning Explicit and Reproducible

Date: 2026-03-10
Scope: `hermes-fly` repo only
Status: Ready for implementation

## Problem

Current deploy behavior installs Hermes Agent from upstream `main` during image build. That makes deploy outcomes time-dependent and undermines reproducibility, incident triage, and supportability.

## Confirmed baseline

From the source investigation (`openrouter-gpt5-mini-reasoning-triage-20260309.md`):

- `deploy_create_build_context()` calls Dockerfile generation with `"main"`.
- exact current call shape in source plan references: `docker_generate_dockerfile "$build_dir" "main"`
- `templates/Dockerfile.template` uses `ARG HERMES_VERSION={{HERMES_VERSION}}` and fetches install script from that ref.
- install fetch path pattern: `https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh`
- Confirmed local refs:
  - `lib/deploy.sh:878-903` (call passes `main`)
  - `templates/Dockerfile.template:3,6`
- prior `0.1.14` raw GitHub 404 discussion does not describe current deploy path; current path clearly resolves from moving `main` at build time.
- Resulting product risk:
  - same `hermes-fly` release can install different Hermes Agent commits on different dates

Incident relevance:

- failing runtime commit was `caab1cf...`, while upstream `main` later changed defaults
- this demonstrates real user-visible behavior drift tied to moving upstream refs

## Product decision carried into this PR

- Prefer explicit pinned Hermes Agent ref per `hermes-fly` release for default behavior.
- If moving refs are allowed, they must be explicit, documented, and non-default.
- If moving refs remain available, incident analysis must be anchored to deploy date/time, not only release version string.
- Deploy metadata must expose what ref was used.

## In scope (this PR)

1. Replace implicit hardcoded `main` with explicit upstream ref resolution.
2. Define default pinned ref behavior for normal deploys.
3. Ensure Dockerfile generation receives and renders explicit ref.
4. Surface selected ref in deploy summary metadata.
5. Add test coverage proving generated Dockerfile contains intended ref.

## Out of scope (deferred)

- Full release channel policy (`stable|preview|edge`) and UX.
- Drift detection checks and runtime-vs-local comparison logic.
- Provenance manifest schema beyond the ref field needed for this PR.

## Detailed design

### Ref resolution policy

Default target:

- deployment path resolves to one explicit Hermes Agent ref (commit SHA or tag) that is versioned with the `hermes-fly` release

Optional override behavior (advanced use only):

- override may exist for explicit non-stable workflows, but must never be silent

### Build path changes

- `deploy_create_build_context()` must pass a resolved ref variable, not a literal `main`
- `docker_generate_dockerfile` must remain deterministic with that ref input
- Dockerfile template rendering must preserve exact string for traceability

### Metadata output changes

At minimum include in deploy summary:

- `hermes_agent_ref`
- generated Dockerfile source ref

## File-level implementation plan

- `lib/deploy.sh`
  - add upstream ref resolution function
  - thread resolved ref into build-context generation
  - include ref in summary output
- `lib/docker-helpers.sh`
  - validate Dockerfile generation accepts explicit ref input
- `templates/Dockerfile.template`
  - ensure install URL/path interpolation is ref-driven and testable
- `scripts/install.sh`
  - align installer default semantics with deploy pinning direction
- `hermes-fly`
  - if user-facing output includes upstream ref policy, keep help/version text aligned
- `tests/docker-helpers.bats`
  - assert rendered Dockerfile uses expected ref
- `tests/deploy.bats`
  - assert summary includes resolved ref
- `tests/install.bats` and `tests/integration.bats`
  - keep installer/deploy default behavior consistent with pinning decision

## Test plan

1. Dockerfile generation tests:
- pinned ref input -> exact pinned ref in generated Dockerfile
- no accidental fallback to `main`

2. Deploy summary tests:
- summary output contains `hermes_agent_ref`
- output remains deterministic across runs

3. Installer consistency tests:
- install path default matches declared pin policy

## Risk assessment

- Risk: pin staleness can block urgent upstream fixes.
- Mitigation: explicit update workflow for pinned ref + release note entry.

- Risk: hidden override paths reintroduce nondeterminism.
- Mitigation: require explicit user intent and record resolved ref in outputs.

## Dependency and sequencing

- This PR should land before channel/drift work, because channels need a stable pin baseline.
- Provenance PR can extend this output, but this PR provides the minimum ref contract now.

## Resolved decision items captured here

- Tracking `main` by default is too risky for reproducibility.
- A pinned ref per release is the preferred stable behavior.
- If tracking `main` is retained in any mode, the tradeoff must be documented as non-reproducible.

## Acceptance criteria

- Deploy path no longer hardcodes `main` as implicit default.
- Build uses explicit resolved Hermes Agent ref.
- Deploy output includes ref used for build.
- Tests verify generated Dockerfile and metadata reflect chosen ref exactly.

## References

- `openrouter-gpt5-mini-reasoning-triage-20260309.md`
- [NousResearch hermes-agent install.sh (upstream)](https://github.com/NousResearch/hermes-agent/blob/main/scripts/install.sh#L786-L790)
- https://raw.githubusercontent.com/NousResearch/hermes-agent/caab1cf4536f79f5b74552f47360e178e6d28ff9/gateway/run.py
- https://raw.githubusercontent.com/NousResearch/hermes-agent/main/gateway/run.py
- [Docker SLSA Provenance Attestations docs](https://docs.docker.com/build/metadata/attestations/slsa-provenance/)
- [Helm Chart Dependencies Best Practices](https://helm.sh/docs/chart_best_practices/dependencies/)
