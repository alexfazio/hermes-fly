#!/usr/bin/env bats
# tests/messaging.bats — Tests for lib/messaging.sh messaging setup wizards

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  source "${PROJECT_ROOT}/lib/ui.sh"
  source "${PROJECT_ROOT}/lib/messaging.sh"
}

teardown() {
  _common_teardown
}

# --- messaging_validate_telegram_token ---

@test "messaging_validate_telegram_token accepts valid token" {
  run messaging_validate_telegram_token "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
  assert_success
}

@test "messaging_validate_telegram_token rejects invalid token" {
  run messaging_validate_telegram_token "invalid"
  assert_failure
}

@test "messaging_validate_telegram_token rejects empty" {
  run messaging_validate_telegram_token ""
  assert_failure
}

# --- messaging_validate_user_ids ---

@test "messaging_validate_user_ids accepts numeric IDs" {
  run messaging_validate_user_ids "12345"
  assert_success
}

@test "messaging_validate_user_ids accepts comma-separated numeric IDs" {
  run messaging_validate_user_ids "12345,67890"
  assert_success
}

@test "messaging_validate_user_ids rejects non-numeric input" {
  run messaging_validate_user_ids "alexfazio"
  assert_failure
}

@test "messaging_validate_user_ids accepts empty input" {
  run messaging_validate_user_ids ""
  assert_success
}

# --- messaging_setup_menu ---

@test "messaging_setup_menu shows Telegram and Skip only" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; source lib/messaging.sh; echo "1" | messaging_setup_menu 2>&1'
  assert_success
  assert_output --partial "Telegram"
  assert_output --partial "Skip"
  refute_output --partial "Discord"
}

@test "messaging_setup_menu default returns skip" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; source lib/messaging.sh; echo "" | messaging_setup_menu 2>/dev/null'
  assert_success
  assert_output --partial "skip"
}

@test "messaging_setup_menu with 1 returns telegram" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; source lib/messaging.sh; echo "1" | messaging_setup_menu 2>/dev/null'
  assert_success
  assert_output --partial "telegram"
}

@test "messaging_setup_menu with 2 returns skip" {
  run bash -c 'export NO_COLOR=1; source lib/ui.sh; source lib/messaging.sh; echo "2" | messaging_setup_menu 2>/dev/null'
  assert_success
  assert_output --partial "skip"
}

@test "messaging_setup_menu re-prompts on invalid input then accepts valid" {
  _run_with_stdin() { printf 'garbage\n1\n' | messaging_setup_menu 2>/dev/null; }
  run _run_with_stdin
  assert_success
  assert_output "telegram"
}

@test "messaging_setup_menu rejects bot token pasted as choice" {
  _run_with_stdin() { printf '8617478383:AAGtp-test\n2\n' | messaging_setup_menu 2>/dev/null; }
  run _run_with_stdin
  assert_success
  assert_output "skip"
}

# --- messaging_setup_telegram ---

@test "messaging_setup_telegram shows BotFather deep link" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\n") 2>&1'
  assert_success
  assert_output --partial "t.me/BotFather"
}

@test "messaging_setup_telegram Only me stores single user ID" {
  # token, confirm bot, access=1(Only me), user ID
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\n") 2>/dev/null
    echo "TOKEN=$DEPLOY_TELEGRAM_BOT_TOKEN USERS=$DEPLOY_TELEGRAM_ALLOWED_USERS"'
  assert_success
  assert_output --partial "TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
  assert_output --partial "USERS=12345"
}

@test "messaging_setup_telegram Specific people stores comma-separated IDs" {
  # token, confirm bot, access=2(Specific people), comma-separated IDs
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n2\n12345,67890\n") 2>/dev/null
    echo "TOKEN=$DEPLOY_TELEGRAM_BOT_TOKEN USERS=$DEPLOY_TELEGRAM_ALLOWED_USERS"'
  assert_success
  assert_output --partial "TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
  assert_output --partial "USERS=12345,67890"
}

@test "messaging_setup_telegram Anyone requires y confirmation" {
  # token, confirm bot, access=3(Anyone), confirm y
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n3\ny\n") 2>/dev/null
    echo "ALLOW_ALL=$DEPLOY_GATEWAY_ALLOW_ALL_USERS"'
  assert_success
  assert_output --partial "ALLOW_ALL=true"
}

