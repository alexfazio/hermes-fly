# PR-A1 Execution Plan: TypeScript Foundation + Hybrid Dispatcher (No User-Visible Behavior Change)

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-20260311.md`  
Parent phase: Phase 0 (Foundation and Safety Rails)  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-a1-foundation` (recommended)  
Implementation branch used: `main` (completed on commit `ec13e14`)

## Implementation Status

Status: Implemented  
Evidence report: `docs/plans/typescript-commander-hybrid-rewrite-pr-a1-foundation-20260312-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Implement the first migration PR that introduces TypeScript project scaffolding and a bash-level hybrid dispatcher contract, while keeping runtime behavior unchanged for all users by default.

This PR must be merge-safe and release-safe:

- default runtime path stays legacy bash,
- no existing command behavior regressions,
- no installer/release-guard contract changes yet,
- no TS command promotion yet.

---

## 2) Scope

### In scope (must ship in this PR)

1. Add minimal TS project skeleton files:
- `package.json`
- `tsconfig.json`
- `src/cli.ts`
- `src/version.ts`
- `src/legacy/bash-bridge.ts`
- `dist/.gitkeep`

2. Add hybrid dispatch plumbing in entrypoint:
- modify `hermes-fly` currently at `hermes-fly:1-183`
- introduce environment switches:
  - `HERMES_FLY_IMPL_MODE=legacy|hybrid|ts`
  - `HERMES_FLY_TS_COMMANDS` (comma list)
- default mode for this PR is `legacy` (no behavior change).

3. Update developer docs:
- add migration env var section in `README.md` (use current anchors around `README.md:130-139`).

4. Add TS artifact ignore policy:
- update `.gitignore` currently at `.gitignore:1-5`.

5. Add focused dispatcher tests:
- new `tests/hybrid-dispatch.bats`
- verify default legacy behavior and safe fallback behavior when TS artifact is missing.

### Out of scope (do not do in this PR)

1. No command porting to TS (`list`, `status`, etc.).
2. No CI workflow additions.
3. No parity harness scripts.
4. No release-guard TS checks.
5. No installer changes to copy `dist/` yet.
6. No dependency-boundary tool integration (`dependency-cruiser`) yet.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Baseline commit should include current bash-only entrypoint semantics (reference snapshot from `hermes-fly:96-183`).

Capture baseline command contracts before edits:

```bash
./hermes-fly --version > /tmp/hermes-fly.version.baseline
./hermes-fly help > /tmp/hermes-fly.help.baseline
./hermes-fly deploy --help > /tmp/hermes-fly.deploy-help.baseline
```

If any command above fails, stop and fix local environment before coding.

---

## 4) Exact File Changes

## 4.1 Add `package.json` (new file)

Path: `package.json`  
Action: create.

Required content contract:

1. Set `"name": "hermes-fly"`.
2. Set `"private": true`.
3. Set `"type": "module"`.
4. Add scripts:
- `"build": "tsc -p tsconfig.json"`
- `"typecheck": "tsc --noEmit -p tsconfig.json"`
5. Add dependencies:
- `commander` (pinned major version)
6. Add devDependencies:
- `typescript` (pinned major version)

Do not add runtime install hooks, postinstall scripts, or release automation.

## 4.2 Add `tsconfig.json` (new file)

Path: `tsconfig.json`  
Action: create.

Required compiler contract:

1. `rootDir` is `src`.
2. `outDir` is `dist`.
3. module target supports Node ESM.
4. strict mode enabled.
5. include only `src/**/*.ts`.

## 4.3 Add TS source skeleton (new files)

Paths:
- `src/cli.ts`
- `src/version.ts`
- `src/legacy/bash-bridge.ts`

Actions: create all three.

Required behavior contract:

1. `src/version.ts` exports a TS CLI version constant (placeholder is acceptable in PR-A1).
2. `src/legacy/bash-bridge.ts` defines typed fallback signal/error class used for future fallback semantics.
3. `src/cli.ts` must compile (once dependencies are installed), define a Commander root command named `hermes-fly`, and keep implementation intentionally minimal (no command parity required in this PR).

No TS command should be wired into production path yet.

## 4.4 Add `dist/.gitkeep` (new file)

Path: `dist/.gitkeep`  
Action: create.

Purpose: reserve output directory path in repo while keeping built artifacts untracked.

## 4.5 Update `.gitignore`

Path: `.gitignore` (currently lines 1-5).  
Action: append TS build artifact rules without removing existing entries.

Required ignore rules:

1. Ignore built JS artifacts under `dist/`.
2. Keep `dist/.gitkeep` tracked.
3. Keep existing `.DS_Store` and `*.sha256` rules unchanged.

## 4.6 Update `hermes-fly` with hybrid dispatch scaffolding

Path: `hermes-fly`  
Current anchors:
- version constant at `hermes-fly:4`
- command dispatch starts at `hermes-fly:96`

Action: modify.

Required implementation contract:

1. Add helper functions before `main()`:
- normalize impl mode (`legacy|hybrid|ts`), fallback unknown -> `legacy` with warning.
- check if command is in `HERMES_FLY_TS_COMMANDS` comma list.
- evaluate TS executability (`node` present and `${SCRIPT_DIR}/dist/cli.js` exists).
- execute TS CLI when requested and executable.
- produce single-line fallback warning when TS requested but unavailable.

2. Default mode must be `legacy` in this PR.

3. Command routing policy:
- `legacy`: always run existing bash case block.
- `hybrid`: run TS only when command is allowlisted; otherwise legacy.
- `ts`: same allowlist check for this PR; non-allowlisted commands remain legacy.

4. If TS execution path returns failure due unavailability (missing node/dist), fallback to legacy in the same process and preserve legacy exit code/output.

5. Existing case branches (`deploy`, `status`, `resume`, `logs`, `doctor`, `list`, `destroy`, `help`, `version`) must remain unchanged in behavior and messages.

Do not reorder source imports (`hermes-fly:15-29`) and do not modify command help text blocks (`hermes-fly:31-94`) in this PR.

## 4.7 Update README developer section

Path: `README.md`  
Current anchor for docs area: `README.md:126-139` (License at 126, Documentation at 130).

Action: add a new section named `Developer Migration Flags` before `## License`.

