# PR-A1 Implementation Report

Date: 2026-03-12  
Plan: `docs/plans/typescript-commander-hybrid-rewrite-pr-a1-foundation-20260312.md`  
Primary implementation commit: `ec13e14`  
Execution branch: `main`

## Scope implemented

- TS foundation scaffolding:
  - `package.json`
  - `tsconfig.json`
  - `src/cli.ts`
  - `src/version.ts`
  - `src/legacy/bash-bridge.ts`
  - `dist/.gitkeep`
- Hybrid dispatcher scaffolding in `hermes-fly`:
  - `HERMES_FLY_IMPL_MODE=legacy|hybrid|ts`
  - `HERMES_FLY_TS_COMMANDS` allowlist
  - TS runtime/artifact gate (`node` + `dist/cli.js`)
  - deterministic single-line fallback warning
- Documentation:
  - `README.md` section `Developer Migration Flags`
- Tests:
  - `tests/hybrid-dispatch.bats`

## Out-of-scope carry-over recorded

The implementation commit also included two documentation changes that were already pending from prior user-requested tasks:

- moved `docs/plans/openrouter-reasoning/05-release-channels-and-drift-detection.md` to `docs/plans/openrouter-reasoning/done/05-release-channels-and-drift-detection.md`
- updated `docs/plans/typescript-commander-hybrid-rewrite-20260311.md` audit/status text

These do not alter runtime behavior and are documented here for audit clarity.

## Deterministic verification evidence

## File existence checks

Verified present:

- `package.json`
- `tsconfig.json`
- `src/cli.ts`
- `src/version.ts`
- `src/legacy/bash-bridge.ts`
- `dist/.gitkeep`
- `tests/hybrid-dispatch.bats`

## Behavioral checks

Checks executed:

```bash
cmp -s <(./hermes-fly --version) <(HERMES_FLY_IMPL_MODE=legacy ./hermes-fly --version)
cmp -s <(./hermes-fly help) <(HERMES_FLY_IMPL_MODE=legacy ./hermes-fly help)
cmp -s <(./hermes-fly deploy --help) <(HERMES_FLY_IMPL_MODE=legacy ./hermes-fly deploy --help)
```

Result: all comparisons equal (exit code `0`).

## Hybrid fallback contract

Executed:

```bash
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version >/tmp/hf.stdout 2>/tmp/hf.stderr
```

Observed:

- stdout: `hermes-fly 0.1.20`
- stderr lines: `1`
- stderr content starts with: `Warning: TS implementation unavailable for command 'version'; falling back to legacy`

## Test evidence

Executed:

```bash
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
npm run typecheck
```

Result:

- BATS: passing
- typecheck: passing

## Re-runnable verifier

Added script:

- `scripts/verify-pr-a1-foundation.sh`

Usage:

```bash
./scripts/verify-pr-a1-foundation.sh
```

This script enforces the PR-A1 acceptance checks in a deterministic, single-command flow.
