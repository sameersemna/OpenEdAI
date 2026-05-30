#!/usr/bin/env bash
set -euo pipefail

trend_json="${1:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
max_fail="${2:-${FAST_CONTRACT_MAX_FAIL:-0}}"
max_unknown="${3:-${FAST_CONTRACT_MAX_UNKNOWN:-0}}"
min_pass_rate="${4:-${FAST_CONTRACT_MIN_PASS_RATE:-100}}"

if [[ ! -f "$trend_json" ]]; then
  echo "[contracts][fail] fast contract trend json not found: $trend_json" >&2
  exit 1
fi

if ! [[ "$max_fail" =~ ^[0-9]+$ ]]; then
  echo "[contracts][fail] FAST_CONTRACT_MAX_FAIL must be a non-negative integer" >&2
  exit 1
fi
if ! [[ "$max_unknown" =~ ^[0-9]+$ ]]; then
  echo "[contracts][fail] FAST_CONTRACT_MAX_UNKNOWN must be a non-negative integer" >&2
  exit 1
fi
if ! [[ "$min_pass_rate" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[contracts][fail] FAST_CONTRACT_MIN_PASS_RATE must be numeric" >&2
  exit 1
fi

read -r fail_count unknown_count pass_rate < <(python3 - "$trend_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

summary = data.get('summary', {})
fail = summary.get('fail', '')
unknown = summary.get('unknown', '')
pass_rate = summary.get('pass_rate_percent', '')

print(f"{fail} {unknown} {pass_rate}")
PY
)

if [[ -z "$fail_count" || -z "$unknown_count" || -z "$pass_rate" ]]; then
  echo "[contracts][fail] unable to parse fail/unknown/pass_rate_percent from trend json" >&2
  exit 1
fi

if (( fail_count > max_fail )); then
  echo "[contracts][fail] fail count $fail_count exceeds max $max_fail" >&2
  exit 1
fi

if (( unknown_count > max_unknown )); then
  echo "[contracts][fail] unknown count $unknown_count exceeds max $max_unknown" >&2
  exit 1
fi

if ! awk -v actual="$pass_rate" -v required="$min_pass_rate" 'BEGIN { exit !(actual + 0 >= required + 0) }'; then
  echo "[contracts][fail] pass rate $pass_rate is below minimum $min_pass_rate" >&2
  exit 1
fi

echo "[contracts][ok] trend thresholds satisfied (fail=$fail_count unknown=$unknown_count pass_rate=$pass_rate)"
