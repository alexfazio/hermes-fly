#!/usr/bin/env bash
# lib/docker-helpers.sh — Dockerfile and fly.toml generation
# Sourced by hermes-fly; not executable directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: source this file, do not execute directly." >&2
  exit 1
fi

# Resolve template directory relative to this script's real location (follow symlinks)
_docker_helpers_source="${BASH_SOURCE[0]}"
while [[ -L "$_docker_helpers_source" ]]; do
  _docker_helpers_link_dir="$(cd -P "$(dirname "$_docker_helpers_source")" && pwd -P)"
  _docker_helpers_source="$(readlink "$_docker_helpers_source")"
  [[ "$_docker_helpers_source" != /* ]] && _docker_helpers_source="$_docker_helpers_link_dir/$_docker_helpers_source"
done
DOCKER_HELPERS_SCRIPT_DIR="$(cd -P "$(dirname "$_docker_helpers_source")" && pwd -P)"
DOCKER_HELPERS_TEMPLATE_DIR="${DOCKER_HELPERS_SCRIPT_DIR}/../templates"
unset _docker_helpers_source _docker_helpers_link_dir

# docker_generate_dockerfile "output_dir" "hermes_version" ["channel"] ["compat_policy_version"]
#   Read templates/Dockerfile.template, substitute {{HERMES_VERSION}},
#   and write the result to output_dir/Dockerfile.
docker_generate_dockerfile() {
  local output_dir="$1"
  local version="$2"
  local channel="${3:-stable}"
  local compat_policy="${4:-unknown}"
  local template="${DOCKER_HELPERS_TEMPLATE_DIR}/Dockerfile.template"

  if [[ ! -f "$template" ]]; then
    echo "Error: template not found: $template" >&2
    return 1
  fi

  mkdir -p "$output_dir"
  # M1: escape sed replacement-significant chars (& backreference, | delimiter, / and \)
  local safe_version safe_channel safe_compat_policy
  safe_version="$(printf '%s' "$version" | sed -e 's/[&|\\/]/\\&/g')"
  safe_channel="$(printf '%s' "$channel" | sed -e 's/[&|\\/]/\\&/g')"
  safe_compat_policy="$(printf '%s' "$compat_policy" | sed -e 's/[&|\\/]/\\&/g')"
  sed \
    -e "s|{{HERMES_VERSION}}|${safe_version}|g" \
    -e "s|{{HERMES_CHANNEL}}|${safe_channel}|g" \
    -e "s|{{HERMES_COMPAT_POLICY}}|${safe_compat_policy}|g" \
    "$template" >"${output_dir}/Dockerfile"
}

# docker_generate_fly_toml "output_dir" "app_name" "region" "vm_size" "vm_memory" "volume_name" "volume_size"
#   Read templates/fly.toml.template, substitute all placeholders,
#   and write the result to output_dir/fly.toml.
docker_generate_fly_toml() {
  local output_dir="$1"
  local app_name="$2"
  local region="$3"
  local vm_size="$4"
  local vm_memory="$5"
  local volume_name="$6"
  local volume_size="$7"
  local template="${DOCKER_HELPERS_TEMPLATE_DIR}/fly.toml.template"

  if [[ ! -f "$template" ]]; then
    echo "Error: template not found: $template" >&2
    return 1
  fi

  mkdir -p "$output_dir"
  sed \
    -e "s|{{APP_NAME}}|${app_name}|g" \
    -e "s|{{REGION}}|${region}|g" \
    -e "s|{{VM_SIZE}}|${vm_size}|g" \
    -e "s|{{VM_MEMORY}}|${vm_memory}|g" \
    -e "s|{{VOLUME_NAME}}|${volume_name}|g" \
    -e "s|{{VOLUME_SIZE}}|${volume_size}|g" \
    "$template" >"${output_dir}/fly.toml"
}

# docker_generate_entrypoint "output_dir"
#   Copy templates/entrypoint.sh into output_dir/entrypoint.sh.
docker_generate_entrypoint() {
  local output_dir="$1"
  local src="${DOCKER_HELPERS_TEMPLATE_DIR}/entrypoint.sh"
  if [[ ! -f "$src" ]]; then
    echo "Error: entrypoint template not found: $src" >&2
    return 1
  fi
  mkdir -p "$output_dir"
  cp "$src" "${output_dir}/entrypoint.sh"
}

# docker_validate_dockerfile "path"
#   Validate that a Dockerfile exists and contains required directives.
#   Returns 0 if valid, 1 if not.
docker_validate_dockerfile() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "Error: file not found: $path" >&2
    return 1
  fi

  if ! grep -q '^FROM ' "$path"; then
    echo "Error: Dockerfile missing FROM directive" >&2
    return 1
  fi

  if ! grep -q '^ENTRYPOINT ' "$path"; then
    echo "Error: Dockerfile missing ENTRYPOINT directive" >&2
    return 1
  fi

  return 0
}

# docker_get_build_dir
#   Create a temporary build directory and echo its path.
docker_get_build_dir() {
  local build_dir
  build_dir="$(mktemp -d)" || {
    echo "Error: failed to create temp directory" >&2
    return 1
  }
  echo "$build_dir"
  return 0
}
