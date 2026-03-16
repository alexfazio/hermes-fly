# Remediation Plan: PR #12 Review-5 Findings

Date: 2026-03-16
Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_5.md`
Primary worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
Target PR: `#12 feat: complete TypeScript Commander.js full transition (9 slices)`

Execution mode:
- Static-analysis implementation and verification only.
- No product/API/architecture decisions delegated to implementer.
- Implementer works only in `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.

---

## 1) Objective

Resolve the two remaining Review-5 defects:

1. Fix `saveApp` so non-target top-level lines located after `apps:` are preserved.
2. Fix `saveApp` dedup to normalize app names (whitespace-safe), preventing duplicate app entries.
3. Add deterministic TS tests proving both behaviors.

---

## 2) In Scope / Out of Scope

### In Scope

1. `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
2. `tests-ts/deploy/run-deploy-wizard.test.ts`

### Out of Scope

1. `hermes-fly` launcher behavior.
2. `tests/status-ts-hybrid.bats`, `tests/logs-ts-hybrid.bats`, `scripts/verify-pr-d2-status-logs.sh`.
3. Installer/release files (`scripts/install.sh`, `scripts/release-guard.sh`).
4. Running runtime/BATS/unit test suites (static verification only in this plan).

---

## 3) Preconditions, Dependencies, Credentials

Preconditions:

1. Worktree path must be `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.
2. Active branch must be `worktree-compressed-waddling-rose`.
3. Required tools available locally: `bash`, `git`, `rg`, `awk`, `sed`, `node`, `npm`.
4. No credentials required.
5. Never commit plaintext secrets or `.env` files.
6. Capture pre-existing uncommitted file changes before edits so scope checks evaluate only net-new drift from this remediation.

Pre-check command:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
bash -euo pipefail -c '
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  test -f src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts
  test -f tests-ts/deploy/run-deploy-wizard.test.ts
  mkdir -p tmp/verification
  git diff --name-only | sort -u > tmp/verification/V5.preexisting.diff
'
```

Expected exit code: `0`.
Expected artifact:
- `tmp/verification/V5.preexisting.diff` (scope baseline captured before any edits).

---

## 4) Ordered Implementation Steps

Apply steps in exact order.

### Step 1 - Preserve non-target top-level lines after `apps:` in `saveApp`

Problem:
- Current `saveApp` parsing can absorb top-level lines after `apps:` into an app entry, then drop them when dedup removes that entry.

Code refs:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`

Required edits (exact algorithm requirements):

1. In `saveApp`, after identifying `appsIdx`, split the post-`apps:` content into two arrays:
   - `appsSectionLines`: lines that belong to app entry list.
   - `trailingTopLevelLines`: first line that does not start with exactly two spaces plus all subsequent lines.
2. Use this split rule:
   - Find `trailingStartIdx = appsBodyRaw.findIndex(l => !/^  /.test(l))`.
   - If `trailingStartIdx === -1`, `trailingTopLevelLines` is empty.
   - Else, `appsSectionLines = appsBodyRaw.slice(0, trailingStartIdx)` and `trailingTopLevelLines = appsBodyRaw.slice(trailingStartIdx)`.
3. Parse app entries from `appsSectionLines` only.
4. Rebuild file output in this exact order:
   - `current_app: <appName>`
   - preserved pre-`apps:` lines
   - `apps:`
   - rebuilt app entry lines
   - preserved `trailingTopLevelLines`
5. Keep trailing newline (`\n`) on file write.

Expected post-state:

1. Top-level sentinel lines after `apps:` are preserved across `saveApp` calls.
2. `current_app` and app list schema remain parser-compatible.

---

### Step 2 - Deduplicate app entries using normalized parsed name

Problem:
- Existing dedup compares raw line equality (`l === "  - name: ${appName}"`) and misses whitespace variants.

Code refs:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts`

Required edits:

1. During app-entry parse, extract normalized app name from the `- name` line using:
   - regex `^  - name:[ \t]*(.+)$`
   - normalization with `.trim()`
