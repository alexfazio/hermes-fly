#!/usr/bin/env bash
set -euo pipefail

require_bats_binary() {
  local repo_path="$1"
  local bats_bin="${repo_path}/tests/bats/bin/bats"
  if [[ -x "${bats_bin}" ]]; then
    return 0
  fi

  cat >&2 <<EOF
error: test runner not found: ${bats_bin}
Initialize git submodules first:
  git submodule update --init --recursive
Then rerun bootstrap:
  make bootstrap
EOF
  exit 1
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

require_bats_binary "${PROJECT_ROOT}"

required_files=(
  "src/adapters/process.ts"
  "src/adapters/flyctl.ts"
  "src/commands/list.ts"
  "src/contexts/runtime/application/ports/deployment-registry.port.ts"
  "src/contexts/runtime/application/use-cases/list-deployments.ts"
  "src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts"
  "tests-ts/runtime/list-deployments.test.ts"
  "tests/list-ts-hybrid.bats"
  "tests/verify-pr-d1-list-command.bats"
  "tests/verify-pr-d1-report-content.bats"
  "scripts/verify-pr-d1-list-command.sh"
  "scripts/verify-pr-d1-report-content.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "${file}" ]]; then
    printf "Missing required file: %s\n" "${file}" >&2
    exit 1
  fi
done

npm run build
npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives
npm run test:runtime-list

tests/bats/bin/bats \
  tests/list-ts-hybrid.bats \
  tests/list.bats \
  tests/verify-pr-d1-list-command.bats \
  tests/verify-pr-d1-report-content.bats \
  tests/parity-harness.bats \
  tests/hybrid-dispatch.bats \
  tests/integration.bats

npm run build

expected_version="$(
  sed -n 's/^HERMES_FLY_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' \
    "${PROJECT_ROOT}/hermes-fly" | head -1
)"
expected_version_line="hermes-fly ${expected_version}"

assert_file_equals() {
  local path="$1"
  local expected="$2"
  local label="$3"

  if [[ "$(cat "${path}")" != "${expected}" ]]; then
    printf "Unexpected %s: %s\n" "${label}" "$(cat "${path}")" >&2
    exit 1
  fi
}

assert_empty_file() {
  local path="$1"
  local label="$2"

  if [[ -s "${path}" ]]; then
    printf "Unexpected %s: %s\n" "${label}" "$(cat "${path}")" >&2
    exit 1
  fi
}

assert_exit_code() {
  local path="$1"
  local label="$2"

  if [[ "$(cat "${path}")" != "0" ]]; then
    printf "Unexpected %s exit: %s\n" "${label}" "$(cat "${path}")" >&2
    exit 1
  fi
}

dist_flag_version_out="$(mktemp)"
dist_flag_version_err="$(mktemp)"
dist_flag_version_exit="$(mktemp)"
node dist/cli.js --version >"${dist_flag_version_out}" 2>"${dist_flag_version_err}"
printf "%s\n" "$?" >"${dist_flag_version_exit}"
assert_file_equals "${dist_flag_version_out}" "${expected_version_line}" "dist --version output"
assert_empty_file "${dist_flag_version_err}" "dist --version stderr"
assert_exit_code "${dist_flag_version_exit}" "dist --version"
rm -f "${dist_flag_version_out}" "${dist_flag_version_err}" "${dist_flag_version_exit}"

dist_command_version_out="$(mktemp)"
dist_command_version_err="$(mktemp)"
dist_command_version_exit="$(mktemp)"
node dist/cli.js version >"${dist_command_version_out}" 2>"${dist_command_version_err}"
printf "%s\n" "$?" >"${dist_command_version_exit}"
assert_file_equals "${dist_command_version_out}" "${expected_version_line}" "dist version output"
assert_empty_file "${dist_command_version_err}" "dist version stderr"
assert_exit_code "${dist_command_version_exit}" "dist version"
rm -f "${dist_command_version_out}" "${dist_command_version_err}" "${dist_command_version_exit}"

dist_root_help_out="$(mktemp)"
dist_root_help_err="$(mktemp)"
dist_root_help_exit="$(mktemp)"
node dist/cli.js help >"${dist_root_help_out}" 2>"${dist_root_help_err}"
printf "%s\n" "$?" >"${dist_root_help_exit}"
if ! grep -F "Usage: hermes-fly" "${dist_root_help_out}" >/dev/null; then
  printf "Unexpected dist help output: %s\n" "$(cat "${dist_root_help_out}")" >&2
  rm -f "${dist_root_help_out}" "${dist_root_help_err}" "${dist_root_help_exit}"
  exit 1
fi
if ! grep -F "Commands:" "${dist_root_help_out}" >/dev/null; then
  printf "Unexpected dist help output: %s\n" "$(cat "${dist_root_help_out}")" >&2
  rm -f "${dist_root_help_out}" "${dist_root_help_err}" "${dist_root_help_exit}"
  exit 1
fi
if grep -F "No deployed agents found." "${dist_root_help_out}" >/dev/null; then
  printf "Unexpected dist help output: %s\n" "$(cat "${dist_root_help_out}")" >&2
  rm -f "${dist_root_help_out}" "${dist_root_help_err}" "${dist_root_help_exit}"
  exit 1
fi
if grep -F "App Name" "${dist_root_help_out}" >/dev/null; then
  printf "Unexpected dist help output: %s\n" "$(cat "${dist_root_help_out}")" >&2
  rm -f "${dist_root_help_out}" "${dist_root_help_err}" "${dist_root_help_exit}"
  exit 1
fi
assert_empty_file "${dist_root_help_err}" "dist help stderr"
assert_exit_code "${dist_root_help_exit}" "dist help"
rm -f "${dist_root_help_out}" "${dist_root_help_err}" "${dist_root_help_exit}"

dist_subcommand_help_out="$(mktemp)"
dist_subcommand_help_err="$(mktemp)"
dist_subcommand_help_exit="$(mktemp)"
node dist/cli.js version --help >"${dist_subcommand_help_out}" 2>"${dist_subcommand_help_err}"
printf "%s\n" "$?" >"${dist_subcommand_help_exit}"
assert_file_equals "${dist_subcommand_help_out}" "${expected_version_line}" "dist version --help output"
assert_empty_file "${dist_subcommand_help_err}" "dist version --help stderr"
assert_exit_code "${dist_subcommand_help_exit}" "dist version --help"
rm -f "${dist_subcommand_help_out}" "${dist_subcommand_help_err}" "${dist_subcommand_help_exit}"

dist_unknown_out="$(mktemp)"
dist_unknown_err="$(mktemp)"
dist_unknown_exit="$(mktemp)"
node dist/cli.js version --unknown-flag >"${dist_unknown_out}" 2>"${dist_unknown_err}"
printf "%s\n" "$?" >"${dist_unknown_exit}"
assert_file_equals "${dist_unknown_out}" "${expected_version_line}" "dist version --unknown-flag output"
assert_empty_file "${dist_unknown_err}" "dist version --unknown-flag stderr"
assert_exit_code "${dist_unknown_exit}" "dist version --unknown-flag"
rm -f "${dist_unknown_out}" "${dist_unknown_err}" "${dist_unknown_exit}"

hybrid_allowlisted_version_output="$(
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version
)"
if [[ "${hybrid_allowlisted_version_output}" != "${expected_version_line}" ]]; then
  printf "Unexpected hybrid allowlisted version output: %s\n" "${hybrid_allowlisted_version_output}" >&2
  exit 1
