# PR-D2 REVIEW-1 Execution Plan: Status/Logs Regression Remediation

Date: 2026-03-13  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-20260311_1.md`  
Target PR: `#11` (`worktree-majestic-hatching-sky -> main`)  
Assignee profile: Junior developer  
Target branch: `worktree-majestic-hatching-sky` (do not switch branches)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-d2-status-logs-review-1-implementation-report.md`

---

## 1) Issue Summary (from static PR review)

This review remediation addresses only the actionable findings discovered in PR-D2 static analysis:

1. High: TS `logs` execution path is buffered and can break live-stream/pass-through behavior.
2. Medium: `resolve-app.ts` does not fully mirror legacy `config_resolve_app` semantics for repeated/edge `-a` inputs.
3. Low: `tests/verify-pr-d2-status-logs.bats` can false-pass verifier failure because of a pipeline masking exit code.
4. Low: `scripts/verify-pr-d2-status-logs.sh` does not execute `tests/verify-pr-d2-status-logs.bats`.
5. Low: two negative assertions in `tests/hybrid-dispatch.bats` are non-assertive and can miss unexpected fallback warnings.

---

## 2) Scope

### In scope (must ship in this review PR)

1. Fix `logs` command runtime to preserve stream-like behavior and avoid end-of-process-only output writes.
2. Fix `resolve-app.ts` edge parsing so repeated `-a` and missing-value cases match intended legacy tolerance.
3. Harden PR-D2 verifier and verifier tests so failures cannot be masked.
4. Harden hybrid-dispatch negative assertions for non-allowlisted status/logs fallback checks.
5. Add deterministic regression tests for each fixed finding.

### Out of scope (do not change)

1. No migration of commands beyond `status` and `logs`.
2. No change to public command names, flags, or help text.
3. No change to parity baseline snapshot files:
   - `tests/parity/baseline/status.*.snap`
   - `tests/parity/baseline/logs.*.snap`
4. No changes to:
   - `scripts/install.sh`
   - `scripts/release-guard.sh`
   - `tests/parity/scenarios/non_destructive_commands.list`
5. No redesign of DDD package structure.

---

## 3) Preconditions

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/majestic-hatching-sky
```

Confirm anchor files exist before edits:

1. `src/adapters/process.ts`
2. `src/adapters/flyctl.ts`
3. `src/commands/logs.ts`
4. `src/commands/resolve-app.ts`
5. `src/contexts/runtime/application/ports/logs-reader.port.ts`
6. `src/contexts/runtime/application/use-cases/show-logs.ts`
7. `src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts`
8. `tests-ts/runtime/show-logs.test.ts`
9. `tests-ts/runtime/show-status.test.ts`
10. `tests/logs-ts-hybrid.bats`
11. `tests/hybrid-dispatch.bats`
12. `tests/verify-pr-d2-status-logs.bats`
13. `scripts/verify-pr-d2-status-logs.sh`
14. Legacy contract references:
    - `lib/config.sh:235-264`
    - `lib/logs.sh:26-32`
    - `lib/fly-helpers.sh:224-228`

---

## 4) Exact File Changes

Implement in order. Follow strict TDD per slice (write failing test first, then minimal code, then green).

### 4.1 Slice A - Fix `logs` buffered-output regression

#### Files to update

1. `src/adapters/process.ts`
2. `src/adapters/flyctl.ts`
3. `src/contexts/runtime/application/ports/logs-reader.port.ts`
4. `src/contexts/runtime/application/use-cases/show-logs.ts`
5. `src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts`
6. `src/commands/logs.ts`
7. `tests-ts/runtime/show-logs.test.ts`
8. `tests/logs-ts-hybrid.bats`

#### Required behavior

1. Add a streaming process-runner path that writes child stdout/stderr chunks to provided sinks as chunks arrive, and resolves with final exit code.
2. Wire `logs` runtime path to stream through that path (no "wait for full buffer then write").
3. Keep command-level failure contract unchanged:
   - on failure: `[error] Failed to fetch logs for app '<app>'`
   - return `1`
4. On success, preserve raw stdout/stderr bytes and return `0`.
5. Handle spawned-process errors without leaking top-level `TS CLI error: ...` from `src/cli.ts` for normal `logs` execution path.

#### Required tests (must be added/updated)

1. Runtime unit test: thrown/failed process path in `runLogsCommand` returns `1` and prints exactly failure contract line.
2. Runtime unit test: streamed chunks are written in order with no extra reformatting.
3. Hybrid bats test: deterministic streaming check.
   - Use a temporary mock `fly` script that prints line 1, sleeps, prints line 2.
   - Execute `./hermes-fly logs -a test-app` in background.
   - Assert line 1 is visible in output file before command exits.
   - Assert line 2 appears by completion.

### 4.2 Slice B - Fix `resolve-app.ts` repeated `-a` parity edge cases

#### Files to update

1. `src/commands/resolve-app.ts`
2. `tests-ts/runtime/show-status.test.ts`
3. `tests-ts/runtime/show-logs.test.ts`

#### Required behavior

1. Keep resolution order unchanged:
   - last parsed `-a` app value
   - else `current_app`
   - else `null`
2. Repeated `-a` must not retain stale prior value when trailing `-a` is unresolved.
3. Implement and lock explicit behavior for `-a` followed by flag-like token (`-` prefix) so behavior is deterministic and test-guarded.
4. Behavior must match documented PR-D2 "legacy tolerance" intent and be consistent across `status` and `logs`.

#### Required tests (must be added)

1. `resolveApp(["-a", "first", "-a"], envWithCurrentApp)` returns fallback app (or `null` if no current app).
2. `resolveApp` behavior for `["-a", "--unknown-flag"]` is explicitly asserted (no ambiguous behavior).
3. `runLogsCommand` regression test covering trailing unresolved `-a` after a valid `-a`.

