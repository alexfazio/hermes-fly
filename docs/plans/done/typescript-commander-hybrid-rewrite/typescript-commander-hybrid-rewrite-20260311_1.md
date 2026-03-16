# PR-D2 Execution Plan: TypeScript `status` + `logs` Command Migration + Hybrid Parity Gate

Date: 2026-03-13  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312.md`  
Parent phase: Phase 3 (Migrate `status`, `logs`)  
Timebox: 120 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-d2-status-logs` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-d2-status-logs-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Implement the next hybrid migration slice by porting the existing app-scoped `status` and `logs` commands to TypeScript, wiring both into Commander, and proving deterministic parity against the committed `status` and `logs` baseline snapshots while keeping safe bash fallback behavior.

This PR migrates two commands only: `status` and `logs`.

Important contract clarification:

1. `status` is not a multi-app summary command. It is a single-app status view.
2. `logs` is not a structured table command. It is a direct log-stream/log-fetch wrapper for one app.
3. This PR must preserve those current public contracts exactly. Do not redesign them.

---

## 2) Scope

### In scope (must ship in this PR)

1. Extend the existing TS runtime to support app-scoped `status` and `logs`.
2. Reuse the existing PR-D1 TypeScript patterns:
- `src/adapters/process.ts`
- `src/adapters/flyctl.ts`
- `src/commands/list.ts`
- `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`
3. Add exact app-resolution parity for `status` and `logs`:
- `-a APP` when provided
- otherwise `current_app` from `config.yaml`
- otherwise the existing no-app error
4. Add TS `status` and `logs` command handlers and wire them in `src/cli.ts`.
5. Add runtime tests, hybrid bats tests, and hybrid-dispatch regression tests.
6. Add a deterministic verifier script for PR-D2.
7. Preserve PR-D1 verifier behavior unchanged.

### Out of scope (do not do in this PR)

1. No migration of `deploy`, `resume`, `doctor`, `destroy`, `help`, or `version`.
2. No multi-app `status` redesign.
3. No new shared table helper. `status` and `logs` must preserve their legacy rendering contracts.
4. No new CLI flags or option redesign for `status`/`logs`.
5. No default TS promotion changes. `status` and `logs` remain opt-in via allowlist.
6. No changes to parity baseline snapshot files:
- `tests/parity/baseline/status.*.snap`
- `tests/parity/baseline/logs.*.snap`
7. No changes to:
- `scripts/install.sh`
- `scripts/release-guard.sh`
- `tests/parity/scenarios/non_destructive_commands.list`

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm anchors before edits:

1. Hybrid dispatcher and TS allowlist gates exist:
- `hermes-fly:96-158`
- `hermes-fly:160-227`

2. The dispatcher already defines the current public `status`/`logs` contract:
- `hermes-fly:204-227`

3. TypeScript CLI currently wires only `version` and `list`:
- `src/cli.ts:1-32`

4. Existing TS runtime files to extend are present:
- `src/adapters/process.ts:1-53`
- `src/adapters/flyctl.ts:1-49`
- `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts:20-182`
- `src/commands/list.ts:1-47`

5. Legacy `status` contract exists:
- `lib/status.sh:52-90`
- `tests/status.bats:18-30`

6. Legacy `logs` contract exists:
- `lib/logs.sh:22-32`
- `tests/logs.bats:18-27`

7. App-resolution contract exists and must be mirrored exactly:
- `lib/config.sh:107-147`
- `lib/config.sh:235-264`

8. Existing parity manifest already captures the exact public command forms for this PR:
- `tests/parity/scenarios/non_destructive_commands.list:1-5`

9. Existing parity baselines already exist and are committed:
- `tests/parity/baseline/status.stdout.snap`
- `tests/parity/baseline/status.stderr.snap`
- `tests/parity/baseline/status.exit.snap`
- `tests/parity/baseline/logs.stdout.snap`
- `tests/parity/baseline/logs.stderr.snap`
- `tests/parity/baseline/logs.exit.snap`

10. Existing quality gates pass before starting:

```bash
npm run parity:check
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
npm run verify:pr-d1-list-command
tests/bats/bin/bats tests/status.bats tests/logs.bats tests/list-ts-hybrid.bats tests/hybrid-dispatch.bats tests/parity-harness.bats tests/integration.bats
```

If these are not true, resolve drift first.

---

## 4) Exact File Changes

Follow the slices in the order below. Do not invent additional architecture or rename files.

## 4.1 Update `package.json` scripts for PR-D2 test surface

Path: `package.json` (scripts block).  
Action: modify.

Required changes:

1. Add script:
- `"test:runtime-status": "tsx --test tests-ts/runtime/show-status.test.ts"`