fi

wrapper_legacy_help_out="$(mktemp)"
wrapper_legacy_help_err="$(mktemp)"
wrapper_legacy_help_exit="$(mktemp)"
wrapper_ts_help_out="$(mktemp)"
wrapper_ts_help_err="$(mktemp)"
wrapper_ts_help_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help >"${wrapper_legacy_help_out}" 2>"${wrapper_legacy_help_err}"
printf "%s\n" "$?" >"${wrapper_legacy_help_exit}"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${wrapper_ts_help_out}" 2>"${wrapper_ts_help_err}"
printf "%s\n" "$?" >"${wrapper_ts_help_exit}"

diff -u "${wrapper_legacy_help_out}" "${wrapper_ts_help_out}"
diff -u "${wrapper_legacy_help_err}" "${wrapper_ts_help_err}"
diff -u "${wrapper_legacy_help_exit}" "${wrapper_ts_help_exit}"

rm -f "${wrapper_legacy_help_out}" "${wrapper_legacy_help_err}" "${wrapper_legacy_help_exit}" \
  "${wrapper_ts_help_out}" "${wrapper_ts_help_err}" "${wrapper_ts_help_exit}"

wrapper_legacy_unknown_out="$(mktemp)"
wrapper_legacy_unknown_err="$(mktemp)"
wrapper_legacy_unknown_exit="$(mktemp)"
wrapper_ts_unknown_out="$(mktemp)"
wrapper_ts_unknown_err="$(mktemp)"
wrapper_ts_unknown_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag >"${wrapper_legacy_unknown_out}" 2>"${wrapper_legacy_unknown_err}"
printf "%s\n" "$?" >"${wrapper_legacy_unknown_exit}"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${wrapper_ts_unknown_out}" 2>"${wrapper_ts_unknown_err}"
printf "%s\n" "$?" >"${wrapper_ts_unknown_exit}"

diff -u "${wrapper_legacy_unknown_out}" "${wrapper_ts_unknown_out}"
diff -u "${wrapper_legacy_unknown_err}" "${wrapper_ts_unknown_err}"
diff -u "${wrapper_legacy_unknown_exit}" "${wrapper_ts_unknown_exit}"

rm -f "${wrapper_legacy_unknown_out}" "${wrapper_legacy_unknown_err}" "${wrapper_legacy_unknown_exit}" \
  "${wrapper_ts_unknown_out}" "${wrapper_ts_unknown_err}" "${wrapper_ts_unknown_exit}"

