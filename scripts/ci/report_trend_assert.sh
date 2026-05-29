#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

limit="${1:-5}"
max_fail="${2:-0}"
max_unknown="${3:-0}"
min_pass_rate="${4:-100}"

if ! [[ "$limit" =~ ^[1-9][0-9]*$ ]]; then
  echo "[trend-assert][fail] limit must be a positive integer (got: $limit)"
  exit 1
fi

if ! [[ "$max_fail" =~ ^[0-9]+$ ]]; then
  echo "[trend-assert][fail] max_fail must be a non-negative integer (got: $max_fail)"
  exit 1
fi

if ! [[ "$max_unknown" =~ ^[0-9]+$ ]]; then
  echo "[trend-assert][fail] max_unknown must be a non-negative integer (got: $max_unknown)"
  exit 1
fi

if ! [[ "$min_pass_rate" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[trend-assert][fail] min_pass_rate must be a non-negative number (got: $min_pass_rate)"
  exit 1
fi

trend_json="$(bash scripts/ci/report_trend_last_json.sh "$limit" || true)"

fail_count="$(printf '%s\n' "$trend_json" | sed -n 's/.*"fail":\([0-9][0-9]*\).*/\1/p' | head -n1)"
unknown_count="$(printf '%s\n' "$trend_json" | sed -n 's/.*"unknown":\([0-9][0-9]*\).*/\1/p' | head -n1)"
pass_rate_percent="$(printf '%s\n' "$trend_json" | sed -n 's/.*"pass_rate_percent":\([0-9][0-9]*\([.][0-9][0-9]*\)\{0,1\}\).*/\1/p' | head -n1)"

if [[ -z "$fail_count" || -z "$unknown_count" || -z "$pass_rate_percent" ]]; then
  echo "[trend-assert][fail] unable to parse trend JSON output"
  echo "[trend-assert][context] $trend_json"
  exit 1
fi

if (( fail_count > max_fail )); then
  echo "[trend-assert][fail] fail count exceeded threshold (actual=$fail_count max=$max_fail)"
  echo "[trend-assert][context] $trend_json"
  exit 1
fi

if (( unknown_count > max_unknown )); then
  echo "[trend-assert][fail] unknown count exceeded threshold (actual=$unknown_count max=$max_unknown)"
  echo "[trend-assert][context] $trend_json"
  exit 1
fi

if ! awk -v actual="$pass_rate_percent" -v min="$min_pass_rate" 'BEGIN { exit (actual + 0 >= min + 0 ? 0 : 1) }'; then
  echo "[trend-assert][fail] pass_rate_percent below threshold (actual=$pass_rate_percent min=$min_pass_rate)"
  echo "[trend-assert][context] $trend_json"
  exit 1
fi

echo "[trend-assert][ok] fail=$fail_count unknown=$unknown_count pass_rate_percent=$pass_rate_percent"
echo "[trend-assert][json] $trend_json"
