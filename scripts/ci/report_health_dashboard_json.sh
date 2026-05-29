#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

dashboard_lean="${DASHBOARD_LEAN:-0}"

run_json() {
  local cmd="$1"
  local output_var="$2"
  local status_var="$3"
  local output
  local status

  set +e
  output="$(eval "$cmd" 2>&1)"
  status=$?
  set -e

  printf -v "$output_var" '%s' "$output"
  printf -v "$status_var" '%s' "$status"
}

run_json "bash scripts/ci/report_latest_smoke_summary_json.sh" summary_json summary_rc
run_json "bash scripts/ci/report_compare_latest_json.sh" drift_json drift_rc
run_json "bash scripts/ci/report_trend_last_json.sh \"${TREND_LIMIT:-5}\"" trend_json trend_rc
run_json "bash scripts/ci/report_guard_all_json.sh" guard_json guard_rc
run_json "bash scripts/ci/report_policy_overview_json.sh" policy_overview_json policy_overview_rc
run_json "bash scripts/ci/report_prune_assert_json.sh" prune_policy_json prune_policy_rc

overall="PASS"
if [[ "$summary_rc" != "0" || "$drift_rc" != "0" || "$trend_rc" != "0" || "$guard_rc" != "0" || "$policy_overview_rc" != "0" || "$prune_policy_rc" != "0" ]]; then
  overall="FAIL"
fi

# If a command failed without JSON output, wrap its stderr/stdout in a compact JSON object.
if [[ "$summary_rc" != "0" && "$summary_json" != \{* ]]; then
  escaped="${summary_json//"/\\"}"
  summary_json=$(printf '{"error":"command failed","detail":"%s"}' "$escaped")
fi
if [[ "$drift_rc" != "0" && "$drift_json" != \{* ]]; then
  escaped="${drift_json//"/\\"}"
  drift_json=$(printf '{"error":"command failed","detail":"%s"}' "$escaped")
fi
if [[ "$trend_rc" != "0" && "$trend_json" != \{* ]]; then
  escaped="${trend_json//"/\\"}"
  trend_json=$(printf '{"error":"command failed","detail":"%s"}' "$escaped")
fi
if [[ "$guard_rc" != "0" && "$guard_json" != \{* ]]; then
  escaped="${guard_json//"/\\"}"
  guard_json=$(printf '{"error":"command failed","detail":"%s"}' "$escaped")
fi
if [[ "$policy_overview_rc" != "0" && "$policy_overview_json" != \{* ]]; then
  escaped="${policy_overview_json//"/\\"}"
  policy_overview_json=$(printf '{"error":"command failed","detail":"%s"}' "$escaped")
fi
if [[ "$prune_policy_rc" != "0" && "$prune_policy_json" != \{* ]]; then
  escaped="${prune_policy_json//"/\\"}"
  prune_policy_json=$(printf '{"error":"command failed","detail":"%s"}' "$escaped")
fi

if [[ "$dashboard_lean" == "1" ]]; then
  printf '{"overall":"%s","generated_at":"%s","latest_summary":%s,"latest_drift":%s,"trend":%s,"combined_guard":%s,"policy_overview":%s,"meta":{"mode":"lean","exit_codes":{"latest_summary":%s,"latest_drift":%s,"trend":%s,"combined_guard":%s,"policy_overview":%s,"prune_policy":%s}}}\n' \
    "$overall" "$(date -Iseconds)" "$summary_json" "$drift_json" "$trend_json" "$guard_json" "$policy_overview_json" "$summary_rc" "$drift_rc" "$trend_rc" "$guard_rc" "$policy_overview_rc" "$prune_policy_rc"
else
  printf '{"overall":"%s","generated_at":"%s","latest_summary":%s,"latest_drift":%s,"trend":%s,"combined_guard":%s,"policy_overview":%s,"prune_policy":%s,"meta":{"mode":"full","exit_codes":{"latest_summary":%s,"latest_drift":%s,"trend":%s,"combined_guard":%s,"policy_overview":%s,"prune_policy":%s}}}\n' \
    "$overall" "$(date -Iseconds)" "$summary_json" "$drift_json" "$trend_json" "$guard_json" "$policy_overview_json" "$prune_policy_json" "$summary_rc" "$drift_rc" "$trend_rc" "$guard_rc" "$policy_overview_rc" "$prune_policy_rc"
fi

if [[ "$overall" != "PASS" ]]; then
  exit 1
fi
