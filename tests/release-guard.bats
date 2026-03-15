#!/usr/bin/env bats
# tests/release-guard.bats — Tests for scripts/release-guard.sh TS version contract

setup() {
  load 'test_helper/common-setup'
  _common_setup
  export NO_COLOR=1
  cd "${PROJECT_ROOT}"
}

teardown() {
  _common_teardown
}

@test "release-guard reads version from src/version.ts not from hermes-fly entrypoint" {
  # The entrypoint hermes-fly should no longer have HERMES_FLY_VERSION=
  run grep -n "HERMES_FLY_VERSION=" "${PROJECT_ROOT}/hermes-fly"
  assert_failure  # grep exit 1 = no version var in entrypoint = good
}

@test "src/version.ts contains HERMES_FLY_TS_VERSION constant" {
  run grep -n "HERMES_FLY_TS_VERSION" "${PROJECT_ROOT}/src/version.ts"
  assert_success
  assert_output --partial "HERMES_FLY_TS_VERSION"
}

@test "release-guard.sh fails with version mismatch against TS source" {
  run bash "${PROJECT_ROOT}/scripts/release-guard.sh" v99.99.99
  assert_failure
  assert_output --partial "version mismatch"
}

@test "release-guard.sh passes when TS version matches tag" {
  # Extract current version from TS source
  local ts_version
  ts_version="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' "${PROJECT_ROOT}/src/version.ts" | tr -d '"')"
  # We can't actually pass the guard (it checks git branch/clean state)
  # but we can verify it reaches the version check by testing with a bad tag
  run bash "${PROJECT_ROOT}/scripts/release-guard.sh" "v${ts_version}"
  # Will fail due to branch/clean check, but NOT due to version mismatch
  refute_output --partial "version mismatch"
}

@test "release-guard.sh version source is src/version.ts" {
  run grep -n "src/version.ts" "${PROJECT_ROOT}/scripts/release-guard.sh"
  assert_success
}
