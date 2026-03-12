# Hermes-Fly TypeScript Rewrite Plan (Commander.js, Hybrid Rollout)

Date: 2026-03-11
Scope: `/Users/alex/Documents/GitHub/hermes-fly` only
Status: Ready for implementation (revalidated on 2026-03-12; execution not started)

## Objective

Rewrite `hermes-fly` from bash modules to TypeScript + Commander.js without stopping release cadence, by shipping a hybrid implementation that routes command-by-command and always preserves a safe bash fallback.

## Core Decision

Yes, the rewrite will be modular and releaseable throughout:

- Keep existing `hermes-fly` bash entrypoint as public contract during migration.
- Add a dispatcher that can invoke TypeScript command handlers per-command.
- Keep unmigrated commands on bash.
- Allow hard fallback to bash on runtime errors or missing Node runtime.
- Promote commands to TypeScript only after deterministic parity gates pass.

## Hard Constraints (Do Not Break)

1. Existing install flow (`scripts/install.sh`) must continue to produce a working CLI on macOS and Linux.
2. Existing command surface and semantics must remain stable:
- `deploy`
- `resume`
- `status`
- `logs`
- `doctor`
- `list`
- `destroy`
- `help`
- `version`
3. Existing release process (`scripts/release-guard.sh`, semver tags, GitHub Releases) must remain usable in every migration phase.
4. No regressions in secret handling (do not print keys/tokens to stdout/stderr or logs).
5. Existing bash implementation remains the source of truth fallback until each command is promoted.

## Implementation Audit Update (2026-03-12)

This section records plan-vs-codebase audit findings without changing the intended migration design below.

### Snapshot conclusion

- Overall completion: not started (pre-PR-A).
- The plan document exists, but no TypeScript hybrid migration artifacts are present in runtime, test, or CI.

### Evidence summary

1. Missing TS foundation artifacts:
- `package.json`
- `tsconfig.json`
- `src/` tree (`cli.ts`, `version.ts`, command files, contexts)
- `dist/cli.js` and `dist/.gitkeep`
2. Missing hybrid dispatcher wiring in `hermes-fly`:
- no `HERMES_FLY_IMPL_MODE`
- no `HERMES_FLY_TS_COMMANDS`
- no `node` + `dist/cli.js` execution path
- no TS-to-bash fallback signal handling path
3. Missing parity harness and migration control artifacts:
- no `scripts/parity-capture.sh`
- no `scripts/parity-compare.sh`
- no `tests/parity/baseline/*.snap`
- no `data/ts-migration-state.json`
4. Missing TS/architecture CI jobs:
- no `test:ts`
- no `build:ts`
- no `parity:promoted-commands`
- no `arch:ddd-boundaries`
- no repository workflow files implementing these gates
5. Install/release scripts are still bash-only migration baseline:
- `scripts/install.sh` does not install `dist/` or migration metadata.
- `scripts/release-guard.sh` does not validate TS artifact/version parity or parity evidence files.

### Phase completion matrix (audited 2026-03-12)

| Phase | Name | Status |
| --- | --- | --- |
| 0 | Foundation and Safety Rails | Not started |
| 0.5 | DDD Model Bootstrap | Not started |
| 1 | Command Contract Snapshot (Parity Harness) | Not started |
| 2 | Migrate `list` | Not started |
| 3 | Migrate `status` and `logs` | Not started |
| 4 | Migrate `doctor` | Not started |
| 5 | Migrate `destroy` | Not started |
| 6 | Shared Provider/Messaging Libraries in TS | Not started |
| 7 | Migrate `resume` | Not started |
| 8 | Incremental `deploy` Rewrite | Not started |
| 9 | Default Flip to TS for Safe Commands | Not started |
| 10 | Full Cutover and Legacy Removal | Not started |

### Revalidated immediate execution start (unchanged intent)

Begin with PR A exactly as defined in this plan: TS toolchain + Commander skeleton + hybrid dispatcher scaffolding + boundary checks, with zero user-facing behavior change and full existing bats suite green.

## Current State Inventory (Baseline)

Current entrypoint and modules:

- Entrypoint: `hermes-fly`
- Bash modules:
  - `lib/deploy.sh`
  - `lib/destroy.sh`
  - `lib/doctor.sh`
  - `lib/status.sh`
  - `lib/logs.sh`
  - `lib/list.sh`
  - `lib/config.sh`
  - `lib/prereqs.sh`
  - `lib/fly-helpers.sh`
  - `lib/docker-helpers.sh`
  - `lib/openrouter.sh`
  - `lib/reasoning.sh`
  - `lib/messaging.sh`
  - `lib/ui.sh`
