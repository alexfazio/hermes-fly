```

New Critical Issue: ui_info pollutes stdout in command-substitution context

  openrouter_build_provider_menu (line ~378) calls ui_info when non-curated providers exist:

  if [[ -n "$other_providers" ]]; then
      ui_info "Additional providers available:"   # <-- writes to STDOUT
      while IFS= read -r provider; do

  ui_info writes to stdout (confirmed in lib/ui.sh:35-42 — no >&2). This function is called via command substitution:

  selected_provider=$(openrouter_build_provider_menu "$cache_file")

  When any non-curated provider exists in the API response (e.g., openrouter/aurora-alpha from the mock fixture),
  selected_provider will contain:

  [info] Additional providers available:
  openai

  This breaks every downstream comparison:
  - [[ "$selected_provider" == "Enter model ID manually" ]] — never matches
  - openrouter_build_model_menu "$cache_file" "$selected_provider" — passes garbage provider name

  The integration test misses this because its fixture only contains curated providers (openai, anthropic).

  Fix: Redirect to stderr:

  ui_info "Additional providers available:" >&2

  Or use printf '...' >&2 directly, since ui_info isn't designed for stderr output.

  ---
  Remaining Medium Issues

  ui_spinner_stop stderr change affects all callers

  The ui.sh fix (lines 566-574 of diff) changes the non-color fallback path in ui_spinner_stop to write to stderr:

  -      printf '✓ %s\n' "$msg"
  +      printf '✓ %s\n' "$msg" >&2

  This corrects an inconsistency (the color path already wrote to stderr), but it's a behavioral change for the entire
  codebase. Any code that previously captured spinner result text from stdout via result=$(function_with_spinner) will
  no longer get it. BATS run captures both streams so tests should be unaffected, but this warrants mention in the PR
  description.

  menu_index declared but never used

  openrouter_build_provider_menu line ~363:

  local menu_index=1

  Never referenced. Minor dead code.

  Two manual fallback tests still weak

  - "explains fetch failure clearly" — [[ -n "$result" ]] always passes if any output exists
  - "prompts for model ID with validation" — same pattern

  The first also relies on SIGPIPE from | head -3 to terminate the ui_ask infinite loop, which is fragile.
```

```
• Findings

  1. High: Manual provider entry is broken when any non-curated provider exists.
     openrouter_build_provider_menu prints ui_info to stdout before echoing the selected provider, so command
     substitution captures both lines. Then the exact match check for "Enter model ID manually" fails and flow
     continues with an invalid provider string, ending in empty model output.
     Refs: lib/openrouter.sh:218, lib/openrouter.sh:231, lib/openrouter.sh:381, lib/openrouter.sh:383, lib/
     openrouter.sh:391, lib/openrouter.sh:396
  2. High: Fallback path returns log text as part of the model value.
     openrouter_manual_fallback writes warnings/info to stdout, and callers capture stdout as the “selected model”.
     This contaminates DEPLOY_MODEL (multi-line text + model id), then gets passed to secrets as LLM_MODEL.
     Refs: lib/openrouter.sh:323, lib/openrouter.sh:329, lib/openrouter.sh:368, lib/deploy.sh:854, lib/deploy.sh:1048
  3. High: Invalid model/provider selection still silently produces empty model.
     ui_select failure is not retried. openrouter_build_model_menu can return non-zero, but
     openrouter_setup_with_models ignores that status and always echoes selected_model (possibly empty), which then
     propagates to deploy secrets.
     Refs: lib/openrouter.sh:286, lib/openrouter.sh:310, lib/openrouter.sh:312, lib/openrouter.sh:391, lib/
     deploy.sh:856
  4. Medium: Manual fallback loops forever on EOF/non-interactive stdin.
     read failure is treated like empty input and loop continues indefinitely.
     Refs: lib/openrouter.sh:332, lib/openrouter.sh:333, lib/openrouter.sh:335

  Testing Notes

  1. bats tests/openrouter.bats passes (23/23), but these failures are not covered by current tests (especially stdout
     contamination + invalid selection handling).
```
