• 1. Medium: deploy_collect_llm_config still does not propagate model-collection failure, so it can succeed with an
empty model when not running under set -e.
At deploy.sh:836, deploy_collect_model is called without checking its exit code, and deploy.sh:838 still assigns
MODEL afterward. I reproduced ec=0 with MODEL='' on EOF/fallback failure, which can flow to secret creation at
deploy.sh:1051. 2. Medium: the invalid-selection test is ineffective in Bats due to ! usage.
openrouter.bats:534 uses ! openrouter_build_model_menu ...; in Bats this does not fail the test when the command
succeeds (confirmed independently), so regressions can slip through. 3. Low: EOF regression test can pass even when timeout is missing, and currently emits a warning.
The test at openrouter.bats:553 relies on timeout; on this environment Bats reports BW01 (command not found, exit
127), and the assertion still passes because it only checks “not 124” and “not 0” at openrouter.bats:557.

BW01: `run`'s command `timeout 2 openrouter_manual_fallback` exited with code 127,
indicating 'Command not found'.

The timeout command isn't available in the worktree test environment (macOS timeout requires coreutils). The test
still passes because BATS captures the 127 status and the assertions check $status -ne 124 and $status -ne 0. In CI
(Linux), timeout will be available. Not a blocker, but could be made portable by using gtimeout on macOS or a
bash-native timeout pattern.

- Two weak [[-n "$result"]] assertions in tests 14-15
- grep -A 3 fragile JSON parsing in \_openrouter_get_model_created_timestamp