2. Add script:
- `"test:runtime-logs": "tsx --test tests-ts/runtime/show-logs.test.ts"`

3. Add script:
- `"test:runtime-status-logs": "npm run test:runtime-status && npm run test:runtime-logs"`

4. Add script:
- `"verify:pr-d2-status-logs": "bash scripts/verify-pr-d2-status-logs.sh"`

5. Keep existing scripts unchanged:
- `build`
- `typecheck`
- `arch:ddd-boundaries`
- `test:domain-primitives`
- `test:runtime-list`
- `verify:pr-d1-list-command`
- `parity:capture`
- `parity:compare`
- `parity:check`

## 4.2 Reuse PR-D1 config-dir logic and add current-app resolution helper

Update:

1. `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`

Create:

1. `src/contexts/runtime/infrastructure/adapters/current-app-config.ts`
2. `src/commands/resolve-app.ts`

Required changes:

### `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`

1. Keep `list` behavior unchanged.
2. Export the existing config-dir helper so this PR reuses the same path resolution semantics instead of duplicating them:
- `resolveConfigDir`
3. Export the existing safe app-name validator so this PR reuses the same validation semantics instead of duplicating them:
- `isSafeAppName`
4. Do not change list output formatting or ordering in this PR.

### `src/contexts/runtime/infrastructure/adapters/current-app-config.ts`

1. Read `current_app:` from `${configDir}/config.yaml`, using the exported `resolveConfigDir`.
2. Validate `current_app` with the exported `isSafeAppName`.
3. Return `null` when:
- config file is missing
- `current_app:` is missing
- `current_app:` is empty
- `current_app:` fails validation
4. Do not write to config in this PR.

### `src/commands/resolve-app.ts`

1. Export a helper that mirrors bash `config_resolve_app` semantics exactly for `status` and `logs`.
2. Resolution order must be:
- `-a APP` from command args when present
- otherwise `current_app` from `current-app-config.ts`
- otherwise `null`
3. While scanning args:
- only `-a` is recognized
- all other args and flags are ignored
4. If `-a` is present without a value, treat it as unresolved and continue to the `current_app` fallback.
5. If `-a` appears multiple times, use the last parsed `-a` value to match legacy tolerance.
6. Do not introduce new option parsing rules in this file.

## 4.3 Extend low-level adapters for `status` and `logs`

Update:

1. `src/adapters/flyctl.ts`
2. `src/adapters/process.ts`

Required changes:

### `src/adapters/flyctl.ts`

1. Keep existing `getMachineState(appName)` behavior unchanged for PR-D1 `list`.
2. Extend `FlyctlPort` with:
- `getAppStatus(appName: string): Promise<{ ok: true; appName: string; status: string | null; hostname: string | null; machineState: string | null; region: string | null } | { ok: false; error: string }>`
- `getAppLogs(appName: string): Promise<{ stdout: string; stderr: string; exitCode: number }>`
3. `getAppStatus(appName)` must:
- run `fly status --app <app> --json`
- parse `app.name`
- parse `app.status`
- parse `app.hostname`
- parse the first machine `state`
- parse the first machine `region`
- return `{ ok: false, error: <message> }` on process error, non-zero exit, or JSON parse failure
4. Error message rules for `getAppStatus(appName)`:
- prefer raw `stderr.trim()` when non-empty
- otherwise use `stdout.trim()` when non-empty
- otherwise use `unknown error`
5. `getAppLogs(appName)` must:
- run `fly logs --app <app>`
- return raw `stdout`, `stderr`, and `exitCode`
- not parse, colorize, trim, or reformat output

### `src/adapters/process.ts`

1. Keep `ProcessResult` unchanged.
2. Preserve UTF-8 capture semantics exactly.
3. Do not normalize newlines or strip trailing newlines.
4. Do not print directly to the console.

## 4.4 Add status runtime port, use-case, and command handler

Create:

1. `src/contexts/runtime/application/ports/status-reader.port.ts`
2. `src/contexts/runtime/application/use-cases/show-status.ts`
3. `src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts`
4. `src/commands/status.ts`

Update:

1. `src/cli.ts`

Required behavior:

### `src/contexts/runtime/application/ports/status-reader.port.ts`

1. Export:
- `StatusDetails`
- `StatusReaderPort`
2. `StatusDetails` fields must be exactly:
- `appName`
- `status`
- `machine`
- `region`
- `hostname`

### `src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts`

1. Implement `StatusReaderPort` using `FlyctlAdapter`.
2. Placeholder mapping must mirror `lib/status.sh:84-87`:
- missing app name -> use the requested app name
- missing status -> `unknown`
- missing machine state -> `unknown`
- missing region -> `unknown`
- missing hostname -> `null`
3. On fly/runtime failure, return an error result carrying the exact error message string from `getAppStatus`.