wrapper_legacy_ts_help_out="$(mktemp)"
wrapper_legacy_ts_help_err="$(mktemp)"
wrapper_legacy_ts_help_exit="$(mktemp)"
wrapper_ts_mode_help_out="$(mktemp)"
wrapper_ts_mode_help_err="$(mktemp)"
wrapper_ts_mode_help_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help >"${wrapper_legacy_ts_help_out}" 2>"${wrapper_legacy_ts_help_err}"
printf "%s\n" "$?" >"${wrapper_legacy_ts_help_exit}"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${wrapper_ts_mode_help_out}" 2>"${wrapper_ts_mode_help_err}"
printf "%s\n" "$?" >"${wrapper_ts_mode_help_exit}"

diff -u "${wrapper_legacy_ts_help_out}" "${wrapper_ts_mode_help_out}"
diff -u "${wrapper_legacy_ts_help_err}" "${wrapper_ts_mode_help_err}"
diff -u "${wrapper_legacy_ts_help_exit}" "${wrapper_ts_mode_help_exit}"

rm -f "${wrapper_legacy_ts_help_out}" "${wrapper_legacy_ts_help_err}" "${wrapper_legacy_ts_help_exit}" \
  "${wrapper_ts_mode_help_out}" "${wrapper_ts_mode_help_err}" "${wrapper_ts_mode_help_exit}"

wrapper_legacy_ts_unknown_out="$(mktemp)"
wrapper_legacy_ts_unknown_err="$(mktemp)"
wrapper_legacy_ts_unknown_exit="$(mktemp)"
wrapper_ts_mode_unknown_out="$(mktemp)"
wrapper_ts_mode_unknown_err="$(mktemp)"
wrapper_ts_mode_unknown_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag >"${wrapper_legacy_ts_unknown_out}" 2>"${wrapper_legacy_ts_unknown_err}"
printf "%s\n" "$?" >"${wrapper_legacy_ts_unknown_exit}"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${wrapper_ts_mode_unknown_out}" 2>"${wrapper_ts_mode_unknown_err}"
printf "%s\n" "$?" >"${wrapper_ts_mode_unknown_exit}"

diff -u "${wrapper_legacy_ts_unknown_out}" "${wrapper_ts_mode_unknown_out}"
diff -u "${wrapper_legacy_ts_unknown_err}" "${wrapper_ts_mode_unknown_err}"
diff -u "${wrapper_legacy_ts_unknown_exit}" "${wrapper_ts_mode_unknown_exit}"

rm -f "${wrapper_legacy_ts_unknown_out}" "${wrapper_legacy_ts_unknown_err}" "${wrapper_legacy_ts_unknown_exit}" \
  "${wrapper_ts_mode_unknown_out}" "${wrapper_ts_mode_unknown_err}" "${wrapper_ts_mode_unknown_exit}"

wrapper_legacy_ts_h_out="$(mktemp)"
wrapper_legacy_ts_h_err="$(mktemp)"
wrapper_legacy_ts_h_exit="$(mktemp)"
wrapper_ts_mode_h_out="$(mktemp)"
wrapper_ts_mode_h_err="$(mktemp)"
wrapper_ts_mode_h_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version -h >"${wrapper_legacy_ts_h_out}" 2>"${wrapper_legacy_ts_h_err}"
printf "%s\n" "$?" >"${wrapper_legacy_ts_h_exit}"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -h >"${wrapper_ts_mode_h_out}" 2>"${wrapper_ts_mode_h_err}"
printf "%s\n" "$?" >"${wrapper_ts_mode_h_exit}"

diff -u "${wrapper_legacy_ts_h_out}" "${wrapper_ts_mode_h_out}"
diff -u "${wrapper_legacy_ts_h_err}" "${wrapper_ts_mode_h_err}"
diff -u "${wrapper_legacy_ts_h_exit}" "${wrapper_ts_mode_h_exit}"

rm -f "${wrapper_legacy_ts_h_out}" "${wrapper_legacy_ts_h_err}" "${wrapper_legacy_ts_h_exit}" \
  "${wrapper_ts_mode_h_out}" "${wrapper_ts_mode_h_err}" "${wrapper_ts_mode_h_exit}"

wrapper_legacy_ts_v_out="$(mktemp)"
wrapper_legacy_ts_v_err="$(mktemp)"
wrapper_legacy_ts_v_exit="$(mktemp)"
wrapper_ts_mode_v_out="$(mktemp)"
wrapper_ts_mode_v_err="$(mktemp)"
wrapper_ts_mode_v_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version -V >"${wrapper_legacy_ts_v_out}" 2>"${wrapper_legacy_ts_v_err}"
printf "%s\n" "$?" >"${wrapper_legacy_ts_v_exit}"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -V >"${wrapper_ts_mode_v_out}" 2>"${wrapper_ts_mode_v_err}"
printf "%s\n" "$?" >"${wrapper_ts_mode_v_exit}"

