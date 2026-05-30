#!/usr/bin/env bash
set -euo pipefail

summary_json="${1:-${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}}"
trend_json="${2:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
out_path="${3:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"
max_fail="${4:-${FAST_CONTRACT_MAX_FAIL:-0}}"
max_unknown="${5:-${FAST_CONTRACT_MAX_UNKNOWN:-0}}"
min_pass_rate="${6:-${FAST_CONTRACT_MIN_PASS_RATE:-100}}"

if [[ ! -f "$summary_json" ]]; then
  echo "[contracts][fail] fast contract status summary not found: $summary_json" >&2
  exit 1
fi
if [[ ! -f "$trend_json" ]]; then
  echo "[contracts][fail] fast contract trend json not found: $trend_json" >&2
  exit 1
fi

mkdir -p "$(dirname "$out_path")"

python3 - "$summary_json" "$trend_json" "$out_path" "$max_fail" "$max_unknown" "$min_pass_rate" <<'PY'
import json
import sys
from datetime import datetime, timezone

summary_path, trend_path, out_path, max_fail, max_unknown, min_pass_rate = sys.argv[1:7]
max_fail = int(max_fail)
max_unknown = int(max_unknown)
min_pass_rate = float(min_pass_rate)

with open(summary_path, "r", encoding="utf-8") as f:
    summary = json.load(f)
with open(trend_path, "r", encoding="utf-8") as f:
    trend = json.load(f)

reasons = []

report_status = str(summary.get("report_status", "UNKNOWN"))
contract_overall_status = str(summary.get("contract_overall_status", "unknown"))
status_require_all_up = int(summary.get("status_require_all_up", 0))

trend_summary = trend.get("summary", {})
fail_count = int(trend_summary.get("fail", 0))
unknown_count = int(trend_summary.get("unknown", 0))
pass_rate = float(trend_summary.get("pass_rate_percent", 0.0))

if report_status != "PASS":
    reasons.append("report_status_not_pass")
if fail_count > max_fail:
    reasons.append("threshold_fail_exceeded")
if unknown_count > max_unknown:
    reasons.append("threshold_unknown_exceeded")
if pass_rate < min_pass_rate:
    reasons.append("threshold_pass_rate_below_min")
if status_require_all_up == 1 and contract_overall_status != "up":
    reasons.append("required_all_up_but_degraded")

overall = "PASS" if not reasons else "FAIL"
if not reasons:
    reasons.append("none")

payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "workflow": "fast-contract-gate",
    "overall": overall,
    "reason_codes": reasons,
    "thresholds": {
        "max_fail": max_fail,
        "max_unknown": max_unknown,
        "min_pass_rate": min_pass_rate,
    },
    "observed": {
        "report_status": report_status,
        "contract_overall_status": contract_overall_status,
        "status_require_all_up": status_require_all_up,
        "fail": fail_count,
        "unknown": unknown_count,
        "pass_rate_percent": pass_rate,
    },
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))

print(f"[contracts][ok] wrote fast contract gate verdict: {out_path}")
print(f"[contracts][status] overall={overall} reasons={','.join(reasons)}")
PY