### `src/contexts/runtime/application/use-cases/show-status.ts`

1. Export `ShowStatusUseCase`.
2. `execute(appName: string)` must return a discriminated union:
- `{ kind: "ok"; details: StatusDetails }`
- `{ kind: "error"; message: string }`
3. Do not add retries or fallback behavior in the use-case.

### `src/commands/status.ts`

1. Export `runStatusCommand(args: string[], options?: ...)`.
2. Resolve the app name using `resolve-app.ts`.
3. If no app can be resolved, write exactly this line to `stderr` and return `1`:

```text
[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.
```

4. On success, write output to `stderr` only, with exact line content and spacing matching the existing success contract:

```text
[info] App:     test-app
[info] Status:  started
[info] Machine: started
[info] Region:  ord
✓ URL:     https://test-app.fly.dev
```

5. URL line rules:
- include the `✓ URL:     ...` line only when hostname is non-null and non-empty
- omit the line completely when hostname is missing
6. On status-read failure, write exactly this error pattern to `stderr` and return `1`:

```text
[error] Failed to get status for app '<app>': <error>
```

7. Successful `status` writes nothing to `stdout` and returns `0`.

### `src/cli.ts`

1. Register `status` as a subcommand.
2. For `status`, set:
- `.helpOption(false)`
- `.allowUnknownOption(true)`
- `.allowExcessArguments(true)`
3. Delegate all raw post-command args to `runStatusCommand(args)`.
4. Do not change the existing `version` or `list` command behavior.

## 4.5 Add logs runtime port, use-case, and command handler

Create:

1. `src/contexts/runtime/application/ports/logs-reader.port.ts`
2. `src/contexts/runtime/application/use-cases/show-logs.ts`
3. `src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts`
4. `src/commands/logs.ts`

Update:

1. `src/cli.ts`

Required behavior:

### `src/contexts/runtime/application/ports/logs-reader.port.ts`

1. Export:
- `LogsReadResult`
- `LogsReaderPort`
2. `LogsReadResult` fields must be exactly:
- `stdout`
- `stderr`
- `exitCode`

### `src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts`

1. Implement `LogsReaderPort` using `FlyctlAdapter.getAppLogs(appName)`.
2. Do not parse or reformat log lines.
3. Return the raw process result unchanged.

### `src/contexts/runtime/application/use-cases/show-logs.ts`

1. Export `ShowLogsUseCase`.
2. `execute(appName: string)` must return the raw `LogsReadResult`.
3. Do not add retries, parsing, or synthetic log records.

### `src/commands/logs.ts`

1. Export `runLogsCommand(args: string[], options?: ...)`.
2. Resolve the app name using `resolve-app.ts`.
3. If no app can be resolved, write exactly this line to `stderr` and return `1`:

```text
[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.
```

4. On success:
- write raw `stdout` exactly as returned by `LogsReaderPort`
- write raw `stderr` exactly as returned by `LogsReaderPort`
  (important: preserve non-empty stderr on success so legacy warning/info lines are not dropped)
- return `0`
5. On fly/log retrieval failure:
- define failure strictly as `exitCode !== 0` from `LogsReaderPort`
- do not forward the fly stderr text
- write exactly this line to `stderr`

```text
[error] Failed to fetch logs for app '<app>'
```

- return `1`
6. Ignore all args except `-a APP`, matching the dispatcher-compatible legacy contract.

### `src/cli.ts`

1. Register `logs` as a subcommand.
2. For `logs`, set:
- `.helpOption(false)`
- `.allowUnknownOption(true)`
- `.allowExcessArguments(true)`
3. Delegate all raw post-command args to `runLogsCommand(args)`.
4. Do not change the existing `version`, `list`, or `status` command behavior.

## 4.6 Add runtime, hybrid, and dispatch tests for PR-D2

Create:

1. `tests-ts/runtime/show-status.test.ts`
2. `tests-ts/runtime/show-logs.test.ts`
3. `tests/status-ts-hybrid.bats`
4. `tests/logs-ts-hybrid.bats`
5. `tests/verify-pr-d2-status-logs.bats`

Update:

1. `tests/hybrid-dispatch.bats`

Required tests:

### `tests-ts/runtime/show-status.test.ts`

1. Status reader/use-case returns:
- requested app name
- `unknown` placeholders for missing status, machine, region
- `null` hostname when missing
2. Status reader/use-case preserves the exact fly error string for failure results.
3. `resolve-app.ts` parity cases:
- `-a APP` wins over current app
- current app is used when `-a` is absent
- unrelated args are ignored
- `-a` without a value falls back to current app
- unresolved app returns `null`

