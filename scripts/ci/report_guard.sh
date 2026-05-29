#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

summary_json="$(bash scripts/ci/report_latest_smoke_summary_json.sh)"
compare_json="$(bash scripts/ci/report_compare_latest_json.sh)"

summary_overall="$(printf '%s\n' "$summary_json" | sed -n 's/.*"overall":"\([^"]*\)".*/\1/p')"
compare_overall="$(printf '%s\n' "$compare_json" | sed -n 's/.*"overall":"\([^"]*\)".*/\1/p')"

if [[ "$summary_overall" != "PASS" ]]; then
  echo "[guard][fail] latest smoke summary overall is ${summary_overall:-unknown}, expected PASS"
  echo "[guard][context] $summary_json"
  exit 1
fi

if [[ "$compare_overall" != "NO_DRIFT" ]]; then
  echo "[guard][fail] latest drift compare overall is ${compare_overall:-unknown}, expected NO_DRIFT"
  echo "[guard][context] $compare_json"
  exit 1
fi

echo "[guard][ok] summary=PASS drift=NO_DRIFT"
echo "[guard][summary-json] $summary_json"
echo "[guard][compare-json] $compare_json"
