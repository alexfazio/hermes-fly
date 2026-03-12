• Findings

1. High: fallback path can still hard-loop on EOF in real deploy flow.
   openrouter_manual_fallback loops on empty model_id but does not handle read EOF/failure, and this function is
   reached from command substitution in deploy (selected_model="$(...)"), where it can spin indefinitely if stdin is
   exhausted.
   Refs: lib/openrouter.sh:331, lib/openrouter.sh:332, lib/openrouter.sh:367, lib/deploy.sh:854.
   I reproduced this with timeout 1 ... deploy_collect_llm_config ...: exit 124, ~9.7k repeated Model ID cannot be
   empty lines in 1s.
2. Medium: one new test is effectively non-assertive for the intended failure mode.
   openrouter_build_model_menu: returns error on invalid selection only asserts inside an if branch and can pass
   without explicitly asserting non-zero status. This can miss regressions.
   Ref: tests/openrouter.bats:536.
3. Low: test cleanup uses model output as a file path.
   rm -f "$result" in the fallback stdout test is incorrect cleanup and can target an unintended path if the mocked
   value changes.
   Ref: tests/openrouter.bats:517.

CRITICAL: Existing ui.bats test broken

File: tests/ui.bats:17
Test: "ui_info prints to stdout"

This test asserts that ui_info output appears in stdout (via run + assert_output). But the PR changes ui_info to write to stderr. The
test will fail when bats-support is available (it only passed openrouter.bats because those tests don't use common-setup.bash).

Fix: Update the test name and assertion to match the new behavior:
@test "ui_info prints to stderr" {
run bash -c 'source lib/ui.sh; NO_COLOR=1; ui_info "hello" 2>&1'
assert_success
assert_output --partial "hello" # Verify it goes to stderr, not stdout
run bash -c 'source lib/ui.sh; NO_COLOR=1; ui_info "hello" 2>/dev/null'
assert_success
assert_output ""
}

Similarly, check if any other tests across the full suite capture ui_info or ui_warn via stdout. Callers that relied on run
some_function and then checked $output for info/warn messages will now find those messages missing from $output (since run only
captures stdout by default in BATS < 1.5).

MEDIUM: ui_success still on stdout — inconsistency

ui_info → stderr, ui_warn → stderr, ui_error → stderr, ui_success → stdout. This is inconsistent. Consider whether ui_success should
also go to stderr for consistency, or document the split rationale (success is "output", info/warn/error are "diagnostics").

MINOR: Two weak manual fallback test assertions

Tests 14-15 (openrouter_manual_fallback: prompts for model ID with validation and explains fetch failure clearly) use [[-n "$result"]] as a fallback assertion, which always passes for non-empty strings. Not a blocker but worth tightening.

MINOR: grep -A 3 fragile JSON parsing

\_openrouter_get_model_created_timestamp relies on "created" being within 3 lines of "id". Acceptable deferral for now.
