# Remediation Plan: PR #12 Review-7 Findings

Date: 2026-03-16
Plan file: `/Users/alex/Documents/GitHub/hermes-fly/docs/plans/typescript-commander-full-transition-20260315_REVIEW_7.md`
Primary worktree: `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`
Target PR: `#12 feat: complete TypeScript Commander.js full transition (9 slices)`

Execution mode:
- Static-analysis implementation and verification only.
- No product/API/architecture decisions delegated to implementer.
- Implementer works only in `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.

---

## 1) Objective

Resolve the remaining deterministic test defect:

1. Fix incorrect `printf` quoting for `which` shim generation in 3 deploy integration tests.
2. Ensure shim evaluates `${1:-}` and `$@` at shim runtime, not at test file generation time.
3. Preserve all existing test assertions and behavior contracts.

---

## 2) In Scope / Out of Scope

### In Scope

1. `tests/integration.bats`

### Out of Scope

1. All `src/**` files.
2. All other test files.
3. `hermes-fly`, installer scripts, release scripts.
4. Runtime test execution (static verification only).

---

## 3) Preconditions, Dependencies, Credentials

Preconditions:

1. Worktree path must be `/Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose`.
2. Active branch must be `worktree-compressed-waddling-rose`.
3. Required tools available locally: `bash`, `git`, `rg`, `awk`, `sed`, `sort`, `comm`, `wc`, `tr`.
4. No credentials required.
5. Never commit plaintext secrets or `.env` files.
6. Capture pre-existing uncommitted changes before edits so scope checks evaluate net-new drift only.

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

### Step 1 - Replace incorrect double-quoted shim `printf` in 3 deploy tests

Problem:
- Three tests generate `which` shim using double-quoted `printf` template, which expands `${1:-}` and `$@` too early.

Code refs:
- `tests/integration.bats`
- Targeted tests:
  - `hermes-fly deploy --no-auto-install skips install when fly not on PATH`
  - `hermes-fly deploy --channel invalid falls back to stable (PR-05)`
  - `hermes-fly deploy --channel preview uses runtime path without parse errors (PR-05)`

Required edits:

1. In each of the 3 targeted tests, replace:
   - `printf "#!/usr/bin/env bash\nif [[ \"${1:-}\" == \"fly\" ]]; then exit 1; fi\nexec /usr/bin/which \"$@\"\n" > "${tmp_no_fly}/which"`
2. With exactly:
   - `printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "fly" ]]; then exit 1; fi\nexec /usr/bin/which "$@"\n' > "${tmp_no_fly}/which"`
3. Do not change the matrix-test shim template if already single-quoted.

Expected post-state:

1. No `printf "#!/usr/bin/env bash...` remains in `tests/integration.bats`.
2. All 4 deploy tests use single-quoted shim template.

---

### Step 2 - Preserve all assertions in targeted tests

Problem:
- Fix must not alter existing behavior checks.

Code refs:
- `tests/integration.bats`

Required edits:

1. Keep `assert_output --partial "auto-install disabled"` in all 4 deploy tests.
2. Keep `refute_output --partial "Not authenticated"` in all 4 deploy tests.
3. Keep `refute_output --partial "Unknown option"` and `refute_output --partial "Unknown command"` in the 3 channel tests.

Expected post-state:

1. Assertion contract remains unchanged while shim template is corrected.

---

## 5) Deterministic Verification Matrix (Static Analysis Only)

Run from:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
mkdir -p tmp/verification
```

### V0 - Credential readiness and worktree guard

Purpose:
- Confirm no credentials needed and execution scope is correct.
- Coverage type: credential-readiness.

Preconditions:
1. None.

Command:

```bash
bash -euo pipefail -c '
  test -d /Users/alex/Documents/GitHub/hermes-fly/.claude/worktrees/compressed-waddling-rose
  test "$(git rev-parse --abbrev-ref HEAD)" = "worktree-compressed-waddling-rose"
  if rg -n "OPENROUTER_API_KEY=.*[A-Za-z0-9]|TELEGRAM_BOT_TOKEN=.*[A-Za-z0-9]" docs/plans/typescript-commander-full-transition-20260315_REVIEW_7.md; then
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

### V1 - Bad double-quoted shim template removed

Purpose:
- Ensure early-expansion bug pattern is fully removed.
- Coverage type: failure/error path prevention.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  if rg -n "printf \"#!/usr/bin/env bash" tests/integration.bats; then
    exit 1
  fi
' >tmp/verification/V1.out 2>tmp/verification/V1.err
```

Expected exit code: `0`  
Expected output: no matches for bad double-quoted template.  
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V1.out`
- `tmp/verification/V1.err`  
Pass/fail rule: no bad-template matches.
Cleanup: none.

---

### V2 - Correct single-quoted shim template exists in all 4 deploy tests

Purpose:
- Confirm runtime-expansion-safe shim template is used consistently.
- Coverage type: happy path.

Preconditions:
1. V0 complete.

Command:

```bash
bash -euo pipefail -c '
  target="tests/integration.bats"
  awk "/@test \"hermes-fly deploy --no-auto-install skips install when fly not on PATH\"/,/^}/" "${target}" > tmp/verification/V2.t1.block
  awk "/@test \"hermes-fly deploy --channel invalid falls back to stable \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t2.block
  awk "/@test \"hermes-fly deploy --channel preview uses runtime path without parse errors \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t3.block
  awk "/@test \"channel end-to-end matrix resolves expected refs for stable preview edge \\(PR-05\\)\"/,/^}/" "${target}" > tmp/verification/V2.t4.block
  for b in tmp/verification/V2.t1.block tmp/verification/V2.t2.block tmp/verification/V2.t3.block tmp/verification/V2.t4.block; do
    rg -n "printf '#!/usr/bin/env bash\\\\nif \\\\\\[\\\\\\[ \"\\\\\\$\\\\\\{1:-\\\\\\}\" == \"fly\" \\\\\\]\\\\\\]; then exit 1; fi\\\\nexec /usr/bin/which \"\\\\\\$@\"\\\\n'" "${b}"
  done
' >tmp/verification/V2.out 2>tmp/verification/V2.err
```

Expected exit code: `0`  
Expected output: each extracted deploy test block contains the exact single-quoted shim template.  
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V2.t1.block`
- `tmp/verification/V2.t2.block`
- `tmp/verification/V2.t3.block`
- `tmp/verification/V2.t4.block`
- `tmp/verification/V2.out`
- `tmp/verification/V2.err`  
Pass/fail rule: all 4 per-block template checks must match.
Cleanup: none.

---

### V3 - Required assertion contract preserved

Purpose:
- Ensure behavior assertions were not accidentally dropped.
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

  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V3.t1.block
  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V3.t2.block
  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V3.t3.block
  rg -n "refute_output --partial \"Not authenticated\"" tmp/verification/V3.t4.block

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
- all 4 deploy blocks include `auto-install disabled`.
- all 4 deploy blocks include `Not authenticated` refute.
- 3 channel blocks include both `Unknown option` and `Unknown command` refutes.  
Artifacts:
- `tests/integration.bats`
- `tmp/verification/V3.t1.block`
- `tmp/verification/V3.t2.block`
- `tmp/verification/V3.t3.block`
- `tmp/verification/V3.t4.block`
- `tmp/verification/V3.out`
- `tmp/verification/V3.err`  
Pass/fail rule: all 14 per-block assertion checks must match.
Cleanup: none.

---

### V4 - Scope containment (net-new changes only)

Purpose:
- Ensure remediation only changes `tests/integration.bats` even in dirty worktrees.
- Coverage type: regression/safety.

Preconditions:
1. Pre-check completed and `tmp/verification/V4.preexisting.diff` exists.

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

1. Step 1 -> V1, V2
2. Step 2 -> V3
3. Cross-cutting safety and credentials -> V0, V4

---

## 7) Deliverables

1. Updated `tests/integration.bats` with corrected single-quoted shim templates in 3 targeted tests.
2. Preserved deploy assertion contract across all 4 deploy tests.
3. Static verification artifacts `tmp/verification/V0.out` through `tmp/verification/V4.out`.

---

## 8) Completion Criteria

This remediation is complete only when all are true:

1. Steps 1-2 are applied in order.
2. V0, V1, V2, V3, V4 all exit with `0`.
3. No double-quoted shim template remains in `tests/integration.bats`.
4. No product/API/architecture decisions were delegated to implementer judgment.