diff -u "${wrapper_legacy_ts_v_out}" "${wrapper_ts_mode_v_out}"
diff -u "${wrapper_legacy_ts_v_err}" "${wrapper_ts_mode_v_err}"
diff -u "${wrapper_legacy_ts_v_exit}" "${wrapper_ts_mode_v_exit}"

rm -f "${wrapper_legacy_ts_v_out}" "${wrapper_legacy_ts_v_err}" "${wrapper_legacy_ts_v_exit}" \
  "${wrapper_ts_mode_v_out}" "${wrapper_ts_mode_v_err}" "${wrapper_ts_mode_v_exit}"

wrapper_legacy_ts_mixed_help_first_out="$(mktemp)"
wrapper_legacy_ts_mixed_help_first_err="$(mktemp)"
wrapper_legacy_ts_mixed_help_first_exit="$(mktemp)"
wrapper_ts_mode_mixed_help_first_out="$(mktemp)"
wrapper_ts_mode_mixed_help_first_err="$(mktemp)"
wrapper_ts_mode_mixed_help_first_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help --unknown-flag >"${wrapper_legacy_ts_mixed_help_first_out}" 2>"${wrapper_legacy_ts_mixed_help_first_err}"
printf "%s\n" "$?" >"${wrapper_legacy_ts_mixed_help_first_exit}"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help --unknown-flag >"${wrapper_ts_mode_mixed_help_first_out}" 2>"${wrapper_ts_mode_mixed_help_first_err}"
printf "%s\n" "$?" >"${wrapper_ts_mode_mixed_help_first_exit}"

diff -u "${wrapper_legacy_ts_mixed_help_first_out}" "${wrapper_ts_mode_mixed_help_first_out}"
diff -u "${wrapper_legacy_ts_mixed_help_first_err}" "${wrapper_ts_mode_mixed_help_first_err}"
diff -u "${wrapper_legacy_ts_mixed_help_first_exit}" "${wrapper_ts_mode_mixed_help_first_exit}"

rm -f "${wrapper_legacy_ts_mixed_help_first_out}" "${wrapper_legacy_ts_mixed_help_first_err}" "${wrapper_legacy_ts_mixed_help_first_exit}" \
  "${wrapper_ts_mode_mixed_help_first_out}" "${wrapper_ts_mode_mixed_help_first_err}" "${wrapper_ts_mode_mixed_help_first_exit}"

wrapper_legacy_ts_mixed_unknown_first_out="$(mktemp)"
wrapper_legacy_ts_mixed_unknown_first_err="$(mktemp)"
wrapper_legacy_ts_mixed_unknown_first_exit="$(mktemp)"
wrapper_ts_mode_mixed_unknown_first_out="$(mktemp)"
wrapper_ts_mode_mixed_unknown_first_err="$(mktemp)"
wrapper_ts_mode_mixed_unknown_first_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag --help >"${wrapper_legacy_ts_mixed_unknown_first_out}" 2>"${wrapper_legacy_ts_mixed_unknown_first_err}"
printf "%s\n" "$?" >"${wrapper_legacy_ts_mixed_unknown_first_exit}"
HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag --help >"${wrapper_ts_mode_mixed_unknown_first_out}" 2>"${wrapper_ts_mode_mixed_unknown_first_err}"
printf "%s\n" "$?" >"${wrapper_ts_mode_mixed_unknown_first_exit}"

diff -u "${wrapper_legacy_ts_mixed_unknown_first_out}" "${wrapper_ts_mode_mixed_unknown_first_out}"
diff -u "${wrapper_legacy_ts_mixed_unknown_first_err}" "${wrapper_ts_mode_mixed_unknown_first_err}"
diff -u "${wrapper_legacy_ts_mixed_unknown_first_exit}" "${wrapper_ts_mode_mixed_unknown_first_exit}"

rm -f "${wrapper_legacy_ts_mixed_unknown_first_out}" "${wrapper_legacy_ts_mixed_unknown_first_err}" "${wrapper_legacy_ts_mixed_unknown_first_exit}" \
  "${wrapper_ts_mode_mixed_unknown_first_out}" "${wrapper_ts_mode_mixed_unknown_first_err}" "${wrapper_ts_mode_mixed_unknown_first_exit}"

wrapper_legacy_h_out="$(mktemp)"
wrapper_legacy_h_err="$(mktemp)"
wrapper_legacy_h_exit="$(mktemp)"
wrapper_hybrid_h_out="$(mktemp)"
wrapper_hybrid_h_err="$(mktemp)"
wrapper_hybrid_h_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version -h >"${wrapper_legacy_h_out}" 2>"${wrapper_legacy_h_err}"
printf "%s\n" "$?" >"${wrapper_legacy_h_exit}"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -h >"${wrapper_hybrid_h_out}" 2>"${wrapper_hybrid_h_err}"
printf "%s\n" "$?" >"${wrapper_hybrid_h_exit}"

diff -u "${wrapper_legacy_h_out}" "${wrapper_hybrid_h_out}"
diff -u "${wrapper_legacy_h_err}" "${wrapper_hybrid_h_err}"
diff -u "${wrapper_legacy_h_exit}" "${wrapper_hybrid_h_exit}"

