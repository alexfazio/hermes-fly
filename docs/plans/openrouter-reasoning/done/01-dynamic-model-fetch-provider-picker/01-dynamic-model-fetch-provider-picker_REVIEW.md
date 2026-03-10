Critical Issues

1. trap "rm -f '$cache_file'" EXIT overwrites caller's trap

openrouter_setup_with_models (line 473 of new file) sets a global EXIT trap. In Bash, traps don't stack — this
replaces any existing EXIT trap in the shell. Since this function is called via command substitution in
deploy_collect_model (selected_model="$(openrouter_setup_with_models ...)"), it runs in a subshell and won't clobber
the parent's traps. However:

- If the call pattern ever changes to direct invocation (no subshell), this breaks.
- The single-quote embedding in double-quote trap string is fragile with paths containing spaces or special chars.

Fix: Use a local cleanup pattern instead:

local cache_file
cache_file="$(mktemp)" || return 1

# At end of function or on error paths

rm -f "$cache_file"

Or if you must use trap, save/restore the previous trap.

1. "--- Other providers ---" separator is selectable

In openrouter_build_provider_menu, the string "--- Other providers ---" is added to menu_items as a regular entry.
ui_select presents it as a numbered option. If the user picks it, it's returned as the selected provider, causing
openrouter_build_model_menu to find zero models and error out.

Fix: Either skip separator items in the selection loop, or use a ui_info call between the curated and other sections
instead of adding it to the menu array.

1. "Show all N models" option returns a garbage model ID

openrouter_build_model_menu adds "Show all $total_count models" when there are 15+ models, but if selected, the
extraction logic falls through to the else branch and returns the literal string "Show all 47 models" as the model
ID.

Fix: Detect this selection and either loop back with the full list, or fall through to manual entry:

if [["$SELECTED_MODEL" == "Show all"*]]; then # Re-present with all models, or fallback
...
fi

1. ui_spinner_stop output fully suppressed

In openrouter_fetch_models, both calls to ui_spinner_stop redirect >/dev/null 2>&1:

ui_spinner_stop "$status" "Model fetch failed (curl exit $status)" >/dev/null 2>&1

ui_spinner_stop does two things: (a) kills the spinner process, and (b) prints the result message. Redirecting to
/dev/null kills the spinner correctly but silences the result message entirely. The user sees the spinner start but
never sees it resolve.

Fix: Don't suppress output, or at minimum don't suppress stderr (where the spinner writes):

ui_spinner_stop 0 "Models loaded"

---

Medium Issues

1. Module not sourced from entry point

Every other module (12 of them) is sourced from the hermes-fly entry point (lines 16-27). openrouter.sh is only
sourced from deploy.sh via its dependency guard. This means:

- scaffold.bats won't verify that openrouter.sh loads without error
- Inconsistent with the convention documented in PSF-01 and PSF-08
- The module isn't available to other potential callers (e.g., a future doctor check for model validity)

Fix: Add source "${SCRIPT_DIR}/lib/openrouter.sh" to the entry point, before deploy.sh.

1. OPENROUTER_CACHE_FILE exported as implicit parameter

openrouter_build_model_menu exports OPENROUTER_CACHE_FILE to pass it to openrouter_sort_models_by_recency. This works
because the sort function checks for it, but:

- It's an implicit data dependency — the sort function's signature says model_ids is the only arg
- The export leaks into the environment (visible to child processes)
- It's never unset

Fix: Pass the cache file as a second argument to openrouter_sort_models_by_recency instead of using a global:

openrouter_sort_models_by_recency() {
local model_ids="$1"
    local cache_file="${2:-${OPENROUTER_CACHE_FILE:-}}"
...
}

1. grep -A 3 / grep -A 1 for JSON field extraction is fragile

\_openrouter_get_model_created_timestamp uses grep -A 3 to find "created" within 3 lines of "id".
openrouter_build_model_menu uses grep -A 1 to find "name" after "id". These assume a specific JSON formatting. The
mock data works because it's structured predictably, but the real OpenRouter API response may have different field
ordering or additional fields between id and created/name.

Fix: Consider collapsing the JSON to a single line per object (using tr -d '\n') before grepping, or increase the
lookahead significantly. Alternatively, extract using a broader pattern that doesn't depend on line proximity.

---

Minor Issues

1. Weak test assertions

Several tests have fallback assertions that always pass:

- openrouter_manual_fallback: explains fetch failure clearly — [[-n "$result"]] passes if there's any output
- openrouter_manual_fallback: prompts for model ID with validation — same pattern
- openrouter_setup_with_models: returns selected model ID — only checks function exists (declare -f), never actually
  calls it

1. openrouter_manual_fallback test hangs without stdin

The test openrouter_manual_fallback: explains fetch failure clearly calls the function without mocking ui_ask. Since
ui_ask reads from stdin and there's no input, it would loop infinitely. It only "works" because | head -3 triggers
SIGPIPE to kill the subprocess. This is fragile.

1. Duplicate "name" key in test fixture

In tests/openrouter.bats line ~921:
{"id":"anthropic/claude","name":"Anthropic: Claude","name":"Anthropic: Claude","created":1234567891}
Duplicate "name" key. Harmless for grep-based parsing but technically invalid JSON.

---

```
• Findings

  1. High: OpenRouter model selection is called with an empty API key, so model selection can silently fail and produce
     an empty model.
     lib/deploy.sh:851 calls openrouter_setup_with_models "$DEPLOY_API_KEY" before DEPLOY_API_KEY is assigned from the
     validated local api_key (lib/deploy.sh:835-836). This can leave DEPLOY_MODEL empty and then set LLM_MODEL= secret
     (lib/deploy.sh:1048).
  2. High: Choosing “Show all N models” returns a non-model label as the selected model ID.
     lib/openrouter.sh:283-295 adds Show all ... but does not implement that flow; selection falls through and returns
     literal text (e.g., Show all 20 models) as LLM_MODEL.
  3. High: Invalid menu input can silently yield empty model, and the section divider is selectable.
     lib/openrouter.sh:217 inserts --- Other providers --- as an actual option.
     lib/openrouter.sh:228 and :288 rely on ui_select, which returns empty on invalid input (lib/ui.sh:121-125).
     Callers do not retry/validate before returning (lib/openrouter.sh:360-371), so one bad choice can produce an empty
     model.
  4. Medium: Manual fallback can spin forever on EOF/non-interactive stdin.
     lib/openrouter.sh:315-322 loops until non-empty input, but ui_ask uses read (lib/ui.sh:82-86). On closed stdin,
     read keeps failing and the loop never exits.
  5. Medium: Test claims overstate coverage; key integration path is not actually tested.
     openrouter_setup_with_models test named “returns selected model ID” only checks function existence (declare -f)
     and never invokes/asserts output (tests/openrouter.bats:362-388). That gap would miss the regressions above.

  Assumptions / Notes

  1. Assumed empty LLM_MODEL is invalid for OpenRouter deployments (based on secret wiring).
  2. tests/openrouter.bats passes locally; targeted tests/deploy.bats subset could not be executed in this worktree due
     missing tests/test_helper/bats-support/load.
```