### 4.3 Slice C - Harden verifier script and verifier tests

#### Files to update

1. `scripts/verify-pr-d2-status-logs.sh`
2. `tests/verify-pr-d2-status-logs.bats`

#### Required behavior

1. `scripts/verify-pr-d2-status-logs.sh` must execute `tests/verify-pr-d2-status-logs.bats` in its bats run list.
2. `tests/verify-pr-d2-status-logs.bats` must not mask verifier failures via pipeline semantics.
3. Verifier success test must fail when verifier fails.

#### Required test hardening

1. In `verify-pr-d2-status-logs.sh exits 0 and prints success message` test:
   - enforce `set -euo pipefail`, or
   - avoid pipeline masking entirely (capture output first, then assert last line).
2. Add an assertion that verifier script bats invocation includes `tests/verify-pr-d2-status-logs.bats`.

### 4.4 Slice D - Harden hybrid-dispatch negative assertions

#### File to update

1. `tests/hybrid-dispatch.bats`

#### Required behavior

1. Replace non-assertive negative checks:
   - current pattern: `grep -qvF "...warning..." file || true`
2. Use deterministic fail-if-present checks:
   - `if grep -qF "...warning..." file; then ... exit 1; fi`
3. Keep all existing routing/parity assertions unchanged.

---

## 5) Deterministic Verification Criteria

All checks are required. Do not skip.

### 5.1 File-level checks

Run:

```bash
test -f src/adapters/process.ts
test -f src/adapters/flyctl.ts
test -f src/contexts/runtime/application/ports/logs-reader.port.ts
test -f src/contexts/runtime/application/use-cases/show-logs.ts
test -f src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts
test -f src/commands/logs.ts
test -f src/commands/resolve-app.ts
test -f tests-ts/runtime/show-logs.test.ts
test -f tests-ts/runtime/show-status.test.ts
test -f tests/logs-ts-hybrid.bats
test -f tests/hybrid-dispatch.bats
test -f tests/verify-pr-d2-status-logs.bats
test -f scripts/verify-pr-d2-status-logs.sh
```

Expected: all exit `0`.

### 5.2 TypeScript + architecture gates

Run:

```bash
npm run build
npm run typecheck
npm run arch:ddd-boundaries
```

Expected: all exit `0`.

### 5.3 Targeted runtime tests

Run:

```bash
npm run test:runtime-status
npm run test:runtime-logs
```

Expected: all exit `0`.

### 5.4 Targeted bats suites

Run:

```bash
tests/bats/bin/bats \
  tests/status-ts-hybrid.bats \
  tests/logs-ts-hybrid.bats \
  tests/hybrid-dispatch.bats \
  tests/verify-pr-d2-status-logs.bats \
  tests/status.bats \
  tests/logs.bats
```

Expected: all tests pass.

### 5.5 Deterministic command checks for fixed regressions

#### A) `resolve-app` trailing `-a` regression

Run:

```bash
npm run test:runtime-status -- --test-name-pattern "trailing unresolved -a"
npm run test:runtime-logs -- --test-name-pattern "trailing unresolved -a"
```

Expected: both pass; no stale prior `-a` value retention.

#### B) Streaming behavior for `logs`

Run (from repo root, deterministic temporary mock):

```bash
npm run build
tmp="$(mktemp -d)"
mkdir -p "${tmp}/mockbin" "${tmp}/config" "${tmp}/logs"
cat > "${tmp}/mockbin/fly" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "logs" ]]; then
  echo "line-1"
  sleep 1
  echo "line-2"
  exit 0
fi
exit 1
EOF
chmod +x "${tmp}/mockbin/fly"

HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=logs \
HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
PATH="${tmp}/mockbin:${PATH}" \
./hermes-fly logs -a test-app >"${tmp}/out" 2>"${tmp}/err" &
pid="$!"

sleep 0.2
grep -q "^line-1$" "${tmp}/out"
kill -0 "${pid}" >/dev/null 2>&1
wait "${pid}"
grep -q "^line-2$" "${tmp}/out"
```

Expected:

1. `line-1` appears before process exits.
2. process exits `0`.
3. `line-2` present after completion.

#### C) Verifier robustness checks

Run:

```bash
npm run verify:pr-d2-status-logs
```

Expected:

1. exits `0`
2. prints final line: `PR-D2 status/logs verification passed.`
3. verifier internally executes `tests/verify-pr-d2-status-logs.bats`

### 5.6 No-regression guardrails

Run:

```bash
npm run verify:pr-d1-list-command
npm run parity:check
git diff --name-only | rg '^tests/parity/baseline/' && exit 1 || true
```

Expected:

1. PR-D1 verifier still passes.
2. parity check still passes.
3. no parity baseline snapshot edits.

---

## 6) Definition of Done

All conditions below must be true:

1. All four slices implemented exactly as specified.
2. New/updated tests fail before code changes and pass after code changes (strict TDD evidence in commit sequence).
3. `npm run verify:pr-d2-status-logs` passes.
4. `npm run verify:pr-d1-list-command` passes.
5. No out-of-scope files changed.
6. Evidence report created at:
   - `docs/plans/typescript-commander-hybrid-rewrite-pr-d2-status-logs-review-1-implementation-report.md`

---

## 7) Commit Guidance

Use small sequential commits aligned to slices:

1. `test(pr-d2-review1): add failing logs streaming and resolve-app edge tests`
2. `fix(pr-d2-review1): stream logs output and fix resolve-app repeated -a handling`
3. `test(pr-d2-review1): harden verifier and hybrid-dispatch negative assertions`
4. `chore(pr-d2-review1): finalize verifier wiring and report`

Do not squash while implementing; keep red/green/refactor history inspectable.
