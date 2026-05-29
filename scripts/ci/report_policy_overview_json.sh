#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

trend_limit="${TREND_LIMIT:-5}"
max_fail="${MAX_FAIL:-0}"
max_unknown="${MAX_UNKNOWN:-0}"
min_pass_rate="${MIN_PASS_RATE:-100}"

is_pos_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_non_negative_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

if ! is_pos_int "$trend_limit"; then
  echo "{\"status\":\"error\",\"error\":\"TREND_LIMIT must be a positive integer\"}"
  exit 1
fi
if ! is_non_negative_int "$max_fail"; then
  echo "{\"status\":\"error\",\"error\":\"MAX_FAIL must be a non-negative integer\"}"
  exit 1
fi
if ! is_non_negative_int "$max_unknown"; then
  echo "{\"status\":\"error\",\"error\":\"MAX_UNKNOWN must be a non-negative integer\"}"
  exit 1
fi
if ! is_non_negative_number "$min_pass_rate"; then
  echo "{\"status\":\"error\",\"error\":\"MIN_PASS_RATE must be a non-negative number\"}"
  exit 1
fi

set +e
trend_json="$(bash scripts/ci/report_trend_last_json.sh "$trend_limit" 2>&1)"
trend_rc=$?
prune_json="$(bash scripts/ci/report_prune_assert_json.sh 2>&1)"
prune_rc=$?
set -e

if [[ "$trend_rc" != "0" && "$trend_json" != \{* ]]; then
  escaped="${trend_json//"/\\"}"
  trend_json=$(printf '{"status":"error","error":"trend command failed","detail":"%s"}' "$escaped")
fi
if [[ "$prune_rc" != "0" && "$prune_json" != \{* ]]; then
  escaped="${prune_json//"/\\"}"
  prune_json=$(printf '{"status":"error","error":"prune policy command failed","detail":"%s"}' "$escaped")
fi

trend_fail="$(printf '%s\n' "$trend_json" | sed -n 's/.*"fail":\([0-9][0-9]*\).*/\1/p' | head -n1)"
trend_unknown="$(printf '%s\n' "$trend_json" | sed -n 's/.*"unknown":\([0-9][0-9]*\).*/\1/p' | head -n1)"
trend_pass_rate="$(printf '%s\n' "$trend_json" | sed -n 's/.*"pass_rate_percent":\([0-9][0-9]*\([.][0-9][0-9]*\)\{0,1\}\).*/\1/p' | head -n1)"

trend_status="error"
if [[ -n "$trend_fail" && -n "$trend_unknown" && -n "$trend_pass_rate" ]]; then
  trend_status="ok"
  if (( trend_fail > max_fail )); then
    trend_status="fail"
  fi
  if (( trend_unknown > max_unknown )); then
    trend_status="fail"
  fi
  if ! awk -v actual="$trend_pass_rate" -v min="$min_pass_rate" 'BEGIN { exit (actual + 0 >= min + 0 ? 0 : 1) }'; then
    trend_status="fail"
  fi
fi

prune_status="$(printf '%s\n' "$prune_json" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "$prune_status" ]]; then
  prune_status="error"
fi

overall="ok"
if [[ "$trend_status" != "ok" || "$prune_status" != "ok" ]]; then
  overall="fail"
fi

printf '{"status":"%s","trend_policy":{"status":"%s","config":{"limit":%s,"max_fail":%s,"max_unknown":%s,"min_pass_rate":%s},"data":%s},"prune_policy":{"status":"%s","data":%s},"meta":{"exit_codes":{"trend":%s,"prune":%s}}}\n' \
  "$overall" "$trend_status" "$trend_limit" "$max_fail" "$max_unknown" "$min_pass_rate" "$trend_json" "$prune_status" "$prune_json" "$trend_rc" "$prune_rc"

if [[ "$overall" != "ok" ]]; then
  exit 1
fi
