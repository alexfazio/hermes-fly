# PR-D1 REVIEW-1 Implementation Report

Date: 2026-03-12
Plan: `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_1.md`

## Summary of Review Fixes

Implemented all REVIEW-1 remediations:

1. Fixed Commander root wiring so `buildProgram()` returns the root command.
2. Added explicit root `version` subcommand and aligned `--version`/`version` output with legacy contract (`hermes-fly <version>`).
3. Preserved legacy-compatible `list` argument behavior on allowlisted TS path (`--help` and unknown flags do not trigger Commander parsing errors).
4. Added hybrid dispatch regression tests for dist-present `version` routing.
5. Added list arg parity tests (`--help`, `--unknown-flag`) comparing legacy vs allowlisted TS path byte-for-byte.
6. Fixed HOME-empty runtime config fallback to use `/.hermes-fly` semantics instead of relative `.hermes-fly`.
7. Added runtime unit coverage for HOME-empty fallback behavior.
8. Hardened `scripts/verify-pr-d1-list-command.sh` with dist-present routing assertions and list arg parity assertions.

## Deterministic Verification Command Log

All section 5 criteria were executed and passed.

1. File-level checks:
- Verified required files exist, including this report file.

2. Dist CLI root routing contracts:
- `npm run build`
- `node dist/cli.js --version`
- `node dist/cli.js version`
- `node dist/cli.js help`

3. Hybrid dist-present non-list routing contract:
- `npm run build`
- `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version`

4. List arg parity under allowlisted TS path:
- Executed deterministic seeded parity diffs for legacy vs TS on:
  - `list --help`
  - `list --unknown-flag`

5. HOME-empty fallback semantics parity:
- Executed deterministic legacy vs TS diff with `HOME=''` and `.hermes-fly/config.yaml` in CWD.

6. Existing PR-D1 regression gates:
- `npm run typecheck`
- `npm run arch:ddd-boundaries`
- `npm run test:domain-primitives`
- `npm run test:runtime-list`
- `tests/bats/bin/bats tests/list-ts-hybrid.bats tests/list.bats tests/parity-harness.bats tests/hybrid-dispatch.bats tests/integration.bats`
- `npm run parity:check`

7. One-command verifier:
- `./scripts/verify-pr-d1-list-command.sh`
- Result: prints `PR-D1 verification passed.`

## Explicit Non-Change Statement

Confirmed unchanged in this remediation:

- `scripts/install.sh`
- `scripts/release-guard.sh`