2. Store parsed entries as structured objects:
   - `{ name: string, lines: string[] }`
3. Dedup by structured `name !== appName`, not raw line equality.
4. Append updated entry:
   - `  - name: ${appName}`
   - `    region: ${region}`
5. Keep method signature unchanged:
   - `async saveApp(appName: string, region: string): Promise<void>`

Expected post-state:

1. Input entries like `  - name: my-app   ` are deduped correctly.
2. Resulting config contains exactly one `my-app` entry after rewrite.

---

### Step 3 - Add TS contract test for preserving top-level trailing lines

Problem:
- No test currently proves that non-target top-level lines after `apps:` survive rewrite.

Code refs:
- `tests-ts/deploy/run-deploy-wizard.test.ts`
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`

Required edits:

1. Add test with exact name:
   - `saveApp preserves non-target lines after apps section`
2. In test setup:
   - Create temp config dir with `mkdtemp`.
   - Seed `config.yaml` with exact pattern:
     - `current_app: old-app`
     - `apps:`
     - `  - name: old-app`
     - `    region: ord`
     - `metadata: keep-me`
3. Invoke `saveApp("my-app", "iad")`.
4. Assert output contains:
   - `metadata: keep-me`
   - `current_app: my-app`
   - `  - name: my-app`
   - `    region: iad`
5. Clean up temp dir with `rm(..., { recursive: true })`.

Expected post-state:

1. Test explicitly guards the preservation defect.

---

### Step 4 - Add TS contract test for whitespace-normalized dedup

Problem:
- No test currently proves dedup works for whitespace-variant `- name:` lines.

Code refs:
- `tests-ts/deploy/run-deploy-wizard.test.ts`
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`

Required edits:

1. Add test with exact name:
   - `saveApp dedupes app entries with whitespace-normalized names`
2. Seed `config.yaml` with:
   - `current_app: my-app`
   - `apps:`
   - `  - name: my-app   ` (trailing spaces intentionally)
   - `    region: ord`
3. Invoke `saveApp("my-app", "lax")`.
4. Assert:
   - exactly one `- name: my-app` entry remains (regex count assertion).
   - `region: lax` is present.
5. Keep existing tests unchanged.

Expected post-state:

1. Whitespace variant dedup regression is permanently covered.

---

## 5) Deterministic Verification Matrix (Static Analysis Only)

Run from:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
mkdir -p tmp/verification
```

### V0 - Credential readiness and scope guard

Purpose:
- Confirm no credentials needed and execution is in correct worktree/branch.
- Coverage type: credential-readiness.

Preconditions:
1. None.

Command:

```bash
bash -euo pipefail -c '
  test -d /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  if rg -n "OPENROUTER_API_KEY=.*[A-Za-z0-9]|TELEGRAM_BOT_TOKEN=.*[A-Za-z0-9]" docs/plans/typescript-commander-full-transition-20260315_REVIEW_5.md; then
    exit 1
  fi
' >tmp/verification/V0.out 2>tmp/verification/V0.err
```

Expected exit code: `0`  
Expected output: no secret-assignment matches.  
Artifacts:
- `tmp/verification/V0.out`
- `tmp/verification/V0.err`  
Pass/fail rule: exit code `0` and empty `V0.err`.  
Cleanup: none (artifacts retained).

---

### V1 - `saveApp` includes explicit trailing-top-level preservation logic

Purpose:
- Prove Step 1 implementation exists and is deterministic.
- Coverage type: happy path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts"
  awk "/saveApp\\(appName: string, region: string\\)/,/^  }/" "${target}" > tmp/verification/V1.saveapp.block
  rg -n "trailingStartIdx" tmp/verification/V1.saveapp.block
  rg -n "trailingTopLevelLines" tmp/verification/V1.saveapp.block
  rg -n "appsBodyRaw\\.findIndex\\(l => !/\\^  /\\.test\\(l\\)\\)" tmp/verification/V1.saveapp.block
  rg -n "\\.\\.\\.trailingTopLevelLines" tmp/verification/V1.saveapp.block
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code: `0`  
Expected output: all four structural markers matched.  
Artifacts:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `tmp/verification/V1.saveapp.block`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`  
Pass/fail rule: all four `rg` checks return at least one match.  
Cleanup: none.