@test "messaging_setup_telegram Anyone rejected falls back" {
  # token, confirm bot, access=3(Anyone), reject n, then access=1(Only me), user ID
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n3\nn\n1\n12345\n") 2>/dev/null
    echo "USERS=$DEPLOY_TELEGRAM_ALLOWED_USERS ALLOW_ALL=[$DEPLOY_GATEWAY_ALLOW_ALL_USERS]"'
  assert_success
  assert_output --partial "USERS=12345"
  assert_output --partial "ALLOW_ALL=[]"
}

@test "messaging_setup_telegram re-prompts on non-numeric user IDs" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\nalexfazio\n12345\n") 2>&1'
  assert_success
  assert_output --partial "user IDs must be numeric"
}

@test "messaging_setup_telegram still captures token with masked input" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\n") 2>/dev/null
    echo "TOKEN=$DEPLOY_TELEGRAM_BOT_TOKEN"'
  assert_success
  assert_output --partial "TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
}

@test "messaging_setup_telegram prompts for home channel" {
  # token, confirm bot, access=1(Only me), user_id, accept default home channel
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\ny\n") 2>/dev/null
    echo "HOME_CHANNEL=$DEPLOY_TELEGRAM_HOME_CHANNEL"'
  assert_success
  assert_output --partial "HOME_CHANNEL=12345"
}

@test "messaging_setup_telegram skips home channel for Anyone" {
  # token, confirm bot, access=3(Anyone), confirm y
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n3\ny\n") 2>&1'
  assert_success
  refute_output --partial "home channel"
}

@test "messaging_setup_telegram home channel declined leaves var unset" {
  # token, confirm bot, access=1(Only me), user_id, decline home channel
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\nn\n") 2>/dev/null
    echo "HOME_CHANNEL=[${DEPLOY_TELEGRAM_HOME_CHANNEL:-}]"'
  assert_success
  assert_output --partial "HOME_CHANNEL=[]"
}

@test "messaging_setup_telegram access menu renders as table" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\n") 2>&1'
  assert_success
  assert_output --partial "Option"
  assert_output --partial "Description"
}

@test "messaging_setup_telegram shows userinfobot deep link" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source lib/ui.sh; source lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11\ny\n1\n12345\n") 2>&1'
  assert_success
  assert_output --partial "t.me/userinfobot"
}

# --- messaging_validate_telegram_token_api ---

@test "messaging_validate_telegram_token_api returns 0 and sets bot username on valid token" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    messaging_validate_telegram_token_api "123456:ValidToken"
    echo "USERNAME=$DEPLOY_TELEGRAM_BOT_USERNAME"'
  assert_success
  assert_output --partial "USERNAME=test_hermes_bot"
}

@test "messaging_validate_telegram_token_api returns 1 on invalid token" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'"; export MOCK_CURL_FAIL=true;
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    messaging_validate_telegram_token_api "bad-token"'
  assert_failure
}

@test "messaging_setup_telegram re-prompts on non-numeric user ID until valid" {
  # token, confirm bot, access=1(Only me), bad ID, good ID
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ValidToken\ny\n1\nalexfazio\n123456789\n") 2>/dev/null
    echo "USERS=$DEPLOY_TELEGRAM_ALLOWED_USERS"'
  assert_success
  assert_output --partial "USERS=123456789"
}

@test "messaging_setup_telegram shows bot identity from getMe" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ValidToken\ny\n1\n123456789\n") 2>&1'
  assert_success
  assert_output --partial "@test_hermes_bot"
}

@test "messaging_setup_telegram sets DEPLOY_MESSAGING_PLATFORM to telegram" {
  run bash -c 'export NO_COLOR=1; export PATH="'"${BATS_TEST_DIRNAME}/mocks:${PATH}"'";
    source '"${PROJECT_ROOT}"'/lib/ui.sh; source '"${PROJECT_ROOT}"'/lib/fly-helpers.sh;
    source '"${PROJECT_ROOT}"'/lib/messaging.sh;
    messaging_setup_telegram < <(printf "123456:ValidToken\ny\n1\n123456789\n") 2>/dev/null
    echo "PLATFORM=$DEPLOY_MESSAGING_PLATFORM"'
  assert_success
  assert_output --partial "PLATFORM=telegram"
}
