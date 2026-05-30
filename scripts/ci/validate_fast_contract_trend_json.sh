#!/usr/bin/env bash
set -euo pipefail

json_file="${1:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"

if [[ ! -f "$json_file" ]]; then
  echo "[contracts][fail] fast contract trend json not found: $json_file" >&2
  exit 1
fi

assert_contains() {
  local pattern="$1"
  if ! grep -Eq "$pattern" "$json_file"; then
    echo "[contracts][fail] missing required pattern: $pattern" >&2
    exit 1
  fi
}

assert_contains '"generated_at"[[:space:]]*:[[:space:]]*"[^"]+"'
assert_contains '"limit"[[:space:]]*:[[:space:]]*[1-9][0-9]*'
assert_contains '"count"[[:space:]]*:[[:space:]]*[0-9]+'
assert_contains '"summary"[[:space:]]*:[[:space:]]*\{'
assert_contains '"pass"[[:space:]]*:[[:space:]]*[0-9]+'
assert_contains '"fail"[[:space:]]*:[[:space:]]*[0-9]+'
assert_contains '"unknown"[[:space:]]*:[[:space:]]*[0-9]+'
assert_contains '"pass_rate_percent"[[:space:]]*:[[:space:]]*[0-9]+\.[0-9]'
assert_contains '"reports"[[:space:]]*:[[:space:]]*\['
assert_contains '"status"[[:space:]]*:[[:space:]]*"(PASS|FAIL|UNKNOWN)"'

echo "[contracts][ok] validated fast contract trend json: $json_file"