### `tests-ts/runtime/show-logs.test.ts`

1. Success path returns raw `stdout`, raw `stderr`, and exit `0` exactly as returned by the port.
2. Failure path preserves non-zero exit code from the adapter.
3. `runLogsCommand` writes the legacy failure line:
- `[error] Failed to fetch logs for app 'bad-app'`
4. `runLogsCommand` ignores unknown args and only uses `-a APP`.
5. `-a` without value falls back to current app.
6. repeated `-a` uses the last value.
7. Success with non-empty stderr must still be passthrough if `exitCode` is `0`.
8. Failure case where adapter returns `exitCode=1` and stderr non-empty must return `1` and print the failure contract line.

### `tests/status-ts-hybrid.bats`

1. Allowlisted TS `status -a test-app` path matches committed parity baseline files exactly:
- stdout == `tests/parity/baseline/status.stdout.snap`
- stderr == `tests/parity/baseline/status.stderr.snap`
- exit == `tests/parity/baseline/status.exit.snap`
2. Current-app fallback case matches the same baseline:
- seed with `config_save_app "test-app" "ord"`
- run `./hermes-fly status`
3. Missing app selection case:
- empty config
- run `./hermes-fly status`
- exit `1`
- stdout empty
- stderr exactly:

```text
[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.
```

4. Fly failure case:
- `MOCK_FLY_STATUS=fail`
- run `./hermes-fly status -a bad-app`
- exit `1`
- stdout empty
- stderr exactly:

```text
[error] Failed to get status for app 'bad-app': Error: app not found
```

5. Dist-missing fallback still works for allowlisted `status` with:
- exit `0`
- first stderr line:

```text
Warning: TS implementation unavailable for command 'status'; falling back to legacy
```

- remaining stderr/stdout/exit match legacy status output for the same fixture

### `tests/logs-ts-hybrid.bats`

1. Allowlisted TS `logs -a test-app` path matches committed parity baseline files exactly:
- stdout == `tests/parity/baseline/logs.stdout.snap`
- stderr == `tests/parity/baseline/logs.stderr.snap`
- exit == `tests/parity/baseline/logs.exit.snap`
2. Current-app fallback case matches the same baseline:
- seed with `config_save_app "test-app" "ord"`
- run `./hermes-fly logs`
3. Missing app selection case:
- empty config
- run `./hermes-fly logs`
- exit `1`
- stdout empty
- stderr exactly:

```text
[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.
```

4. Fly failure case:
- `MOCK_FLY_LOGS=fail`
- run `./hermes-fly logs -a bad-app`
- exit `1`
- stdout empty
- stderr exactly:

```text
[error] Failed to fetch logs for app 'bad-app'
```

5. Dist-missing fallback still works for allowlisted `logs` with:
- exit `0`
- first stderr line:

```text
Warning: TS implementation unavailable for command 'logs'; falling back to legacy
```

- remaining stdout/stderr/exit match legacy logs output for the same fixture

### `tests/hybrid-dispatch.bats`

1. Add direct routing checks for `status`:
- hybrid mode with `HERMES_FLY_TS_COMMANDS=status` uses dist runtime (proved with temporary shim replacement of `dist/cli.js` that prints `[marker] TS runtime invoked` and exits `0`)
- keep legacy output parity check with the real `dist/cli.js` present in a separate step
- hybrid mode with `HERMES_FLY_TS_COMMANDS=logs` keeps `status` on legacy
- prove the non-allowlisted legacy path by removing `dist/cli.js` and asserting:
  - no TS fallback warning is printed
  - output still matches the legacy `status` contract
2. Add direct routing checks for `logs`:
- hybrid mode with `HERMES_FLY_TS_COMMANDS=logs` uses dist runtime (proved with temporary shim replacement of `dist/cli.js` that prints `[marker] TS runtime invoked` and exits `0`)
- keep legacy output parity check with the real `dist/cli.js` present in a separate step
- hybrid mode with `HERMES_FLY_TS_COMMANDS=status` keeps `logs` on legacy
- prove the non-allowlisted legacy path by removing `dist/cli.js` and asserting:
  - no TS fallback warning is printed
  - output still matches the legacy `logs` contract
3. Add argument-parity checks proving that TS mode ignores unknown args the same way legacy does for:
- `status --unknown-flag -a test-app`
- `logs --unknown-flag -a test-app`
- `status -a test-app --help`
- `logs -a test-app --help`
- `status -h`
- `status -V`
- `logs -h`
- `logs -V`

### `tests/verify-pr-d2-status-logs.bats`

1. Assert all required files for PR-D2 exist.
2. Assert `./scripts/verify-pr-d2-status-logs.sh` exits `0` and prints:

```text
PR-D2 status/logs verification passed.
```