Required content:

1. Explain `HERMES_FLY_IMPL_MODE` values and PR-A1 default (`legacy`).
2. Explain `HERMES_FLY_TS_COMMANDS` comma-list behavior.
3. State explicitly that TS command execution is scaffold-only in this PR and defaults to legacy.
4. Provide 2 executable examples:
- force legacy mode
- hybrid mode with allowlisted command demonstrating fallback when TS artifact is absent.

No end-user install/deploy instructions should be changed in this PR.

## 4.8 Add focused test file

Path: `tests/hybrid-dispatch.bats`  
Action: create.

Reuse existing test setup contract from `tests/test_helper/common-setup.bash:1-16`.

Required tests (minimum 6):

1. `default impl mode is legacy`  
Command: `./hermes-fly version`  
Assert: exit `0`, output exactly `hermes-fly 0.1.20`, no fallback warning.

2. `legacy mode ignores TS allowlist`  
Env: `HERMES_FLY_IMPL_MODE=legacy HERMES_FLY_TS_COMMANDS=version`  
Assert: same stdout as baseline, no fallback warning.

3. `hybrid mode with non-allowlisted command stays legacy`  
Env: `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list`  
Command: `./hermes-fly version`  
Assert: legacy output, no fallback warning.

4. `hybrid mode allowlisted command falls back when dist missing`  
Env: `HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version`  
Precondition: `dist/cli.js` absent  
Assert: stdout remains `hermes-fly 0.1.20`, stderr contains exactly one fallback warning line.

5. `ts mode allowlisted command falls back when dist missing`  
Env: `HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version`  
Assert: same as test 4.

6. `invalid impl mode normalizes to legacy with warning`  
Env: `HERMES_FLY_IMPL_MODE=invalid`  
Command: `./hermes-fly version`  
Assert: legacy output + one mode-normalization warning.

---

## 5) Deterministic Verification Criteria

All checks below are required and must pass exactly.

## 5.1 File-level verification

Run:

```bash
test -f package.json
test -f tsconfig.json
test -f src/cli.ts
test -f src/version.ts
test -f src/legacy/bash-bridge.ts
test -f dist/.gitkeep
test -f tests/hybrid-dispatch.bats
```

Expected: all commands exit `0`.

## 5.2 Behavioral no-regression checks

Run:

```bash
cmp -s /tmp/hermes-fly.version.baseline <(./hermes-fly --version)
cmp -s /tmp/hermes-fly.help.baseline <(./hermes-fly help)
cmp -s /tmp/hermes-fly.deploy-help.baseline <(./hermes-fly deploy --help)
```

Expected: all `cmp` commands exit `0`.

## 5.3 Hybrid fallback checks (exact)

Run:

```bash
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version >/tmp/hf.stdout 2>/tmp/hf.stderr
cat /tmp/hf.stdout
wc -l /tmp/hf.stderr
```

Expected:

1. `/tmp/hf.stdout` is exactly:
```text
hermes-fly 0.1.20
```
2. `wc -l /tmp/hf.stderr` is `1` (single-line fallback warning).

## 5.4 Test execution checks

Run only touched/entrypoint-relevant suites:

```bash
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected:

1. Exit code `0`.
2. No failed tests.

## 5.5 Optional TS toolchain check (only if Node/npm available locally)

Run:

```bash
npm install
npm run typecheck
```

Expected: exit `0`.

If Node/npm is unavailable, do not block PR; document skipped optional check in PR description.

---

## 6) Definition of Done (PR acceptance)

PR is done only if all are true:

1. All files in section 4 exist and match contracts.
2. `hermes-fly --version/help/deploy --help` are byte-identical to baseline in default mode.
3. Hybrid fallback behavior is deterministic and single-warning-line.
4. New bats dispatcher tests pass.
5. No install/release scripts changed in this PR.
6. PR description includes:
- scope,
- verification commands run,
- exact outputs for fallback checks.

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-A1: add TS foundation scaffold and hybrid dispatcher in legacy-default mode
```

Recommended PR title:

```text
PR-A1 Foundation: TS scaffold + legacy-default hybrid dispatcher
```

---

## 8) Rollback

If any regression is detected post-merge:

1. Set `HERMES_FLY_IMPL_MODE=legacy` operationally (already default in this PR).
2. Revert this PR commit.
3. Re-run:

```bash
./hermes-fly --version
./hermes-fly help
tests/bats/bin/bats tests/integration.bats
```

Expected: baseline behavior restored.

---

## References

- [Commander.js documentation (ESM/TypeScript support)](https://github.com/tj/commander.js/blob/master/Readme.md)
- [TypeScript tsconfig module options for Node ESM](https://www.typescriptlang.org/docs/handbook/modules/guides/choosing-compiler-options)
- [TypeScript 5.9 release notes (updated tsc --init defaults)](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-9)
