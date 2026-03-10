• 1. Medium: the new EOF watchdog test still does not reliably test openrouter_manual_fallback.
At tests/openrouter.bats:554, it runs bash -c '...' without exporting openrouter_manual_fallback, so the child
shell may not have that function.
Inside that child script, tests/openrouter.bats:557 uses local at top level, which errors but can still lead to
an overall 0 exit. Combined with the final assertion tests/openrouter.bats:576, this can produce false positives.