3. Assert the verifier script includes checks for:
- `status -a test-app`
- `logs -a test-app`
- current-app fallback for both commands
- missing-app error for both commands
- dist-missing fallback for both commands
- script-level assertions are structural, not just string presence; assert each listed item appears as an executed assertion.
- In the test file, check for concrete commands such as:
  - `if ! diff -u ...status.stdout.snap ...; then` and `if ! diff -u ...status.stderr.snap ...; then`
  - `if ! diff -u ...logs.stdout.snap ...; then` and `if ! diff -u ...logs.stderr.snap ...; then`
  - `if ! grep -q` checks for both success and failure messages for:
    - `status` missing app
    - `logs` missing app
    - `status -a bad-app` with `MOCK_FLY_STATUS=fail`
    - `logs -a bad-app` with `MOCK_FLY_LOGS=fail`
  - `if ! diff -u` checks using temp files captured from:
    - full status command output (stdout and stderr) under dist-missing fallback
    - full logs command output (stdout and stderr) under dist-missing fallback

## 4.7 Add deterministic verifier script for PR-D2

Create:

1. `scripts/verify-pr-d2-status-logs.sh` (executable)

Script steps:

1. Verify all required new and modified files exist.
2. Run:
- `npm run build`
- `npm run typecheck`
- `npm run arch:ddd-boundaries`
- `npm run test:domain-primitives`
- `npm run test:runtime-status-logs`
3. Run:
- `tests/bats/bin/bats tests/status-ts-hybrid.bats tests/logs-ts-hybrid.bats tests/verify-pr-d2-status-logs.bats tests/hybrid-dispatch.bats tests/status.bats tests/logs.bats`
4. Run direct deterministic parity assertions for the allowlisted TS success paths:
- `status -a test-app`
- `logs -a test-app`
5. Run direct deterministic parity assertions for current-app fallback:
- `status`
- `logs`
after seeding `current_app` via `config_save_app "test-app" "ord"`.
6. Run direct error assertions for:
- `status` with no app available
- `logs` with no app available
- `status -a bad-app` with `MOCK_FLY_STATUS=fail`
- `logs -a bad-app` with `MOCK_FLY_LOGS=fail`
7. Run dist-missing fallback assertions for:
- `status`
- `logs`
8. Run:
- `npm run verify:pr-d1-list-command`
9. Print `PR-D2 status/logs verification passed.` only on success.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f src/contexts/runtime/infrastructure/adapters/current-app-config.ts
test -f src/commands/resolve-app.ts
test -f src/contexts/runtime/application/ports/status-reader.port.ts
test -f src/contexts/runtime/application/use-cases/show-status.ts
test -f src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts
test -f src/commands/status.ts
test -f src/contexts/runtime/application/ports/logs-reader.port.ts
test -f src/contexts/runtime/application/use-cases/show-logs.ts
test -f src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts
test -f src/commands/logs.ts
test -f tests-ts/runtime/show-status.test.ts
test -f tests-ts/runtime/show-logs.test.ts
test -f tests/status-ts-hybrid.bats
test -f tests/logs-ts-hybrid.bats
test -f tests/verify-pr-d2-status-logs.bats
test -f scripts/verify-pr-d2-status-logs.sh
```

Expected: all exit `0`.

## 5.2 TypeScript build and architecture checks

Run:

```bash
npm run build
npm run typecheck
npm run arch:ddd-boundaries
```

Expected: all exit `0`.

## 5.3 Runtime unit tests

Run:

```bash
npm run test:runtime-status
npm run test:runtime-logs
```

Expected: exit `0` and all test cases pass.

## 5.4 Hybrid TS `status` parity against committed baseline

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status -a test-app >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/exit"'
diff -u tests/parity/baseline/status.stdout.snap "${tmp}/out"
diff -u tests/parity/baseline/status.stderr.snap "${tmp}/err"
diff -u tests/parity/baseline/status.exit.snap "${tmp}/exit"
```

Expected: all diffs exit `0`.

## 5.5 Hybrid TS `logs` parity against committed baseline

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs -a test-app >"${TMP_ROOT}/out" 2>"${TMP_ROOT}/err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/exit"'
diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/out"
diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/err"
diff -u tests/parity/baseline/logs.exit.snap "${tmp}/exit"
```

Expected: all diffs exit `0`.

## 5.6 Current-app fallback parity (positive and edge cases)

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status >"${TMP_ROOT}/status.out" 2>"${TMP_ROOT}/status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/status.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs >"${TMP_ROOT}/logs.out" 2>"${TMP_ROOT}/logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/logs.exit"'
diff -u tests/parity/baseline/status.stdout.snap "${tmp}/status.out"
diff -u tests/parity/baseline/status.stderr.snap "${tmp}/status.err"
diff -u tests/parity/baseline/status.exit.snap "${tmp}/status.exit"
diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/logs.out"
diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/logs.err"
diff -u tests/parity/baseline/logs.exit.snap "${tmp}/logs.exit"
```