- Test suites (bats):
  - `tests/deploy.bats`
  - `tests/doctor.bats`
  - `tests/destroy.bats`
  - `tests/status.bats`
  - `tests/logs.bats`
  - `tests/list.bats`
  - `tests/prereqs*.bats`
  - `tests/openrouter.bats`
  - `tests/reasoning.bats`
  - `tests/messaging.bats`
  - `tests/integration.bats`
  - others in `tests/`

## Target Architecture (TypeScript + DDD)

### New top-level layout

```text
src/
  cli.ts
  version.ts
  commands/
    deploy.ts
    resume.ts
    status.ts
    logs.ts
    doctor.ts
    list.ts
    destroy.ts
  adapters/
    flyctl.ts
    docker.ts
    git.ts
    curl.ts
    process.ts
    fs.ts
    env.ts
    logger.ts
    prompts.ts
  shared/
    core/
      errors.ts
      result.ts
      value-object.ts
    infra/
      retry.ts
      time.ts
      redaction.ts
  contexts/
    deploy/
      domain/
        entities/
        value-objects/
        services/
      application/
        use-cases/
        ports/
      infrastructure/
        adapters/
      presentation/
        wizard/
    diagnostics/
      domain/
      application/
      infrastructure/
      presentation/
    messaging/
      domain/
      application/
      infrastructure/
    release/
      domain/
      application/
      infrastructure/
    runtime/
      domain/
      application/
      infrastructure/
  legacy/
    bash-bridge.ts
dist/
  cli.js
```

### DDD bounded contexts

1. `Deploy`:
- app provisioning, region/size/storage selection, template generation, provenance metadata.
2. `Diagnostics`:
- doctor checks, drift detection, summarized operator findings.
3. `Messaging`:
- Telegram/Discord configuration, token validation, allowed user policy.
4. `Release`:
- version/tag/release invariants, release guard compatibility checks.
5. `Runtime`:
- command execution orchestration and environment capabilities (node availability, fallback policy).

### Ubiquitous language (must be consistent across code + docs)

1. `DeploymentIntent`: normalized user choices before provisioning.
2. `DeploymentPlan`: resolved, validated plan ready to execute.
3. `ProvenanceRecord`: persisted channel/ref/policy metadata.
4. `DriftFinding`: typed diagnostic mismatch result.
5. `MessagingPolicy`: who can talk to bot (`only_me`, `specific_users`, `anyone`).
6. `ReleaseContract`: version/tag/artifact consistency rules.

### Layering rules (strict)

1. `domain`:
- pure logic only, no IO, no CLI rendering, no process execution.
2. `application`:
- orchestrates use-cases; depends only on `domain` + `ports`.
3. `infrastructure`:
- adapters for flyctl/curl/fs/process/network; implements ports.
4. `presentation`:
- Commander handlers and prompt/table formatting only.
5. Forbidden dependency directions:
- `domain -> infrastructure` disallowed.
- `domain -> presentation` disallowed.
- cross-context calls must go through application ports or an anti-corruption adapter.

### Hybrid anti-corruption layer

The existing bash implementation is treated as an anti-corruption layer during migration:

1. TS command fails closed to typed fallback signal.
2. Dispatcher executes legacy bash command.
3. Output includes one concise fallback notice.
4. No shared mutable state between TS domain objects and sourced bash globals.

### Commander command contract

- Root command: `hermes-fly`
- Subcommands and flags remain unchanged.
- Keep existing help text behavior as close as practical for compatibility.
- Keep exit code behavior consistent with bash commands.

### Hybrid dispatcher contract

`hermes-fly` (bash) routes commands using deterministic policy:

1. Determine implementation mode:
- `HERMES_FLY_IMPL_MODE=legacy|hybrid|ts` (default `hybrid` during migration).
2. Determine per-command implementation:
- `HERMES_FLY_TS_COMMANDS` comma list (for example `list,status,doctor`).
3. For a command in TS set:
- If Node runtime + `dist/cli.js` available, execute TS.
- If missing runtime/artifact or TS exits with fallback-marked error, route to bash and print single-line warning.
4. For non-TS commands:
- Always execute existing bash path.