---

### V2 - `saveApp` dedup uses normalized parsed app name (not raw line equality)

Purpose:
- Prove Step 2 implementation addresses whitespace-variant dedup.
- Coverage type: edge case.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts"
  awk "/saveApp\\(appName: string, region: string\\)/,/^  }/" "${target}" > tmp/verification/V2.saveapp.block
  rg -n "\\^  - name:\\[ \\t\\]\\*\\(\\.\\+\\)\\$" tmp/verification/V2.saveapp.block
  rg -n "\\.trim\\(\\)" tmp/verification/V2.saveapp.block
  rg -n "name !== appName|name === appName" tmp/verification/V2.saveapp.block
  if rg -n "l === `  - name: \\$\\{appName\\}`" tmp/verification/V2.saveapp.block; then
    exit 1
  fi
' >tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code: `0`  
Expected output: regex parse + trim + normalized-name comparison present; raw-line equality absent.  
Artifacts:
- `src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts`
- `tmp/verification/V2.saveapp.block`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`  
Pass/fail rule: first three checks match and raw-line equality check returns no match.  
Cleanup: none.

---

### V3 - Test for preserving top-level lines after `apps:` exists with required sentinel assertions

Purpose:
- Prove Step 3 test exists and enforces defect scenario.
- Coverage type: failure/error path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests-ts/deploy/run-deploy-wizard.test.ts"
  rg -n "saveApp preserves non-target lines after apps section" "${target}"
  rg -n "metadata: keep-me" "${target}"
  rg -n "current_app: my-app" "${target}"
  rg -n "region: iad" "${target}"
' >tmp/verification/V3.out 2>tmp/verification/V3.err
```

Expected exit code: `0`  
Expected output: all four required markers matched.  
Artifacts:
- `tests-ts/deploy/run-deploy-wizard.test.ts`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`  
Pass/fail rule: all four checks return matches.  
Cleanup: none.

---

### V4 - Test for whitespace-normalized dedup exists with deterministic duplicate-count assertion

Purpose:
- Prove Step 4 test exists and enforces whitespace dedup.
- Coverage type: edge case.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests-ts/deploy/run-deploy-wizard.test.ts"
  rg -n "saveApp dedupes app entries with whitespace-normalized names" "${target}"
  rg -n "name: my-app   " "${target}"
  rg -n "assert\\.equal\\(nameMatches, 1|exactly one|exactly 1" "${target}"
  rg -n "region: lax" "${target}"
' >tmp/verification/V4.out 2>tmp/verification/V4.err
```

Expected exit code: `0`  
Expected output: test name, whitespace seed, duplicate-count assertion, and region-update assertion present.  
Artifacts:
- `tests-ts/deploy/run-deploy-wizard.test.ts`
- `tmp/verification/V4.out`
- `tmp/verification/V4.err`  
Pass/fail rule: all four checks return matches.  
Cleanup: none.

---

### V5 - Regression/safety check for scope containment

Purpose:
- Ensure remediation stayed in intended files and did not drift into unrelated surfaces.
- Coverage type: regression/safety.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  allowed="^src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard\\.ts$|^tests-ts/deploy/run-deploy-wizard\\.test\\.ts$"
  test -f tmp/verification/V5.preexisting.diff
  git diff --name-only | sort -u > tmp/verification/V5.current.diff
  sort -u tmp/verification/V5.preexisting.diff > tmp/verification/V5.preexisting.sorted
  comm -13 tmp/verification/V5.preexisting.sorted tmp/verification/V5.current.diff > tmp/verification/V5.new.diff
  if [[ -s tmp/verification/V5.new.diff ]]; then
    while IFS= read -r f; do
      if ! printf "%s\n" "${f}" | rg -q "${allowed}"; then
        printf "Out-of-scope changed file: %s\n" "${f}" >&2
        exit 1
      fi
    done < tmp/verification/V5.new.diff
  fi