Expected: all checks exit `0`.

## 5.6a Current-app edge-case resolution (canonical no-app matrix)

Run:

```bash
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'source ./lib/config.sh; \
    printf "" >"${TMP_ROOT}/config/config.yaml"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status >"${TMP_ROOT}/empty_status.out" 2>"${TMP_ROOT}/empty_status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/empty_status.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs >"${TMP_ROOT}/empty_logs.out" 2>"${TMP_ROOT}/empty_logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/empty_logs.exit"; \
    printf "current_app: bad name\n" >"${TMP_ROOT}/config/config.yaml"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status >"${TMP_ROOT}/badname_status.out" 2>"${TMP_ROOT}/badname_status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/badname_status.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs >"${TMP_ROOT}/badname_logs.out" 2>"${TMP_ROOT}/badname_logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/badname_logs.exit"; \
    rm -f "${TMP_ROOT}/config/config.yaml"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status >"${TMP_ROOT}/missing_file_status.out" 2>"${TMP_ROOT}/missing_file_status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/missing_file_status.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs >"${TMP_ROOT}/missing_file_logs.out" 2>"${TMP_ROOT}/missing_file_logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/missing_file_logs.exit"'
test "$(cat "${tmp}/empty_status.exit")" = "1"
test "$(cat "${tmp}/empty_logs.exit")" = "1"
test "$(cat "${tmp}/badname_status.exit")" = "1"
test "$(cat "${tmp}/badname_logs.exit")" = "1"
test "$(cat "${tmp}/missing_file_status.exit")" = "1"
test "$(cat "${tmp}/missing_file_logs.exit")" = "1"
for artifact in empty_status empty_logs badname_status badname_logs missing_file_status missing_file_logs; do
  test -z "$(cat "${tmp}/${artifact}.out")"
done
test "$(cat "${tmp}/empty_status.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
test "$(cat "${tmp}/empty_logs.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
test "$(cat "${tmp}/badname_status.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
test "$(cat "${tmp}/badname_logs.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
test "$(cat "${tmp}/missing_file_status.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
test "$(cat "${tmp}/missing_file_logs.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
```

Expected: all checks exit `0`.

## 5.7 No-app smoke parity

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status >"${TMP_ROOT}/status.out" 2>"${TMP_ROOT}/status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/status.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs >"${TMP_ROOT}/logs.out" 2>"${TMP_ROOT}/logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/logs.exit"'
test ! -s "${tmp}/status.out"
test ! -s "${tmp}/logs.out"
test "$(cat "${tmp}/status.exit")" = "1"
test "$(cat "${tmp}/logs.exit")" = "1"
test "$(cat "${tmp}/status.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
test "$(cat "${tmp}/logs.err")" = "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first."
```

Expected: all checks exit `0`.

Implementation note:

- This is a compact smoke check complementary to `5.6a` and should not replace the canonical matrix there.

## 5.8 Fly failure error parity

Run:

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'MOCK_FLY_STATUS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status -a bad-app >"${TMP_ROOT}/status.out" 2>"${TMP_ROOT}/status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/status.exit"; \
    MOCK_FLY_LOGS=fail HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs -a bad-app >"${TMP_ROOT}/logs.out" 2>"${TMP_ROOT}/logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/logs.exit"'
test ! -s "${tmp}/status.out"
test ! -s "${tmp}/logs.out"
test "$(cat "${tmp}/status.exit")" = "1"
test "$(cat "${tmp}/logs.exit")" = "1"
test "$(cat "${tmp}/status.err")" = "[error] Failed to get status for app 'bad-app': Error: app not found"
test "$(cat "${tmp}/logs.err")" = "[error] Failed to fetch logs for app 'bad-app'"
```

Expected: all checks exit `0`.

## 5.9 Allowlisted fallback when artifact missing

Run:

```bash
tmp="$(mktemp -d)"
mkdir -p "${tmp}/config" "${tmp}/logs"
PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" TMP_ROOT="${tmp}" \
  bash -c 'source ./lib/config.sh; config_save_app "test-app" "ord"; rm -f dist/cli.js; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=status ./hermes-fly status -a test-app >"${TMP_ROOT}/status.out" 2>"${TMP_ROOT}/status.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/status.exit"; \
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs ./hermes-fly logs -a test-app >"${TMP_ROOT}/logs.out" 2>"${TMP_ROOT}/logs.err"; \
    printf "%s\n" "$?" >"${TMP_ROOT}/logs.exit"'
head -n 1 "${tmp}/status.err"
head -n 1 "${tmp}/logs.err"
test "$(cat "${tmp}/status.exit")" = "0"
test "$(cat "${tmp}/logs.exit")" = "0"
test "$(head -n 1 "${tmp}/status.err")" = "Warning: TS implementation unavailable for command 'status'; falling back to legacy"
test "$(head -n 1 "${tmp}/logs.err")" = "Warning: TS implementation unavailable for command 'logs'; falling back to legacy"
diff -u tests/parity/baseline/status.stdout.snap "${tmp}/status.out"
tail -n +2 "${tmp}/status.err" > "${tmp}/status.err.rest"
diff -u tests/parity/baseline/status.stderr.snap "${tmp}/status.err.rest"
diff -u tests/parity/baseline/logs.stdout.snap "${tmp}/logs.out"
tail -n +2 "${tmp}/logs.err" > "${tmp}/logs.err.rest"
diff -u tests/parity/baseline/logs.stderr.snap "${tmp}/logs.err.rest"
```

Expected: all checks exit `0`.

## 5.10 Hybrid dispatch regression checks

Run:

```bash
tests/bats/bin/bats tests/hybrid-dispatch.bats
```

Expected:

1. `status` only uses TS when allowlisted.
2. `logs` only uses TS when allowlisted.
3. Non-allowlisted `status` and `logs` do not print fallback warnings when `dist/cli.js` is missing, proving they stayed on legacy.
4. Unknown args do not cause Commander parsing regressions for `status` or `logs`.

## 5.11 One-command verifier

Run:

```bash
./scripts/verify-pr-d2-status-logs.sh
```

Expected: exit `0`, prints `PR-D2 status/logs verification passed.`

## 5.12 Regression guard for prior gate

Run:

```bash
npm run verify:pr-d1-list-command
```

Expected: exit `0`, prints `PR-D1 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. `status` is implemented in TS as a single-app status command.
2. `logs` is implemented in TS as a single-app raw log command.
3. `status -a test-app` matches the committed `status` parity baseline exactly.
4. `logs -a test-app` matches the committed `logs` parity baseline exactly.
5. `status` with current-app fallback matches the same success baseline.
6. `logs` with current-app fallback matches the same success baseline.
7. Missing-app errors for both commands match the current legacy error line exactly.
8. Fly failure errors for both commands match the current legacy error line exactly.
9. Dist-missing fallback for both commands remains one-warning plus legacy output.
10. Existing PR-D1 `list` verifier remains green.
11. Existing CLI behavior remains unchanged outside allowlisted `status` and `logs`.
12. No changes in:
- `scripts/install.sh`
- `scripts/release-guard.sh`
- `tests/parity/scenarios/non_destructive_commands.list`
- `tests/parity/baseline/status.*.snap`
- `tests/parity/baseline/logs.*.snap`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-D2: migrate status and logs commands to TypeScript runtime with parity gate
```

Recommended PR title:

```text
PR-D2 Phase 3: TypeScript status and logs commands + hybrid parity verification
```

Recommended PR checklist text:

1. Ran `npm run build`
2. Ran `npm run typecheck`
3. Ran `npm run arch:ddd-boundaries`
4. Ran `npm run test:domain-primitives`
5. Ran `npm run test:runtime-status`
6. Ran `npm run test:runtime-logs`
7. Verified hybrid TS `status -a test-app` output matches `tests/parity/baseline/status.*.snap`
8. Verified hybrid TS `logs -a test-app` output matches `tests/parity/baseline/logs.*.snap`
9. Verified current-app fallback parity for both commands
10. Verified missing-app and fly-failure error strings for both commands
11. Verified allowlisted fallback path when `dist/cli.js` is missing
12. Ran `tests/bats/bin/bats tests/status-ts-hybrid.bats tests/logs-ts-hybrid.bats tests/verify-pr-d2-status-logs.bats tests/hybrid-dispatch.bats tests/status.bats tests/logs.bats`
13. Ran `./scripts/verify-pr-d2-status-logs.sh`
14. Ran `npm run verify:pr-d1-list-command`

---

## 8) Rollback

If regressions are found:

1. Revert the PR-D2 commit.
2. Re-run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
npm run verify:pr-d1-list-command
tests/bats/bin/bats tests/status.bats tests/logs.bats tests/list-ts-hybrid.bats tests/hybrid-dispatch.bats tests/parity-harness.bats tests/integration.bats
```

Expected: behavior returns to PR-D1 baseline.

---

## References

- [Commander.js documentation](https://github.com/tj/commander.js)
- [Node.js child_process documentation](https://nodejs.org/api/child_process.html)
- [Bats-core documentation](https://bats-core.readthedocs.io/)
- [GNU diffutils manual](https://www.gnu.org/software/diffutils/manual/)

## Execution Log

### Slice 1: package-scripts-pr-d2
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted
- [x] S5 WRITE_TEST: `tests/verify-pr-d2-status-logs.bats` (file-existence + script-content checks)
- [x] S6 CONFIRM_RED: test fails as expected (script did not exist)
- [x] S7 IMPLEMENT: `package.json` (added `test:runtime-status`, `test:runtime-logs`, `test:runtime-status-logs`, `verify:pr-d2-status-logs`)
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: current-app-resolution-parity
- [x] S4 ANALYZE_CRITERIA: 5 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/show-status.test.ts` (resolve-app + current-app-config suites)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: exported `isSafeAppName` from `fly-deployment-registry.ts`; created `src/contexts/runtime/infrastructure/adapters/current-app-config.ts`, `src/commands/resolve-app.ts`
- [x] S8 RUN_TESTS: pass (1 iteration — 13/13)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 3: low-level-flyctl-status-and-logs-adapter
- [x] S4 ANALYZE_CRITERIA: 6 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/show-status.test.ts` (FlyctlAdapter.getAppStatus + getAppLogs suites)
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: extended `FlyctlPort` interface and `FlyctlAdapter` in `src/adapters/flyctl.ts` with `getAppStatus` and `getAppLogs`; added `AppStatusOk`, `AppStatusError`, `AppStatusResult` types
- [x] S8 RUN_TESTS: pass (1 iteration — 20/20)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: status-use-case-and-command
- [x] S4 ANALYZE_CRITERIA: 8 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/show-status.test.ts` (ShowStatusUseCase, FlyStatusReader, runStatusCommand); `tests/status-ts-hybrid.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/contexts/runtime/application/ports/status-reader.port.ts`, `src/contexts/runtime/application/use-cases/show-status.ts`, `src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts`, `src/commands/status.ts`; wired into `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iteration — 28/28 TS + 5/5 bats)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 5: logs-use-case-and-command
- [x] S4 ANALYZE_CRITERIA: 7 criteria extracted
- [x] S5 WRITE_TEST: `tests-ts/runtime/show-logs.test.ts`; `tests/logs-ts-hybrid.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: `src/contexts/runtime/application/ports/logs-reader.port.ts`, `src/contexts/runtime/application/use-cases/show-logs.ts`, `src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts`, `src/commands/logs.ts`; wired into `src/cli.ts`
- [x] S8 RUN_TESTS: pass (1 iteration — 11/11 TS + 5/5 bats)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 6: hybrid-dispatch-regression-lock
- [x] S4 ANALYZE_CRITERIA: 5 criteria extracted
- [x] S5 WRITE_TEST: PR-D2 tests appended to `tests/hybrid-dispatch.bats` (status/logs routing, argument parity); `tests/status-ts-hybrid.bats`, `tests/logs-ts-hybrid.bats`
- [x] S6 CONFIRM_RED: test fails as expected
- [x] S7 IMPLEMENT: bats tests in `tests/hybrid-dispatch.bats`; git submodules initialized (`git submodule update --init --recursive`)
- [x] S8 RUN_TESTS: pass (2 iterations — `|| true` removal fix on iteration 2; 67/67 bats)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: S8a — `|| true` before `printf "%s\n" "$?"` was masking exit codes in inner bash; fix was to remove `|| true` entirely since inner bash does not inherit `set -e`

### Slice 7: pr-d2-verifier-script
- [x] S4 ANALYZE_CRITERIA: 7 criteria extracted
- [x] S5 WRITE_TEST: `tests/verify-pr-d2-status-logs.bats` (9 tests: file existence, script exit/output, structural grep checks)
- [x] S6 CONFIRM_RED: test fails as expected (script did not exist)
- [x] S7 IMPLEMENT: `scripts/verify-pr-d2-status-logs.sh` (executable; file checks, npm build/typecheck/arch/test, bats suite, direct parity assertions, current-app fallback, no-app errors, mock-fail errors, dist-missing fallback, PR-D1 regression guard)
- [x] S8 RUN_TESTS: pass (1 iteration — 9/9 bats)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: `tests/verify-pr-d2-status-logs.bats` excluded from the script's own bats run to avoid infinite recursion (the bats file's test 2 calls the script)

### VERIFY_ALL
- Test suite: pass (1 iteration — 28 TS status tests + 11 TS logs tests + 67 bats hybrid/dispatch + 9 bats verifier; full verifier script exits 0)
- Criteria walk: all satisfied — `bash scripts/verify-pr-d2-status-logs.sh` exits 0 and prints "PR-D2 status/logs verification passed."