## Runtime Strategy During Hybrid

To avoid breaking existing users:

1. Node is optional during migration.
2. Default path remains bash for all commands at first.
3. TS paths are progressively enabled per command after parity.
4. If TS cannot run (`node` missing, broken artifact), command transparently falls back to bash.

## Version and Release Contract

### Single version source

Keep `HERMES_FLY_VERSION` in `hermes-fly` as canonical version until full cutover.

### Add release guard checks

Extend `scripts/release-guard.sh` to validate:

1. If `dist/cli.js` exists, embedded TS version matches `HERMES_FLY_VERSION`.
2. If TS command promotion flags are changed, parity evidence file exists for this release.
3. No dirty worktree.

### Install contract

During hybrid:

- `scripts/install.sh` continues copying `hermes-fly`, `lib/`, `templates/`, `data/`.
- Add copying `dist/` and minimal runtime metadata (`package.json` optional for diagnostics).
  - **Finding** [MEDIUM]: `package.json` provides diagnostic metadata for `doctor` checks and release guard version verification at ~1KB overhead. Since `src/version.ts` compiles into `dist/cli.js`, `package.json` serves as a secondary verification source. **Recommendation**: Include `package.json` in install artifacts (change from 'optional' to 'included').
- No install-time dependency install step.
- Runtime fallback protects users without Node.

## Migration Phases (Detailed)

## Phase 0: Foundation and Safety Rails

### Scope

1. Introduce TS toolchain and Commander skeleton without changing user behavior.
2. Add hybrid dispatch plumbing but keep all commands on bash.
3. Establish DDD package boundaries and lint-enforced dependency rules.

### Files to add/update