rm -f "${wrapper_legacy_h_out}" "${wrapper_legacy_h_err}" "${wrapper_legacy_h_exit}" \
  "${wrapper_hybrid_h_out}" "${wrapper_hybrid_h_err}" "${wrapper_hybrid_h_exit}"

wrapper_legacy_v_out="$(mktemp)"
wrapper_legacy_v_err="$(mktemp)"
wrapper_legacy_v_exit="$(mktemp)"
wrapper_hybrid_v_out="$(mktemp)"
wrapper_hybrid_v_err="$(mktemp)"
wrapper_hybrid_v_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version -V >"${wrapper_legacy_v_out}" 2>"${wrapper_legacy_v_err}"
printf "%s\n" "$?" >"${wrapper_legacy_v_exit}"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -V >"${wrapper_hybrid_v_out}" 2>"${wrapper_hybrid_v_err}"
printf "%s\n" "$?" >"${wrapper_hybrid_v_exit}"

diff -u "${wrapper_legacy_v_out}" "${wrapper_hybrid_v_out}"
diff -u "${wrapper_legacy_v_err}" "${wrapper_hybrid_v_err}"
diff -u "${wrapper_legacy_v_exit}" "${wrapper_hybrid_v_exit}"

rm -f "${wrapper_legacy_v_out}" "${wrapper_legacy_v_err}" "${wrapper_legacy_v_exit}" \
  "${wrapper_hybrid_v_out}" "${wrapper_hybrid_v_err}" "${wrapper_hybrid_v_exit}"

wrapper_legacy_mixed_help_first_out="$(mktemp)"
wrapper_legacy_mixed_help_first_err="$(mktemp)"
wrapper_legacy_mixed_help_first_exit="$(mktemp)"
wrapper_hybrid_mixed_help_first_out="$(mktemp)"
wrapper_hybrid_mixed_help_first_err="$(mktemp)"
wrapper_hybrid_mixed_help_first_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --help --unknown-flag >"${wrapper_legacy_mixed_help_first_out}" 2>"${wrapper_legacy_mixed_help_first_err}"
printf "%s\n" "$?" >"${wrapper_legacy_mixed_help_first_exit}"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help --unknown-flag >"${wrapper_hybrid_mixed_help_first_out}" 2>"${wrapper_hybrid_mixed_help_first_err}"
printf "%s\n" "$?" >"${wrapper_hybrid_mixed_help_first_exit}"

diff -u "${wrapper_legacy_mixed_help_first_out}" "${wrapper_hybrid_mixed_help_first_out}"
diff -u "${wrapper_legacy_mixed_help_first_err}" "${wrapper_hybrid_mixed_help_first_err}"
diff -u "${wrapper_legacy_mixed_help_first_exit}" "${wrapper_hybrid_mixed_help_first_exit}"

rm -f "${wrapper_legacy_mixed_help_first_out}" "${wrapper_legacy_mixed_help_first_err}" "${wrapper_legacy_mixed_help_first_exit}" \
  "${wrapper_hybrid_mixed_help_first_out}" "${wrapper_hybrid_mixed_help_first_err}" "${wrapper_hybrid_mixed_help_first_exit}"

wrapper_legacy_mixed_unknown_first_out="$(mktemp)"
wrapper_legacy_mixed_unknown_first_err="$(mktemp)"
wrapper_legacy_mixed_unknown_first_exit="$(mktemp)"
wrapper_hybrid_mixed_unknown_first_out="$(mktemp)"
wrapper_hybrid_mixed_unknown_first_err="$(mktemp)"
wrapper_hybrid_mixed_unknown_first_exit="$(mktemp)"

HERMES_FLY_IMPL_MODE=legacy ./hermes-fly version --unknown-flag --help >"${wrapper_legacy_mixed_unknown_first_out}" 2>"${wrapper_legacy_mixed_unknown_first_err}"
printf "%s\n" "$?" >"${wrapper_legacy_mixed_unknown_first_exit}"
HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag --help >"${wrapper_hybrid_mixed_unknown_first_out}" 2>"${wrapper_hybrid_mixed_unknown_first_err}"
printf "%s\n" "$?" >"${wrapper_hybrid_mixed_unknown_first_exit}"

diff -u "${wrapper_legacy_mixed_unknown_first_out}" "${wrapper_hybrid_mixed_unknown_first_out}"
diff -u "${wrapper_legacy_mixed_unknown_first_err}" "${wrapper_hybrid_mixed_unknown_first_err}"
diff -u "${wrapper_legacy_mixed_unknown_first_exit}" "${wrapper_hybrid_mixed_unknown_first_exit}"

rm -f "${wrapper_legacy_mixed_unknown_first_out}" "${wrapper_legacy_mixed_unknown_first_err}" "${wrapper_legacy_mixed_unknown_first_exit}" \
  "${wrapper_hybrid_mixed_unknown_first_out}" "${wrapper_hybrid_mixed_unknown_first_err}" "${wrapper_hybrid_mixed_unknown_first_exit}"

