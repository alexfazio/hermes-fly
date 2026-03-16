# PR-D2 REVIEW-2 Implementation Report

**Plan**: `typescript-commander-hybrid-rewrite-20260311_1_REVIEW_2.md`
**Branch**: `worktree-majestic-hatching-sky`
**Date**: 2026-03-13
**Status**: COMPLETE — all 5 slices implemented, all verification criteria satisfied

---

## Summary

PR-D2 REVIEW-2 addressed 5 review findings on the TypeScript `status`/`logs` migration:

| Slice | Finding | Resolution |
|-------|---------|------------|
| A | `logs` used batch execution (`getLogs`) instead of true streaming | Added `runStreaming`, `streamAppLogs`, `streamLogs`, `stream()` — full streaming pipeline with deterministic chunk policy |
| B | `resolveApp` retained stale `appName` when `-a` had invalid/missing next token | Reset `appName = null` when `-a` has no valid argument |
| C | `verify-pr-d2-status-logs.bats` not included in verifier's bats invocation; pipeline masked verifier exit code | Added bats file to invocation; rewrote "exits 0" test to use temp-file capture |
| D | 4 `grep -qvF ... \|\| true` patterns in hybrid-dispatch.bats were non-assertive (always pass) | Replaced with `if grep -qF ...; then exit 1; fi` deterministic blocks |
| E | No integration proof that streaming produces output incrementally before process exit | Added bats test with slow mock fly that asserts `line-1` visible after 0.2s while process still running |

---

## Commit History

```
6216611 test(pr-d2-review2): add hybrid incremental streaming proof
cae46f7 test(pr-d2-review2): harden hybrid-dispatch negative assertions
b55898b test(pr-d2-review2): harden verifier and hybrid-dispatch negative assertions
f688654 fix(pr-d2-review2): implement streaming logs runtime and deterministic resolve-app behavior
11f7b5f test(pr-d2-review2): add failing tests for logs streaming and resolve-app edge cases
```

---

## Files Changed

### New/Modified (implementation)

| File | Change |
|------|--------|
| `src/adapters/process.ts` | Added `onStdoutChunk?/onStderrChunk?` to `ProcessRunOptions`; added `runStreaming` to interface and `NodeProcessRunner` |
| `src/adapters/flyctl.ts` | Added `streamAppLogs` to `FlyctlPort` and `FlyctlAdapter` |
| `src/contexts/runtime/application/ports/logs-reader.port.ts` | Added `StreamLogsOptions`, `streamLogs` to `LogsReaderPort` |
| `src/contexts/runtime/application/use-cases/show-logs.ts` | Added `stream()` method |
| `src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts` | Implemented `streamLogs` delegating to `flyctl.streamAppLogs` |
| `src/commands/logs.ts` | Switched from `execute()` to `stream()` with deterministic chunk policy |
| `src/commands/resolve-app.ts` | Reset `appName = null` when `-a` has invalid/missing next token |
| `scripts/verify-pr-d2-status-logs.sh` | Added `tests/verify-pr-d2-status-logs.bats` to bats invocation |

### New/Modified (tests)

| File | Change |
|------|--------|
| `tests-ts/runtime/show-logs.test.ts` | 4 streaming path tests; 1 resolve-app edge test; updated all mocks to include `streamLogs` |
| `tests-ts/runtime/show-status.test.ts` | 3 resolve-app edge tests for trailing `-a` behavior |
| `tests/verify-pr-d2-status-logs.bats` | Replaced pipeline-based "exits 0" test; added "bats invocation includes" grep-count test; added 8 structural checks |
| `tests/hybrid-dispatch.bats` | Replaced 4 `\|\| true` non-assertive patterns with deterministic failure assertions |
| `tests/logs-ts-hybrid.bats` | Added incremental streaming integration test with slow mock fly |

---

## Streaming Architecture (Slice A)

### Chunk Policy

```
fly logs → onStdoutChunk → process.stdout.write(chunk)  [immediate]
        → onStderrChunk → stderrBuffer.push(chunk)       [buffered]

On exit code 0:   flush stderrBuffer → process.stderr.write
On exit code ≠ 0: drop stderrBuffer, emit [error] Failed to fetch logs for app '<app>'
On spawn error:   emit [error] Failed to fetch logs for app '<app>'
```

### Interface Chain

```
ProcessRunner.runStreaming()
  → FlyctlAdapter.streamAppLogs()
    → FlyLogsReader.streamLogs()
      → ShowLogsUseCase.stream()
        → runLogsCommand() [logs.ts]
```

---

## Verification Results

### 7.1 Build and core checks
- `npm run build` → exit 0
- `npm run typecheck` → exit 0
- `npm run arch:ddd-boundaries` → 0 violations (31 modules, 20 dependencies)

### 7.2 Runtime unit tests
- `npm run test:runtime-status` → 31 tests pass
- `npm run test:runtime-logs` → 16 tests pass

### 7.3 Focused edge-pattern checks (rg)
All 5 patterns found:
- `resolveApp(["-a", "first", "-a"]` in show-status.test.ts ✓
- `resolveApp(["-a", "--unknown-flag"]` in show-status.test.ts ✓
- `spawn/runner rejection` in show-logs.test.ts ✓
- `non-zero exit after stdout chunks` in show-logs.test.ts ✓
- `streams output incrementally before process exit` in logs-ts-hybrid.bats ✓

### 7.4 Bats suites
- `status-ts-hybrid.bats`: 5/5 pass
- `logs-ts-hybrid.bats`: 6/6 pass (including new streaming test)
- `hybrid-dispatch.bats`: 57/57 pass
- `status.bats` + `logs.bats`: 13/13 pass
- `verify-pr-d2-status-logs.bats` structural: 9/9 pass

### 7.5 Verifier command
- `scripts/verify-pr-d2-status-logs.sh` wiring verified: `verify-pr-d2-status-logs.bats` appears ≥ 2 times (required_files + bats invocation block)

### 7.6 No-regression gates
- `npm run verify:pr-d1-list-command` → 102 tests pass
- `npm run parity:check` → Parity compare passed

### Baseline snapshots
- No modifications to `tests/parity/baseline/` — verified via `git diff --name-only`