1. Add:
- `package.json`
- `tsconfig.json`
- `src/cli.ts`
- `src/version.ts`
- `src/legacy/bash-bridge.ts`
- `src/contexts/` skeleton per bounded context
- `eslint` import-boundary configuration (or equivalent) to enforce layer rules
  - **Finding** [HIGH]: Both `eslint-plugin-boundaries` and `dependency-cruiser` are mature tools for DDD layer enforcement. `dependency-cruiser` offers richer regex-based path matching that maps directly to `src/contexts/<context>/<layer>/` structure, standalone CI integration, and cross-context isolation via group matching. `eslint-plugin-boundaries` integrates into ESLint for in-editor feedback but requires more complex config for 5+ bounded contexts ([dependency-cruiser](https://github.com/sverweij/dependency-cruiser), [eslint-plugin-boundaries](https://github.com/javierbrea/eslint-plugin-boundaries)). **Recommendation**: Use `dependency-cruiser` as the primary CI boundary check; optionally add `eslint-plugin-boundaries` for editor-time feedback.
- `dist/.gitkeep` (or generated artifact policy file)
2. Update:
- `hermes-fly` (hybrid dispatch wrapper, defaulting to legacy behavior)
- `.gitignore` (TS build artifacts policy)
- `README.md` (developer section only; no user-facing behavioral change)

### Deterministic verification criteria

1. `./hermes-fly --version` output unchanged.
2. `./hermes-fly help` output unchanged.
3. All existing bats tests pass unchanged.
4. `HERMES_FLY_IMPL_MODE=legacy ./hermes-fly <cmd>` equals baseline behavior for every command.
5. `HERMES_FLY_IMPL_MODE=hybrid` with empty TS command set still executes bash for all commands.
6. Import-boundary check fails if any domain module imports infrastructure/presentation modules.

## Phase 0.5: DDD Model Bootstrap

### Scope

Define core domain model and invariants before command porting.

### Deliverables

1. Add domain primitives:
- `DeploymentIntent`
- `DeploymentPlan`
- `ProvenanceRecord`
- `DriftFinding`
- `MessagingPolicy`
- `ReleaseContract`
2. Add context-level port interfaces in `application/ports`.
3. Add anti-corruption adapter contracts for legacy bash fallback.

### Deterministic verification criteria

1. Domain module tests pass with zero mocks for process/network/fs.
2. Invalid state construction fails deterministically (for example invalid channel/model policy combos).
3. Cross-context dependency rule check passes.
4. Existing CLI behavior remains unchanged (`bats` baseline still green).

## Phase 1: Command Contract Snapshot (Parity Harness)

### Scope

Create machine-checkable contract snapshots for command behavior before migration.

### Deliverables

1. Add parity harness script:
- `scripts/parity-capture.sh`
- `scripts/parity-compare.sh`
2. Add baseline fixtures:
- `tests/parity/baseline/*.snap`
3. Add CI job for parity checks on promoted commands.

### Deterministic verification criteria

1. For each command (`list,status,logs,doctor,destroy,resume,deploy`):
- capture `stdout`, `stderr`, exit code for mocked scenarios.
2. Re-run capture twice: snapshots must be stable (no nondeterministic drift).
3. Comparison tool reports exact diff with file + line.

## Phase 2: Migrate `list` (lowest risk)

### Scope

Implement `list` in TS; keep bash fallback.

### Files

1. Add:
- `src/commands/list.ts`
- `src/adapters/flyctl.ts`
- `src/adapters/process.ts`
- `src/contexts/runtime/application/use-cases/list-deployments.ts`
- `src/contexts/runtime/application/ports/deployment-registry.port.ts`
- `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`
2. Update:
- `src/cli.ts`
- `hermes-fly` (add `list` to pilot TS allowlist only behind env flag)

### Deterministic verification criteria

1. `tests/list.bats` still passes in default mode.
2. TS path validation:
- `HERMES_FLY_TS_COMMANDS=list HERMES_FLY_IMPL_MODE=hybrid ./hermes-fly list` matches parity snapshot in mocked environment.
3. If `node` absent:
- command falls back to bash with single warning line and same exit code.

### Release gate

`list` can be enabled by default in hybrid mode only after:

1. parity snapshots match in CI for 3 consecutive commits, and
2. no regression in full bats suite.

## Phase 3: Migrate `status` and `logs`

### Scope

Implement read-only operational commands in TS.

### Files

1. Add:
- `src/commands/status.ts`
- `src/commands/logs.ts`
- shared table renderer in `src/shared/core/` if needed
  - **Finding** [MEDIUM]: Three commands (`list`, `status`, `doctor`) need tabular output. A shared renderer in `src/shared/core/table.ts` avoids duplication. Recommend adding it during Phase 2 (`list` migration) using either a thin `cli-table3` wrapper or a minimal custom formatter. **Recommendation**: Promote from 'if needed' to planned deliverable in Phase 2.
- use-cases under `src/contexts/runtime/application/use-cases/`
2. Update parity fixtures for both commands.

### Deterministic verification criteria

1. `tests/status.bats` and `tests/logs.bats` pass in default path.
2. TS paths produce equivalent data fields and exit codes.
3. Streaming behavior for `logs`:
- CTRL-C handling and process termination tested with mock process.

## Phase 4: Migrate `doctor`

### Scope

Port diagnostics checks and drift checks with strict output contract.

### Key risk

`doctor` contains nuanced logic and user-facing messaging; preserve diagnostic meaning and failure semantics.

### Files

1. Add:
- `src/commands/doctor.ts`
- `src/contexts/diagnostics/domain/checks/*.ts`
- `src/contexts/diagnostics/application/use-cases/run-doctor.ts`
- `src/contexts/diagnostics/infrastructure/adapters/*.ts`
2. Map from bash `lib/doctor.sh` check-by-check and encode each finding type as a typed `DriftFinding`.

### Deterministic verification criteria

1. All `tests/doctor.bats` pass with default routing.
2. TS routing for `doctor` matches:
- check ordering,
- failure/success exit code,
- presence of key diagnostic messages.
3. Drift-specific checks:
- missing summary, missing channel, mismatch cases must produce same outcomes.
4. Domain tests verify check invariant rules independent of shell/process adapters.

## Phase 5: Migrate `destroy`

### Scope

Port teardown flow including confirmations and Telegram cleanup behavior.

### Files

1. Add:
- `src/contexts/deploy/application/use-cases/destroy-deployment.ts`
- `src/contexts/messaging/application/use-cases/revoke-telegram-session.ts`
- relevant infrastructure adapters in both contexts.

### Deterministic verification criteria

1. `tests/destroy.bats` pass.
2. `--force` behavior identical.
3. No secret leakage in logs for token-related operations.
4. TS fallback path handles partial failures without orphaning local config state.

## Phase 6: Shared Provider/Messaging Libraries in TS

### Scope

Extract provider/model/messaging logic into TS modules before full `deploy` migration.

### Deliverables

1. Add modules:
- `src/contexts/deploy/infrastructure/adapters/openrouter-catalog.ts`
- `src/contexts/messaging/infrastructure/adapters/telegram-api.ts`
- ~~`src/contexts/messaging/infrastructure/adapters/discord-api.ts`~~ (not applicable -- Discord was removed from `lib/messaging.sh`; only backward-compat secret bridging remains in `templates/entrypoint.sh`)
  - **Finding** [HIGH]: Codebase confirms Discord fully removed from messaging module. No Discord setup flow, validation, or behavior exists to port. Only `DISCORD_BOT_TOKEN`/`DISCORD_ALLOWED_USERS` env bridging remains in entrypoint template for backward compat. **Recommendation**: Drop this adapter from Phase 6 scope.
2. Add domain/application modules:
- `src/contexts/messaging/domain/*`
- `src/contexts/messaging/application/use-cases/*`
- `src/contexts/deploy/application/use-cases/select-model.ts`
2. Reuse existing contract behavior from:
- `lib/openrouter.sh`
- `lib/messaging.sh`
- `lib/reasoning.sh`

### Deterministic verification criteria

1. Port corresponding unit/behavior tests (new TS tests + existing bats coverage preserved).
2. Telegram token validation and poll-conflict detection behavior preserved.
3. Model selection and reasoning compatibility decisions match existing fixtures.

## Phase 7: Migrate `resume`

### Scope

Port `resume` functionality (post-interruption recovery checks) to TS using shared deploy state contracts.

### Files

1. Add:
- `src/contexts/deploy/application/use-cases/resume-deployment.ts`
- `src/contexts/deploy/domain/entities/deployment-journal.ts`
- `src/contexts/deploy/infrastructure/adapters/deployment-journal-fs.ts`

### Deterministic verification criteria

1. Existing integration scenarios for interrupted deploy are reproducible with TS resume path.
2. Exit code and user guidance messages match existing contract.

## Phase 8: Incremental `deploy` Rewrite (Sub-Phases)

`deploy` is highest complexity; migrate by internal steps with strict gates.

### Phase 8.1: Non-interactive deploy primitives

1. Fly app creation wrapper
2. Volume creation wrapper
3. Secret setting wrapper
4. Deploy command wrapper
5. `DeploymentPlan` aggregate execution in application layer (no direct Commander logic).

Verification:

1. Unit tests for command construction.
2. Mocked integration test verifies order and retry policy.

### Phase 8.2: Interactive wizard framework

1. Prompt adapter abstraction
2. Table rendering and default selection behavior
3. Input validation parity
4. Map prompt outputs into `DeploymentIntent` value objects.

Verification:

1. Snapshot tests for prompt text where deterministic.
2. Behavior tests for invalid input re-prompt loops.

### Phase 8.3: Provider and model selection

1. OpenRouter key verification
2. Provider list loading and model menu rendering
3. Failure handling (timeouts/network errors)
4. `ModelSelectionPolicy` domain service for compatibility gating and channel constraints.

Verification:

1. Existing provider selection edge cases covered by migrated tests.
2. Timeout/retry behavior deterministic.

### Phase 8.4: Messaging setup flows

1. Telegram setup, token verification, conflict detection
2. Access policy prompts and home channel prompts
3. `MessagingPolicy` domain validation and anti-corruption mapping to legacy env keys.

Verification:

1. `tests/messaging.bats` equivalent behavior retained via parity harness and TS tests.

### Phase 8.5: Scaffold generation and config writing

1. Dockerfile and fly.toml generation
2. Deploy summary persistence
3. Channel/provenance metadata persistence
4. `ProvenanceRecord` generation from `DeploymentPlan` and release context.

Verification:

1. Generated files diff identical (or intentionally normalized with approved diff map).
2. `doctor` reads TS-generated metadata without regression.

### Phase 8.6: End-to-end deploy orchestration

1. Preflight checks
2. Resource provisioning
3. Deployment verification and success summary
4. Resume-token/operation journal for interrupted sessions
5. Domain-event-style result objects (no shell-global side effects).

Verification:

1. Integration suite passes for happy path + interruption path + recovery.
2. Failure messages actionable and not generic.

## Phase 9: Default Flip to TS for Safe Commands

### Scope

Enable TS by default for low/medium-risk commands while keeping fallback and override.

### Target order

1. `list`, `status`, `logs`
2. `doctor`
3. `destroy`, `resume`
4. `deploy` last

### Deterministic verification criteria

1. Canary period per command with release notes annotation.
2. Error rate thresholds met (no increase in failed command invocations in telemetry if available, else issue-based gate).
3. `HERMES_FLY_IMPL_MODE=legacy` emergency switch documented and tested.

## Phase 10: Full Cutover and Legacy Removal

### Preconditions

1. All commands have passed parity gates.
2. At least two stable releases with TS default for all commands and no critical regressions.

### Scope

1. Switch `hermes-fly` to exec TS CLI directly (or keep thin bash shim).
2. Archive/remove legacy bash modules from runtime path (optionally move to `legacy/` for one release).
  - **Finding** [MEDIUM]: The plan's own rollback mechanism (`HERMES_FLY_IMPL_MODE=legacy`) requires bash modules in the runtime path. Moving to `legacy/` (not removing) preserves rollback during the deprecation window. Full removal should follow one release after the deprecation window closes. **Recommendation**: Commit to 'move to `legacy/`' for at least one release rather than leaving it optional; schedule full removal for the subsequent release.
3. Simplify release/install scripts around new runtime contract.

### Deterministic verification criteria

1. Full CI green (bats legacy compatibility + TS suites).
2. Install from latest release works on clean Linux and macOS test hosts.
3. `--version` and command help outputs remain consistent with docs.

## Test Strategy

## 1. Preserve existing bats as compatibility net

- Keep all existing bats tests until full cutover is complete.
- For migrated commands, run tests in both modes:
  - legacy (`HERMES_FLY_IMPL_MODE=legacy`)
  - hybrid+TS (`HERMES_FLY_IMPL_MODE=hybrid`, command in TS set)

## 2. Add TS unit/integration tests

Recommended stack:

- Test runner: `vitest`
- Mocking: built-in + process wrapper mocks
- Snapshot assertions for deterministic text/table outputs

DDD-specific requirements:

1. Domain tests per bounded context:
- no process/network/fs mocks in domain tests,
- invariant tests for entities/value objects/services.
2. Application tests:
- mock only application ports, verify orchestration behavior and error mapping.
3. Infrastructure tests:
- adapter contract tests against mocked fly/curl/fs/process boundaries.

## 3. Add parity test matrix in CI

For each promoted command:

1. Run bash path and capture tuple `(stdout, stderr, exit_code)`.
2. Run TS path and capture same tuple.
3. Compare with normalization rules:
- strip ANSI color when `NO_COLOR=1`
- allow known timestamp fields only if normalized

Fail CI on mismatch unless explicitly approved in a parity exception file.

## 4. Enforce architecture constraints in CI

1. Add dependency-boundary check (eslint/import rules or dependency-cruiser):
- fail on forbidden imports (`domain -> infrastructure`, `domain -> presentation`).
2. Add context-isolation check:
- fail on direct cross-context infrastructure coupling.
3. Add anti-corruption check:
- only `legacy/bash-bridge.ts` may directly execute legacy command wrappers in TS mode.

## CI/CD Updates

Add jobs:

1. `test:bats` (existing)
2. `test:ts` (new)
3. `parity:promoted-commands` (new)
4. `build:ts` (new)
5. `arch:ddd-boundaries` (new)

Merge gate:

- No PR may promote a command to TS default without:
  - passing parity job
  - updated command migration checklist item
  - release note entry

## Migration Control File

Add a tracked control file:

- `data/ts-migration-state.json`

Suggested schema:

```json
{
  "impl_mode_default": "hybrid",
  "ts_default_commands": [],
  "ts_canary_commands": ["list"],
  "parity_baseline_version": "0.1.19"
}
```

Purpose:

1. explicit promoted/canary command inventory,
2. reproducible release behavior,
3. auditable command promotion history.

## Security and Reliability Requirements

1. Never include secrets in thrown errors or logs.
2. Process adapter must support explicit timeout and cancellation.
3. All network operations must classify failures:
- auth error
- connectivity error
- rate limit
- unknown
4. Interactive prompts must be interrupt-safe (CTRL-C cleanup).
5. Fallback to bash must not recurse infinitely (guard by env var, for example `HERMES_FLY_FALLBACK_DEPTH`).

## Rollback Plan

Rollback must be possible in <5 minutes for a bad release.

### Rollback mechanisms

1. Operational:
- set `HERMES_FLY_IMPL_MODE=legacy` to force bash path.
2. Release:
- cut patch release reverting command promotions.
3. Emergency:
- remove TS command from `data/ts-migration-state.json` and republish patch.

### Deterministic rollback verification

1. On latest release artifact:
- `HERMES_FLY_IMPL_MODE=legacy ./hermes-fly deploy` works.
2. Release guard passes post-rollback.
3. Install script still validates version correctly after rollback tag.

## Proposed PR Breakdown

1. PR A: TS foundation + hybrid dispatcher + DDD boundaries (no behavior change)
2. PR B: DDD model bootstrap (`DeploymentIntent`, `DeploymentPlan`, `ProvenanceRecord`, `DriftFinding`, `MessagingPolicy`, `ReleaseContract`)
3. PR C: Parity harness + baseline snapshots
4. PR D: TS `list` in `runtime` context
5. PR E: TS `status` + `logs` in `runtime` context
6. PR F: TS `doctor` in `diagnostics` context
7. PR G: TS `destroy` in `deploy` + `messaging` contexts
8. PR H: provider/messaging infrastructure adapters and domain services
9. PR I: TS `resume` in `deploy` context
10. PR J-M: TS `deploy` sub-phases (8.1-8.6)
11. PR N: default promotion and cleanup

Each PR must include:

1. explicit migration scope statement,
2. parity evidence for affected command(s),
3. fallback behavior test(s),
4. release note snippet.

## Estimated Timeline (1 Engineer)

1. Foundation + DDD boundaries + parity harness: 1.5 to 2 weeks
2. Read-only commands: 1 week
3. Doctor + destroy + resume: 1.5 to 2 weeks
4. Deploy sub-phases: 2.5 to 3.5 weeks
5. Stabilization + default flip: 1 week

Total: ~7 to 9.5 weeks depending on deploy wizard complexity and parity deltas.

## Acceptance Criteria (Project Complete)

1. All user commands run in TS by default.
2. Legacy mode remains available for one deprecation window (at least one minor release).
3. Full test suite green, including parity checks.
4. Installer and release guard enforce consistent versioning and artifact integrity.
5. No open P0/P1 regressions attributable to migration after two stable releases.
6. Architecture boundary checks pass: no forbidden DDD layer dependencies.
7. Core invariants are covered by domain tests in each bounded context.

## Definition of Done Per Command Migration

Command migration is considered complete only when all are true:

1. Command implemented in TS.
2. Command wired in hybrid dispatcher.
3. Legacy fallback path tested.
4. Parity snapshot approved.
5. Existing bats command tests pass.
6. New TS tests added for command-specific logic.
7. Release note updated.
8. DDD boundary checks pass for touched contexts.

## Immediate Next Step (Execution Start)

Start with PR A (foundation):

1. Add TS toolchain and Commander skeleton.
2. Add hybrid dispatch logic to `hermes-fly` with default legacy behavior.
3. Add `HERMES_FLY_IMPL_MODE` and `HERMES_FLY_TS_COMMANDS` docs in README developer section.
4. Add DDD folder skeleton + import-boundary lint rules.
5. Prove zero user-facing behavior change via full existing bats suite.

---

## References

- [dependency-cruiser GitHub repository](https://github.com/sverweij/dependency-cruiser)
- [eslint-plugin-boundaries GitHub repository](https://github.com/javierbrea/eslint-plugin-boundaries)
- [dependency-cruiser rules reference (DDD patterns)](https://github.com/sverweij/dependency-cruiser/blob/main/doc/rules-reference.md)
- [eslint-plugin-boundaries element-types rule docs](https://github.com/javierbrea/eslint-plugin-boundaries/blob/master/docs/rules/element-types.md)
- [Jest vs Vitest comparison (2025)](https://medium.com/@ruverd/jest-vs-vitest-which-test-runner-should-you-use-in-2025-5c85e4f2bda9)
- [Vitest official comparisons page](https://vitest.dev/guide/comparisons)
- [Enforcing DDD Bounded Contexts with boundaries enforcement (Medium)](https://medium.com/@sergioausin1993/boundaries-enforcement-in-ts-e2597c65bc4d)
- [Three Ways to Enforce Module Boundaries (Nx comparison)](https://www.stefanos-lignos.dev/posts/nx-module-boundaries)
- [Modern Node.js Patterns for 2025](https://kashv1n.com/blog/nodejs-2025/)
