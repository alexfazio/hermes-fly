# PR-C1 Execution Plan: Parity Harness Foundation + Baseline Snapshots (Phase 1 Start)

Date: 2026-03-12  
Parent plan: `docs/plans/typescript-commander-hybrid-rewrite-20260311.md`  
Parent phase: Phase 1 (Command Contract Snapshot), first implementation chunk  
Timebox: 60 minutes (single session)  
Assignee profile: Junior developer  
Target branch: `feat/ts-pr-c1-parity-harness` (recommended)

## Implementation Status

Status: Ready for implementation  
Evidence report (to create after implementation): `docs/plans/typescript-commander-hybrid-rewrite-pr-c1-parity-harness-20260312-implementation-report.md`

---

## 1) Issue Summary (Jira/Linear style)

Implement the first parity harness slice by introducing deterministic capture/compare tooling and committing baseline command-contract snapshots for non-destructive commands.

This PR is harness-only: no command migration and no user-facing CLI behavior change.

---

## 2) Scope

### In scope (must ship in this PR)

1. Add parity capture script.
2. Add parity compare script.
3. Add baseline snapshots for deterministic non-destructive command scenarios.
4. Add npm scripts for parity capture/compare/check.
5. Add one-command verifier script for this PR.
6. Update README developer section with parity harness usage.
7. Ignore transient parity capture directories in `.gitignore`.

### Out of scope (do not do in this PR)

1. No `hermes-fly` dispatch logic changes.
2. No TypeScript command handlers (`list`, `status`, etc.).
3. No `scripts/install.sh` changes.
4. No `scripts/release-guard.sh` changes.
5. No CI workflow file additions.
6. No destructive/interactive parity scenarios (`deploy`, `destroy`, `resume`, `doctor`) in this chunk.

---

## 3) Preconditions (must be true before coding)

Run from repo root:

```bash
cd /Users/alex/Documents/GitHub/hermes-fly
```

Confirm anchors before edits:

1. `hermes-fly` command dispatch and help text exist:
- `hermes-fly:31-94`
- `hermes-fly:160-255`
2. Existing deterministic mock foundation exists:
- `tests/test_helper/common-setup.bash:8-14`
- `tests/mocks/fly:144-183`
3. Existing quality gates pass:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

If these are not true, resolve drift first.

---

## 4) Exact File Changes

## 4.1 Update `package.json` with parity scripts

Path: `package.json` (scripts block at `package.json:5-10`).  
Action: modify.

Required changes:

1. Add script:
- `"parity:capture": "bash scripts/parity-capture.sh --out-dir tests/parity/current"`
2. Add script:
- `"parity:compare": "bash scripts/parity-compare.sh --baseline tests/parity/baseline --candidate tests/parity/current"`
3. Add script:
- `"parity:check": "npm run parity:capture && npm run parity:compare"`
4. Keep existing scripts unchanged:
- `build`
- `typecheck`
- `arch:ddd-boundaries`
- `test:domain-primitives`

## 4.2 Update `.gitignore` for transient parity outputs

Path: `.gitignore` (current TS artifact section at `.gitignore:7-11`).  
Action: modify.

Required changes:

1. Add ignore entries:
- `tests/parity/current/`
- `tests/parity/_tmp_run1/`
- `tests/parity/_tmp_run2/`

2. Do not ignore:
- `tests/parity/baseline/` (must stay tracked)

## 4.3 Add deterministic scenario manifest

Create:

1. `tests/parity/scenarios/non_destructive_commands.list`

Required file format:

1. Pipe-delimited lines: `<scenario>|<args...>`
2. Required scenarios in this exact order:
- `version|version`
- `help|help`
- `list|list`
- `status|status -a test-app`
- `logs|logs -a test-app`

## 4.4 Add parity capture script

Create:

1. `scripts/parity-capture.sh` (executable)

Required behavior:

