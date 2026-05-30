#!/usr/bin/env bash
set -euo pipefail

json_file="${1:-${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}}"

if [[ ! -f "$json_file" ]]; then
  echo "[contracts][fail] fast contract status summary json not found: $json_file" >&2
  exit 1
fi

assert_contains() {
  local pattern="$1"
  if ! grep -Eq "$pattern" "$json_file"; then
    echo "[contracts][fail] missing required pattern: $pattern" >&2
    exit 1
  fi
}

extract_value() {
  local key="$1"
  local raw
  raw="$(grep -E "\"${key}\"[[:space:]]*:" "$json_file" | head -1 || true)"
  if [[ -z "$raw" ]]; then
    echo ""
    return
  fi
  echo "$raw" | sed -E 's/^[^:]*:[[:space:]]*"?([^",}]+)"?.*$/\1/'
}

assert_contains '"generated_at"[[:space:]]*:[[:space:]]*"[^"]+"'
assert_contains '"workflow"[[:space:]]*:[[:space:]]*"fast-contract-gate"'
assert_contains '"report_path"[[:space:]]*:[[:space:]]*"[^"]+"'
assert_contains '"report_status"[[:space:]]*:[[:space:]]*"(PASS|FAIL|UNKNOWN)"'
assert_contains '"contract_overall_status"[[:space:]]*:[[:space:]]*"(up|degraded|unknown)"'
assert_contains '"status_require_all_up"[[:space:]]*:[[:space:]]*[01]'
assert_contains '"auto_source_env"[[:space:]]*:[[:space:]]*(true|false)'
assert_contains '"api_key_hash_pepper"[[:space:]]*:[[:space:]]*"(set|missing)"'
assert_contains '"overall"[[:space:]]*:[[:space:]]*"(PASS|FAIL|UNKNOWN)"'

report_status="$(extract_value report_status)"
overall="$(extract_value overall)"
if [[ -n "$report_status" && -n "$overall" && "$report_status" != "$overall" ]]; then
  echo "[contracts][fail] overall must match report_status (report_status=$report_status overall=$overall)" >&2
  exit 1
fi

echo "[contracts][ok] validated fast contract status summary JSON: $json_file"
