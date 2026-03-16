# Remediation Plan: PR #12 Review-6 Findings

Date: 2026-03-16
Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_6.md`
Primary worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
Target PR: `#12 feat: complete TypeScript Commander.js full transition (9 slices)`

Execution mode:
- Static-analysis implementation and verification only.
- No product/API/architecture decisions delegated to implementer.
- Implementer works only in `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.

---

## 1) Objective

Resolve the remaining host-dependence defect in deploy integration tests:

1. Make deploy `--no-auto-install` integration assertions deterministic even when `fly` exists in `/usr/bin` or `/bin`.
2. Prove tests are exercising the intended missing-`fly` branch, not auth/connectivity fallback branches.

---

## 2) In Scope / Out of Scope

### In Scope

1. `tests/integration.bats`

### Out of Scope

1. `src/**`, `hermes-fly`, installer scripts, release scripts.
2. Any other test files.
3. Runtime test execution (static verification only).

---

## 3) Preconditions, Dependencies, Credentials

Preconditions:

1. Worktree path must be `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.
2. Active branch must be `worktree-compressed-waddling-rose`.
3. Required tools available locally: `bash`, `git`, `rg`, `awk`, `sed`, `sort`, `comm`, `wc`, `tr`, `mktemp`.
4. No credentials required.
5. Never commit plaintext secrets or `.env` files.
6. Capture pre-existing uncommitted file changes before edits so scope checks evaluate only net-new drift from this remediation.

Pre-check command:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
bash -euo pipefail -c '
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  test -f tests/integration.bats
  mkdir -p tmp/verification
  git diff --name-only | sort -u > tmp/verification/V4.preexisting.diff
'
```

Expected exit code: `0`  
Expected artifact:
- `tmp/verification/V4.preexisting.diff`

---

## 4) Ordered Implementation Steps

Apply steps in exact order.

### Step 1 - Harden `deploy --no-auto-install` integration test against host `fly` binaries

Problem:
- The test currently uses `PATH="${NODE_DIR}:/usr/bin:/bin"` and assumes `fly` is absent.
- On machines where `/usr/bin/fly` exists, assertion can fail for unrelated reasons.

Code refs:
- `tests/integration.bats` test name:
  - `hermes-fly deploy --no-auto-install skips install when fly not on PATH`

Required edits:

1. Inside this test’s `run bash -c '...'` block, create a temporary `which` shim directory:
   - `tmp_no_fly="$(mktemp -d)"`
   - cleanup with trap.
2. Write executable shim file `${tmp_no_fly}/which` with exact behavior:
   - if first arg is `fly`, exit `1`.
   - else `exec /usr/bin/which "$@"`.
3. Set PATH to include shim first:
   - `PATH="${tmp_no_fly}:${NODE_DIR}:/usr/bin:/bin"`
4. Keep command under test unchanged:
   - `"${PROJECT_ROOT}/hermes-fly" deploy --no-auto-install 2>&1`
5. Keep existing assertion:
   - `assert_output --partial "auto-install disabled"`
6. Add assertion:
   - `refute_output --partial "Not authenticated"`

Expected post-state:

1. Missing-`fly` branch is deterministic regardless of host.
2. Auth path is explicitly excluded in assertion contract.

---

### Step 2 - Harden invalid-channel deploy test against host `fly` binaries

Problem:
- Same host-dependence exists for invalid channel runtime-path test.

Code refs:
- `tests/integration.bats` test name:
  - `hermes-fly deploy --channel invalid falls back to stable (PR-05)`

Required edits:

1. Apply the same `which` shim pattern as Step 1 in this test.
2. Keep command under test unchanged:
   - `deploy --channel badvalue --no-auto-install`
3. Keep existing assertions:
   - `assert_output --partial "auto-install disabled"`
   - `refute_output --partial "Unknown option"`
   - `refute_output --partial "Unknown command"`
4. Add assertion:
   - `refute_output --partial "Not authenticated"`

Expected post-state:

1. Invalid-channel check remains parse-focused and deterministic.

---

### Step 3 - Harden preview-channel deploy test against host `fly` binaries

Problem:
- Same host-dependence exists for preview channel runtime-path test.

Code refs:
- `tests/integration.bats` test name:
  - `hermes-fly deploy --channel preview uses runtime path without parse errors (PR-05)`

Required edits:

1. Apply the same `which` shim pattern as Step 1 in this test.
2. Keep command under test unchanged:
   - `deploy --channel preview --no-auto-install`
3. Keep existing assertions:
   - `assert_output --partial "auto-install disabled"`
   - `refute_output --partial "Unknown option"`
   - `refute_output --partial "Unknown command"`
4. Add assertion:
   - `refute_output --partial "Not authenticated"`

Expected post-state:

1. Preview-channel runtime-path check is deterministic on all hosts.

---

### Step 4 - Harden channel matrix test loop against host `fly` binaries

Problem:
- Matrix loop (`stable|preview|edge`) currently assumes ambient PATH lacks `fly`.

Code refs:
- `tests/integration.bats` test name:
  - `channel end-to-end matrix resolves expected refs for stable preview edge (PR-05)`

Required edits:

1. In each `run bash -c "..."` loop iteration, include the same `which` shim setup from Step 1.
2. Keep command under test unchanged:
   - `"${PROJECT_ROOT}/hermes-fly" deploy --channel ${ch} --no-auto-install 2>&1`
3. Keep existing assertions:
   - `assert_output --partial "auto-install disabled"`
   - `refute_output --partial "Unknown option"`
   - `refute_output --partial "Unknown command"`
4. Add assertion in-loop:
   - `refute_output --partial "Not authenticated"`

Expected post-state:

1. All channel cases validate parser/runtime routing without host `fly` leakage.

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
  if rg -n "OPENROUTER_API_KEY=.*[A-Za-z0-9]|TELEGRAM_BOT_TOKEN=.*[A-Za-z0-9]" docs/plans/typescript-commander-full-transition-20260315_REVIEW_6.md; then
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
Cleanup: none.

---

### V1 - Missing-`fly` shim pattern exists in all 4 targeted tests

Purpose:
- Confirm host-independent missing-`fly` simulation was added everywhere required.
- Coverage type: happy path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  awk "/@test \"hermes-fly deploy --no-auto-install skips install when fly not on PATH\"/,/^}/" "${target}" > tmp/verification/V1.t1.block
  awk "/@test \"hermes-fly deploy --channel invalid falls back to stable \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V1.t2.block
  awk "/@test \"hermes-fly deploy --channel preview uses runtime path without parse errors \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V1.t3.block
  awk "/@test \"channel end-to-end matrix resolves expected refs for stable preview edge \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V1.t4.block
  for b in tmp/verification/V1.t1.block tmp/verification/V1.t2.block tmp/verification/V1.t3.block tmp/verification/V1.t4.block; do
    rg -n "if \\[\\[ \"\\$\\{1:-\\}\" == \"fly\" \\]\\]; then" "${b}"
    rg -n "exec /usr/bin/which \"\\$@\"" "${b}"
  done
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code: `0`  
Expected output: each extracted test block has both shim markers.  
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V1.t1.block`
- `tmp/verification/V1.t2.block`
- `tmp/verification/V1.t3.block`
- `tmp/verification/V1.t4.block`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`  
Pass/fail rule: all 8 checks (2 per block across 4 blocks) must match.  
Cleanup: none.

---

### V2 - Old ambient-path-only pattern removed; auth-branch refutation added

Purpose:
- Ensure deterministic branch targeting and explicit exclusion of auth failure path.
- Coverage type: failure/error path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  if rg -n "PATH=\"\\$\\{(NODE_DIR|node_dir)\\}:/usr/bin:/bin\"" "${target}"; then
    exit 1
  fi
  awk "/@test \"hermes-fly deploy --no-auto-install skips install when fly not on PATH\"/,/^}/" "${target}" > tmp/verification/V2.t1.block
  awk "/@test \"hermes-fly deploy --channel invalid falls back to stable \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t2.block
  awk "/@test \"hermes-fly deploy --channel preview uses runtime path without parse errors \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t3.block
  awk "/@test \"channel end-to-end matrix resolves expected refs for stable preview edge \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t4.block
  for b in tmp/verification/V2.t1.block tmp/verification/V2.t2.block tmp/verification/V2.t3.block tmp/verification/V2.t4.block; do
    rg -n "refute_output --partial \"Not authenticated\"" "${b}"
  done
' >tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code: `0`  
Expected output:
- zero matches for old ambient-path-only pattern (both `NODE_DIR` and `node_dir` variants).
- each extracted test block includes `refute_output --partial "Not authenticated"`.  
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V2.t1.block`
- `tmp/verification/V2.t2.block`
- `tmp/verification/V2.t3.block`
- `tmp/verification/V2.t4.block`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`  
Pass/fail rule: old ambient-path pattern absent and all 4 per-test checks match.  
Cleanup: none.

---

### V3 - Required deploy assertions are preserved in all 4 targeted tests

Purpose:
- Ensure this remediation does not drop original assertion intent.
- Coverage type: edge case.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  awk "/@test \"hermes-fly deploy --no-auto-install skips install when fly not on PATH\"/,/^}/" "${target}" > tmp/verification/V3.t1.block
  awk "/@test \"hermes-fly deploy --channel invalid falls back to stable \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V3.t2.block
  awk "/@test \"hermes-fly deploy --channel preview uses runtime path without parse errors \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V3.t3.block
  awk "/@test \"channel end-to-end matrix resolves expected refs for stable preview edge \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V3.t4.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V3.t1.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V3.t2.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V3.t3.block
  rg -n "assert_output --partial \"auto-install disabled\"" tmp/verification/V3.t4.block
  rg -n "refute_output --partial \"Unknown option\"" tmp/verification/V3.t2.block
  rg -n "refute_output --partial \"Unknown option\"" tmp/verification/V3.t3.block
  rg -n "refute_output --partial \"Unknown option\"" tmp/verification/V3.t4.block
  rg -n "refute_output --partial \"Unknown command\"" tmp/verification/V3.t2.block
  rg -n "refute_output --partial \"Unknown command\"" tmp/verification/V3.t3.block
  rg -n "refute_output --partial \"Unknown command\"" tmp/verification/V3.t4.block
' >tmp/verification/V3.out 2>tmp/verification/V3.err
```

Expected exit code: `0`  
Expected output:
- `auto-install disabled` assertion present in each of 4 extracted blocks.
- `Unknown option` and `Unknown command` refutations present in each of 3 channel-oriented blocks.
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V3.t1.block`
- `tmp/verification/V3.t2.block`
- `tmp/verification/V3.t3.block`
- `tmp/verification/V3.t4.block`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`  
Pass/fail rule: all 10 per-block assertion checks must match.  
Cleanup: none.

---

### V4 - Regression/safety check for scope containment (net-new changes only)

Purpose:
- Ensure remediation changed only `tests/integration.bats`, even in dirty worktrees.
- Coverage type: regression/safety.

Preconditions:
1. Pre-check was run and `tmp/verification/V4.preexisting.diff` exists.

Command:

```bash
bash -euo pipefail -c '
  allowed="^tests/integration\\.bats$"
  test -f tmp/verification/V4.preexisting.diff
  git diff --name-only | sort -u > tmp/verification/V4.current.diff
  sort -u tmp/verification/V4.preexisting.diff > tmp/verification/V4.preexisting.sorted
  comm -13 tmp/verification/V4.preexisting.sorted tmp/verification/V4.current.diff > tmp/verification/V4.new.diff
  if [[ -s tmp/verification/V4.new.diff ]]; then
    while IFS= read -r f; do
      if ! printf "%s\n" "${f}" | rg -q "${allowed}"; then
        printf "Out-of-scope changed file: %s\n" "${f}" >&2
        exit 1
      fi
    done < tmp/verification/V4.new.diff
  fi
' >tmp/verification/V4.out 2>tmp/verification/V4.err
```

Expected exit code: `0`  
Expected output: no `Out-of-scope changed file:` message.  
Artifacts:
- `tmp/verification/V4.preexisting.diff`
- `tmp/verification/V4.preexisting.sorted`
- `tmp/verification/V4.current.diff`
- `tmp/verification/V4.new.diff`
- `tmp/verification/V4.out`
- `tmp/verification/V4.err`  
Pass/fail rule: exit code `0` and no out-of-scope message in `V4.err`.  
Cleanup: none.

---

## 6) Step-to-Verification Traceability

1. Step 1 -> V1, V2, V3
2. Step 2 -> V1, V2, V3
3. Step 3 -> V1, V2, V3
4. Step 4 -> V1, V2, V3
5. Cross-cutting safety and credentials -> V0, V4

---

## 7) Deliverables

1. Updated `tests/integration.bats` with deterministic missing-`fly` simulation in 4 deploy tests.
2. Added explicit `refute_output --partial "Not authenticated"` guards in those 4 tests.
3. Static verification artifacts `tmp/verification/V0.out` through `tmp/verification/V4.out`.

---

## 8) Completion Criteria

This remediation is complete only when all are true:

1. Steps 1-4 are applied in order.
2. V0, V1, V2, V3, V4 all exit with `0`.
3. No unresolved ambiguity remains about branch under test (`missing fly` vs auth path).
4. No product/API/architecture decisions were delegated to implementer judgment.

## Execution Log

### Slice 1: Harden --no-auto-install test (Step 1)
- [x] S4 ANALYZE_CRITERIA: 3 criteria (which shim, shim PATH prepend, auth refutation)
- [x] S5 WRITE_TEST: V1/V2 grep checks against test block
- [x] S6 CONFIRM_RED: no shim, no auth refutation, old PATH pattern present
- [x] S7 IMPLEMENT: replaced PATH-only approach with mktemp which shim + auth refutation
- [x] S8 RUN_TESTS: pass (1 iteration)
- [x] S9 REFACTOR: no refactoring needed
- Anomalies: none

### Slice 2: Harden invalid-channel test (Step 2)
- [x] S4-S9: same pattern as Slice 1
- Anomalies: none

### Slice 3: Harden preview-channel test (Step 3)
- [x] S4-S9: same pattern as Slice 1
- Anomalies: none

### Slice 4: Harden channel matrix test (Step 4)
- [x] S4-S9: same pattern; double-quoted bash -c with escaped shim inside loop
- Anomalies: [S7] matrix test uses double-quoted `bash -c "..."` with inner variable escaping for shim setup inside the for-loop; printf uses single quotes for the shim body to avoid nested escaping issues

### VERIFY_ALL
- Test suite: pass (1 iteration) — V0 PASS, V1 PASS, V2 PASS, V3 PASS, V4 PASS
- Criteria walk: all satisfied