1. Accept `--out-dir <path>` argument (required).
2. Read scenario list from:
- `tests/parity/scenarios/non_destructive_commands.list`
3. Set deterministic execution environment before running commands:
- `NO_COLOR=1`
- `LC_ALL=C`
- `TZ=UTC`
- prepend `tests/mocks` to `PATH`
- create temporary `HERMES_FLY_CONFIG_DIR` and `HERMES_FLY_LOG_DIR`
4. Seed deterministic app context by sourcing `lib/config.sh` and running:
- `config_save_app "test-app" "ord"`
5. For each scenario, execute `./hermes-fly <args>` and capture:
- `<scenario>.stdout.snap`
- `<scenario>.stderr.snap`
- `<scenario>.exit.snap`
6. Exit code capture must be numeric text with trailing newline.
7. Print final success line:
- `Parity capture completed: <out-dir>`

## 4.5 Add parity compare script

Create:

1. `scripts/parity-compare.sh` (executable)

Required behavior:

1. Accept:
- `--baseline <path>`
- `--candidate <path>`
2. Use scenario list from:
- `tests/parity/scenarios/non_destructive_commands.list`
3. For each scenario stream (`stdout`, `stderr`, `exit`):
- verify both files exist,
- compare byte-for-byte,
- if mismatch, print:
  - `Mismatch: <scenario>.<stream>.snap`
  - unified diff (`diff -u ...`)
4. Exit `1` on any mismatch or missing file.
5. Print `Parity compare passed.` only when all files match.

## 4.6 Add baseline snapshots

Create directory:

1. `tests/parity/baseline/`

Required files (15 total):

1. `tests/parity/baseline/version.stdout.snap`
2. `tests/parity/baseline/version.stderr.snap`
3. `tests/parity/baseline/version.exit.snap`
4. `tests/parity/baseline/help.stdout.snap`
5. `tests/parity/baseline/help.stderr.snap`
6. `tests/parity/baseline/help.exit.snap`
7. `tests/parity/baseline/list.stdout.snap`
8. `tests/parity/baseline/list.stderr.snap`
9. `tests/parity/baseline/list.exit.snap`
10. `tests/parity/baseline/status.stdout.snap`
11. `tests/parity/baseline/status.stderr.snap`
12. `tests/parity/baseline/status.exit.snap`
13. `tests/parity/baseline/logs.stdout.snap`
14. `tests/parity/baseline/logs.stderr.snap`
15. `tests/parity/baseline/logs.exit.snap`

Required content constraints:

1. `version.stdout.snap` must equal `hermes-fly 0.1.20` followed by newline.
2. `version.stderr.snap`, `help.stderr.snap`, `list.stderr.snap`, `logs.stderr.snap`, `status.stdout.snap` must be empty files.
3. All `*.exit.snap` files must contain `0` followed by newline.
4. `logs.stdout.snap` must contain exactly the three mock log lines from `tests/mocks/fly:181-183`.
5. `status.stderr.snap` must include all of:
- `[info] App:     test-app`
- `[info] Status:  started`
- `[info] Machine: started`
- `[info] Region:  ord`
- `✓ URL:     https://test-app.fly.dev`

Generation rule:

1. Generate baseline via capture script, not manual typing:

```bash
bash scripts/parity-capture.sh --out-dir tests/parity/baseline
```

## 4.7 Update README developer section

Path: `README.md`  
Current anchor: developer migration subsection around `README.md:149-163`.

Action: append subsection.

Title:

1. `Parity Harness`

Required content:

```bash
npm run parity:check
```

Required sentence:

1. `Captures deterministic command snapshots and compares them to the committed parity baseline.`

## 4.8 Add deterministic verifier script

Create:

1. `scripts/verify-pr-c1-parity-harness.sh` (executable)

Script steps:

1. Verify all required new files exist.
2. Run:
- `npm run parity:check`
3. Verify capture stability by running twice and diffing outputs:
- capture to `tests/parity/_tmp_run1`
- capture to `tests/parity/_tmp_run2`
- `diff -ru` must be clean.
4. Run negative compare test:
- mutate one candidate snapshot in temp directory,
- `parity-compare.sh` must fail and print `Mismatch:`.
5. Run regression safety:
- `npm run typecheck`
- `npm run arch:ddd-boundaries`
- `npm run test:domain-primitives`
- `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`
6. Print `PR-C1 verification passed.` only on success.

---

## 5) Deterministic Verification Criteria

All checks are required.

## 5.1 File-level checks

