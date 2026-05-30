#!/usr/bin/env bash
set -euo pipefail

json_file="${1:-${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}}"

if [[ ! -f "$json_file" ]]; then
  echo "[contracts][fail] status json file not found: $json_file" >&2
  exit 1
fi

assert_contains() {
  local pattern="$1"
  if ! grep -Eq "$pattern" "$json_file"; then
    echo "[contracts][fail] missing required pattern: $pattern" >&2
    exit 1
  fi
}

assert_contains '"mode"[[:space:]]*:[[:space:]]*"status-json"'
assert_contains '"auto_source_env"[[:space:]]*:[[:space:]]*(true|false)'
assert_contains '"overall_status"[[:space:]]*:[[:space:]]*"(up|degraded)"'
assert_contains '"status_require_all_up"[[:space:]]*:[[:space:]]*[01]'
assert_contains '"api_key_hash_pepper"[[:space:]]*:[[:space:]]*"(set|missing)"'
assert_contains '"services"[[:space:]]*:[[:space:]]*\{'

for service in postgres redis litellm; do
  assert_contains "\"${service}\"[[:space:]]*:[[:space:]]*\{"
  assert_contains "\"${service}\"[^\n]*\"host\"[[:space:]]*:[[:space:]]*\"[^\"]+\""
  assert_contains "\"${service}\"[^\n]*\"port\"[[:space:]]*:[[:space:]]*[0-9]+"
  assert_contains "\"${service}\"[^\n]*\"status\"[[:space:]]*:[[:space:]]*\"(up|down)\""
done

echo "[contracts][ok] validated contract environment status JSON: $json_file"