(
  set -euo pipefail
  dist_missing_tmp="$(mktemp -d)"
  dist_backup="${dist_missing_tmp}/cli.js.bak"
  trap 'if [[ -f "${dist_backup}" ]]; then mv "${dist_backup}" dist/cli.js; fi; rm -rf "${dist_missing_tmp}"' EXIT

  mv dist/cli.js "${dist_backup}"

  hybrid_help_out="${dist_missing_tmp}/hybrid-help.out"
  hybrid_help_err="${dist_missing_tmp}/hybrid-help.err"
  hybrid_help_exit="${dist_missing_tmp}/hybrid-help.exit"
  hybrid_h_out="${dist_missing_tmp}/hybrid-h.out"
  hybrid_h_err="${dist_missing_tmp}/hybrid-h.err"
  hybrid_h_exit="${dist_missing_tmp}/hybrid-h.exit"
  hybrid_v_out="${dist_missing_tmp}/hybrid-v.out"
  hybrid_v_err="${dist_missing_tmp}/hybrid-v.err"
  hybrid_v_exit="${dist_missing_tmp}/hybrid-v.exit"
  hybrid_mixed_out="${dist_missing_tmp}/hybrid-mixed.out"
  hybrid_mixed_err="${dist_missing_tmp}/hybrid-mixed.err"
  hybrid_mixed_exit="${dist_missing_tmp}/hybrid-mixed.exit"
  hybrid_unknown_help_out="${dist_missing_tmp}/hybrid-unknown-help.out"
  hybrid_unknown_help_err="${dist_missing_tmp}/hybrid-unknown-help.err"
  hybrid_unknown_help_exit="${dist_missing_tmp}/hybrid-unknown-help.exit"
  hybrid_unknown_out="${dist_missing_tmp}/hybrid-unknown.out"
  hybrid_unknown_err="${dist_missing_tmp}/hybrid-unknown.err"
  hybrid_unknown_exit="${dist_missing_tmp}/hybrid-unknown.exit"
  ts_help_out="${dist_missing_tmp}/ts-help.out"
  ts_help_err="${dist_missing_tmp}/ts-help.err"
  ts_help_exit="${dist_missing_tmp}/ts-help.exit"
  ts_h_out="${dist_missing_tmp}/ts-h.out"
  ts_h_err="${dist_missing_tmp}/ts-h.err"
  ts_h_exit="${dist_missing_tmp}/ts-h.exit"
  ts_v_out="${dist_missing_tmp}/ts-v.out"
  ts_v_err="${dist_missing_tmp}/ts-v.err"
  ts_v_exit="${dist_missing_tmp}/ts-v.exit"
  ts_help_unknown_out="${dist_missing_tmp}/ts-help-unknown.out"
  ts_help_unknown_err="${dist_missing_tmp}/ts-help-unknown.err"
  ts_help_unknown_exit="${dist_missing_tmp}/ts-help-unknown.exit"
  ts_unknown_out="${dist_missing_tmp}/ts-unknown.out"
  ts_unknown_err="${dist_missing_tmp}/ts-unknown.err"
  ts_unknown_exit="${dist_missing_tmp}/ts-unknown.exit"
  ts_mixed_out="${dist_missing_tmp}/ts-mixed.out"
  ts_mixed_err="${dist_missing_tmp}/ts-mixed.err"
  ts_mixed_exit="${dist_missing_tmp}/ts-mixed.exit"

  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${hybrid_help_out}" 2>"${hybrid_help_err}"
  printf "%s\n" "$?" >"${hybrid_help_exit}"
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -h >"${hybrid_h_out}" 2>"${hybrid_h_err}"
  printf "%s\n" "$?" >"${hybrid_h_exit}"
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -V >"${hybrid_v_out}" 2>"${hybrid_v_err}"
  printf "%s\n" "$?" >"${hybrid_v_exit}"
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help --unknown-flag >"${hybrid_mixed_out}" 2>"${hybrid_mixed_err}"
  printf "%s\n" "$?" >"${hybrid_mixed_exit}"
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag --help >"${hybrid_unknown_help_out}" 2>"${hybrid_unknown_help_err}"
  printf "%s\n" "$?" >"${hybrid_unknown_help_exit}"
  HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${hybrid_unknown_out}" 2>"${hybrid_unknown_err}"
  printf "%s\n" "$?" >"${hybrid_unknown_exit}"
  HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help >"${ts_help_out}" 2>"${ts_help_err}"
  printf "%s\n" "$?" >"${ts_help_exit}"
  HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -h >"${ts_h_out}" 2>"${ts_h_err}"
  printf "%s\n" "$?" >"${ts_h_exit}"
  HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version -V >"${ts_v_out}" 2>"${ts_v_err}"
  printf "%s\n" "$?" >"${ts_v_exit}"
  HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --help --unknown-flag >"${ts_help_unknown_out}" 2>"${ts_help_unknown_err}"
  printf "%s\n" "$?" >"${ts_help_unknown_exit}"
  HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag >"${ts_unknown_out}" 2>"${ts_unknown_err}"
  printf "%s\n" "$?" >"${ts_unknown_exit}"
  HERMES_FLY_IMPL_MODE=ts HERMES_FLY_TS_COMMANDS=version ./hermes-fly version --unknown-flag --help >"${ts_mixed_out}" 2>"${ts_mixed_err}"
  printf "%s\n" "$?" >"${ts_mixed_exit}"

  if [[ "$(cat "${hybrid_help_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected hybrid fallback version --help output: %s\n" "$(cat "${hybrid_help_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_h_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected hybrid fallback version -h output: %s\n" "$(cat "${hybrid_h_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_v_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected hybrid fallback version -V output: %s\n" "$(cat "${hybrid_v_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_mixed_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected hybrid fallback version --help --unknown-flag output: %s\n" "$(cat "${hybrid_mixed_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_unknown_help_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected hybrid fallback version --unknown-flag --help output: %s\n" "$(cat "${hybrid_unknown_help_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_unknown_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected hybrid fallback version --unknown-flag output: %s\n" "$(cat "${hybrid_unknown_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_help_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected ts fallback version --help output: %s\n" "$(cat "${ts_help_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_h_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected ts fallback version -h output: %s\n" "$(cat "${ts_h_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_v_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected ts fallback version -V output: %s\n" "$(cat "${ts_v_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_help_unknown_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected ts fallback version --help --unknown-flag output: %s\n" "$(cat "${ts_help_unknown_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_unknown_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected ts fallback version --unknown-flag output: %s\n" "$(cat "${ts_unknown_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_mixed_out}")" != "${expected_version_line}" ]]; then
    printf "Unexpected ts fallback version --unknown-flag --help output: %s\n" "$(cat "${ts_mixed_out}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_help_exit}")" != "0" ]]; then
    printf "Unexpected hybrid fallback version --help exit: %s\n" "$(cat "${hybrid_help_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_h_exit}")" != "0" ]]; then
    printf "Unexpected hybrid fallback version -h exit: %s\n" "$(cat "${hybrid_h_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_v_exit}")" != "0" ]]; then
    printf "Unexpected hybrid fallback version -V exit: %s\n" "$(cat "${hybrid_v_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_mixed_exit}")" != "0" ]]; then
    printf "Unexpected hybrid fallback version --help --unknown-flag exit: %s\n" "$(cat "${hybrid_mixed_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_unknown_help_exit}")" != "0" ]]; then
    printf "Unexpected hybrid fallback version --unknown-flag --help exit: %s\n" "$(cat "${hybrid_unknown_help_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${hybrid_unknown_exit}")" != "0" ]]; then
    printf "Unexpected hybrid fallback version --unknown-flag exit: %s\n" "$(cat "${hybrid_unknown_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_help_exit}")" != "0" ]]; then
    printf "Unexpected ts fallback version --help exit: %s\n" "$(cat "${ts_help_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_h_exit}")" != "0" ]]; then
    printf "Unexpected ts fallback version -h exit: %s\n" "$(cat "${ts_h_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_v_exit}")" != "0" ]]; then
    printf "Unexpected ts fallback version -V exit: %s\n" "$(cat "${ts_v_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_help_unknown_exit}")" != "0" ]]; then
    printf "Unexpected ts fallback version --help --unknown-flag exit: %s\n" "$(cat "${ts_help_unknown_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_unknown_exit}")" != "0" ]]; then
    printf "Unexpected ts fallback version --unknown-flag exit: %s\n" "$(cat "${ts_unknown_exit}")" >&2
    exit 1
  fi
  if [[ "$(cat "${ts_mixed_exit}")" != "0" ]]; then
    printf "Unexpected ts fallback version --unknown-flag --help exit: %s\n" "$(cat "${ts_mixed_exit}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${hybrid_help_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected hybrid fallback version --help stderr line count: %s\n" "$(wc -l < "${hybrid_help_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${hybrid_h_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected hybrid fallback version -h stderr line count: %s\n" "$(wc -l < "${hybrid_h_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${hybrid_v_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected hybrid fallback version -V stderr line count: %s\n" "$(wc -l < "${hybrid_v_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${hybrid_mixed_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected hybrid fallback version --help --unknown-flag stderr line count: %s\n" "$(wc -l < "${hybrid_mixed_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${hybrid_unknown_help_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected hybrid fallback version --unknown-flag --help stderr line count: %s\n" "$(wc -l < "${hybrid_unknown_help_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${hybrid_unknown_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected hybrid fallback version --unknown-flag stderr line count: %s\n" "$(wc -l < "${hybrid_unknown_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${ts_help_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected ts fallback version --help stderr line count: %s\n" "$(wc -l < "${ts_help_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${ts_h_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected ts fallback version -h stderr line count: %s\n" "$(wc -l < "${ts_h_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${ts_v_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected ts fallback version -V stderr line count: %s\n" "$(wc -l < "${ts_v_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${ts_help_unknown_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected ts fallback version --help --unknown-flag stderr line count: %s\n" "$(wc -l < "${ts_help_unknown_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${ts_unknown_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected ts fallback version --unknown-flag stderr line count: %s\n" "$(wc -l < "${ts_unknown_err}")" >&2
    exit 1
  fi
  if [[ "$(wc -l < "${ts_mixed_err}" | tr -d "[:space:]")" != "1" ]]; then
    printf "Unexpected ts fallback version --unknown-flag --help stderr line count: %s\n" "$(wc -l < "${ts_mixed_err}")" >&2
    exit 1
  fi

  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${hybrid_help_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${hybrid_h_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${hybrid_v_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${hybrid_mixed_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${hybrid_unknown_help_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${hybrid_unknown_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${ts_help_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${ts_h_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${ts_v_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${ts_help_unknown_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${ts_unknown_err}" >/dev/null
  grep -x "Warning: TS implementation unavailable for command 'version'; falling back to legacy" "${ts_mixed_err}" >/dev/null
)

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/config" "${tmp}/logs"

PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    source ./lib/config.sh
    config_save_app "test-app" "ord"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list >"${TMP_DIR}/out" 2>"${TMP_DIR}/err"
    printf "%s\n" "$?" >"${TMP_DIR}/exit"
  '

diff -u tests/parity/baseline/list.stdout.snap "${tmp}/out"
diff -u tests/parity/baseline/list.stderr.snap "${tmp}/err"
diff -u tests/parity/baseline/list.exit.snap "${tmp}/exit"

PATH="tests/mocks:${PATH}" HERMES_FLY_CONFIG_DIR="${tmp}/config" HERMES_FLY_LOG_DIR="${tmp}/logs" \
  TMP_DIR="${tmp}" bash -c '
    source ./lib/config.sh
    config_save_app "test-app" "ord"
    HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --help >"${TMP_DIR}/legacy-help.out" 2>"${TMP_DIR}/legacy-help.err"
    printf "%s\n" "$?" >"${TMP_DIR}/legacy-help.exit"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --help >"${TMP_DIR}/ts-help.out" 2>"${TMP_DIR}/ts-help.err"
    printf "%s\n" "$?" >"${TMP_DIR}/ts-help.exit"
    HERMES_FLY_IMPL_MODE=legacy ./hermes-fly list --unknown-flag >"${TMP_DIR}/legacy-unknown.out" 2>"${TMP_DIR}/legacy-unknown.err"
    printf "%s\n" "$?" >"${TMP_DIR}/legacy-unknown.exit"
    HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list ./hermes-fly list --unknown-flag >"${TMP_DIR}/ts-unknown.out" 2>"${TMP_DIR}/ts-unknown.err"
    printf "%s\n" "$?" >"${TMP_DIR}/ts-unknown.exit"
  '

diff -u "${tmp}/legacy-help.out" "${tmp}/ts-help.out"
diff -u "${tmp}/legacy-help.err" "${tmp}/ts-help.err"
diff -u "${tmp}/legacy-help.exit" "${tmp}/ts-help.exit"
diff -u "${tmp}/legacy-unknown.out" "${tmp}/ts-unknown.out"
diff -u "${tmp}/legacy-unknown.err" "${tmp}/ts-unknown.err"
diff -u "${tmp}/legacy-unknown.exit" "${tmp}/ts-unknown.exit"

(
  set -euo pipefail
  home_unset_tmp="$(mktemp -d)"
  trap 'rm -rf "${home_unset_tmp}"' EXIT

  mkdir -p "${home_unset_tmp}/.hermes-fly"
  cat >"${home_unset_tmp}/.hermes-fly/config.yaml" <<'YAML'
apps:
  - name: should-not-be-read-from-relative-path
    region: ord
YAML

  (
    cd "${home_unset_tmp}"
    env -u HOME -u HERMES_FLY_CONFIG_DIR HERMES_FLY_IMPL_MODE=legacy "${PROJECT_ROOT}/hermes-fly" list >legacy.out 2>legacy.err
    printf "%s\n" "$?" >legacy.exit
    env -u HOME -u HERMES_FLY_CONFIG_DIR HERMES_FLY_IMPL_MODE=hybrid HERMES_FLY_TS_COMMANDS=list "${PROJECT_ROOT}/hermes-fly" list >ts.out 2>ts.err
    printf "%s\n" "$?" >ts.exit
    diff -u legacy.out ts.out
    diff -u legacy.err ts.err
    diff -u legacy.exit ts.exit
  )
)

review3_report="docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312-review-3-implementation-report.md"
review1_plan="docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_1.md"
review2_plan="docs/plans/typescript-commander-hybrid-rewrite-pr-d1-list-command-20260312_REVIEW_2.md"

./scripts/verify-pr-d1-report-content.sh "${review3_report}" "${review1_plan}" "${review2_plan}"

printf 'PR-D1 verification passed.\n'