Run:

```bash
test -f scripts/parity-capture.sh
test -f scripts/parity-compare.sh
test -f scripts/verify-pr-c1-parity-harness.sh
test -f tests/parity/scenarios/non_destructive_commands.list
test -f tests/parity/baseline/version.stdout.snap
test -f tests/parity/baseline/version.stderr.snap
test -f tests/parity/baseline/version.exit.snap
test -f tests/parity/baseline/help.stdout.snap
test -f tests/parity/baseline/help.stderr.snap
test -f tests/parity/baseline/help.exit.snap
test -f tests/parity/baseline/list.stdout.snap
test -f tests/parity/baseline/list.stderr.snap
test -f tests/parity/baseline/list.exit.snap
test -f tests/parity/baseline/status.stdout.snap
test -f tests/parity/baseline/status.stderr.snap
test -f tests/parity/baseline/status.exit.snap
test -f tests/parity/baseline/logs.stdout.snap
test -f tests/parity/baseline/logs.stderr.snap
test -f tests/parity/baseline/logs.exit.snap
```

Expected: all exit `0`.

## 5.2 Parity harness success path

Run:

```bash
npm run parity:check
```

Expected:

1. Exit `0`.
2. Capture step prints `Parity capture completed:`.
3. Compare step prints `Parity compare passed.`.

## 5.3 Capture determinism check

Run:

```bash
bash scripts/parity-capture.sh --out-dir tests/parity/_tmp_run1
bash scripts/parity-capture.sh --out-dir tests/parity/_tmp_run2
diff -ru tests/parity/_tmp_run1 tests/parity/_tmp_run2
```

Expected: final `diff` exits `0`.

## 5.4 Compare negative path

Run:

```bash
cp -R tests/parity/_tmp_run1 tests/parity/_tmp_mutation
echo "# mutation" >> tests/parity/_tmp_mutation/version.stdout.snap
bash scripts/parity-compare.sh --baseline tests/parity/baseline --candidate tests/parity/_tmp_mutation
```

Expected:

1. compare exits non-zero,
2. output contains `Mismatch: version.stdout.snap`.

## 5.5 Static/boundary and runtime regression checks

Run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: all exit `0`.

## 5.6 One-command verifier

Run:

```bash
./scripts/verify-pr-c1-parity-harness.sh
```

Expected: exit `0`, prints `PR-C1 verification passed.`

---

## 6) Definition of Done (PR acceptance)

PR is done only when all are true:

1. `scripts/parity-capture.sh` deterministically captures scenario tuples (`stdout`, `stderr`, `exit`).
2. `scripts/parity-compare.sh` detects missing/mismatched snapshot files with deterministic failure output.
3. Baseline parity snapshots for `version/help/list/status/logs` are committed and reproducible.
4. `npm run parity:check` passes.
5. Existing quality gates remain green (`typecheck`, `arch:ddd-boundaries`, domain tests, hybrid/integration bats).
6. Existing CLI behavior remains unchanged.
7. No changes in:
- `hermes-fly`
- `scripts/install.sh`
- `scripts/release-guard.sh`

---

## 7) Commit and PR Metadata

Recommended commit message:

```text
PR-C1: add parity capture/compare harness and baseline snapshots
```

Recommended PR title:

```text
PR-C1 Phase 1: parity harness foundation and baseline snapshots
```

Recommended PR checklist text:

1. Ran `npm run parity:check`
2. Ran deterministic double-capture diff (`_tmp_run1` vs `_tmp_run2`)
3. Verified negative compare path reports mismatch
4. Ran `npm run typecheck`
5. Ran `npm run arch:ddd-boundaries`
6. Ran `npm run test:domain-primitives`
7. Ran `tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats`
8. Ran `./scripts/verify-pr-c1-parity-harness.sh`

---

## 8) Rollback

If regressions are found:

1. Revert PR-C1 commit.
2. Re-run:

```bash
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats
```

Expected: behavior returns to PR-B1 baseline.

---

## References

- [GNU diffutils manual](https://www.gnu.org/software/diffutils/manual/)
- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/bash.html)
- [Bats-core documentation](https://bats-core.readthedocs.io/)