' >tmp/verification/V5.out 2>tmp/verification/V5.err
```

Expected exit code: `0`  
Expected output: no out-of-scope file messages in `V5.err`.  
Artifacts:
- `tmp/verification/V5.preexisting.diff`
- `tmp/verification/V5.preexisting.sorted`
- `tmp/verification/V5.current.diff`
- `tmp/verification/V5.new.diff`
- `tmp/verification/V5.out`
- `tmp/verification/V5.err`  
Pass/fail rule: exit code `0`; `V5.err` contains no `Out-of-scope changed file:` line.  
Cleanup: none.

---

## 6) Step-to-Verification Traceability

1. Step 1 -> V1
2. Step 2 -> V2
3. Step 3 -> V3
4. Step 4 -> V4
5. Cross-cutting safety and credentials -> V0, V5

---

## 7) Deliverables

1. Updated `saveApp` logic preserving trailing top-level lines and deduping by normalized app name.
2. Two new tests in `tests-ts/deploy/run-deploy-wizard.test.ts` with exact names required by this plan.
3. Static verification artifacts `tmp/verification/V0.out` through `tmp/verification/V5.out`.

---

## 8) Completion Criteria

This remediation is complete only when all conditions are true:

1. Steps 1-4 are applied in order.
2. V0, V1, V2, V3, V4, V5 all exit with `0`.
3. No unresolved ambiguity remains in dedup or non-target-line preservation behavior.
4. No product/API/architecture decisions were delegated to implementer judgment.

## Execution Log

### Slice 1: Preserve non-target top-level lines after apps: + normalized dedup (Steps 1+2 combined)
- [x] S4 ANALYZE_CRITERIA: 8 criteria extracted (4 from V1 structural markers + 4 from V2 normalized dedup)
- [x] S5 WRITE_TEST: V1/V2 structural grep checks against saveApp block
- [x] S6 CONFIRM_RED: trailingStartIdx and trailingTopLevelLines absent; raw line equality present
- [x] S7 IMPLEMENT: refactored saveApp in fly-deploy-wizard.ts — split appsBodyRaw into appsSectionLines/trailingTopLevelLines; parse entries as { name, lines } with regex + .trim(); dedup by e.name !== appName
- [x] S8 RUN_TESTS: pass (1 iteration) — 15/15 existing tests green
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: [S7] Steps 1 and 2 implemented together as they modify the same code block; doing them separately would require an intermediate refactor

### Slice 3: Test for preserving top-level trailing lines
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted (test name, metadata sentinel, current_app, region)
- [x] S5 WRITE_TEST: appended "saveApp preserves non-target lines after apps section" test
- [x] S6 CONFIRM_RED: test name absent
- [x] S7 IMPLEMENT: added test seeding metadata: keep-me and asserting survival
- [x] S8 RUN_TESTS: pass (1 iteration) — 16/16
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 4: Test for whitespace-normalized dedup
- [x] S4 ANALYZE_CRITERIA: 4 criteria extracted (test name, whitespace seed, count=1, region=lax)
- [x] S5 WRITE_TEST: appended "saveApp dedupes app entries with whitespace-normalized names" test
- [x] S6 CONFIRM_RED: test name absent
- [x] S7 IMPLEMENT: added test seeding "  - name: my-app   " (trailing spaces) and asserting exactly 1 entry with region: lax
- [x] S8 RUN_TESTS: pass (1 iteration) — 17/17
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### VERIFY_ALL
- Test suite: pass (1 iteration) — 24/24 TS tests (deploy + runtime), 0 failures
- Criteria walk: V0 PASS, V1 PASS, V2 PASS, V3 PASS, V4 PASS, V5 PASS — all satisfied
