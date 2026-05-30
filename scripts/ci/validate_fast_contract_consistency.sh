#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-${FAST_CONTRACT_REPORT:-}}"
summary_json="${2:-${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}}"
trend_json="${3:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
verdict_json="${4:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"
consistency_json="${5:-${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}}"
consistency_write="${FAST_CONTRACT_CONSISTENCY_WRITE:-1}"

if [[ -z "$report_path" || ! -f "$report_path" ]]; then
  echo "[contracts][fail] fast contract report not found: ${report_path:-<empty>}" >&2
  exit 1
fi
for path in "$summary_json" "$trend_json" "$verdict_json"; do
  if [[ ! -f "$path" ]]; then
    echo "[contracts][fail] artifact not found: $path" >&2
    exit 1
  fi
done

python3 - "$report_path" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$consistency_write" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone

report_path, summary_path, trend_path, verdict_path, consistency_path, consistency_write = sys.argv[1:7]

with open(report_path, "r", encoding="utf-8") as f:
    report_text = f.read()
with open(summary_path, "r", encoding="utf-8") as f:
    summary = json.load(f)
with open(trend_path, "r", encoding="utf-8") as f:
    trend = json.load(f)
with open(verdict_path, "r", encoding="utf-8") as f:
    verdict = json.load(f)

m = re.search(r"^- Status:[ \t]*(PASS|FAIL)$", report_text, flags=re.MULTILINE)
report_status = m.group(1) if m else "UNKNOWN"

reason_codes = []

def add_reason(code, condition):
    if condition:
        reason_codes.append(code)

add_reason("report_status_missing", m is None)

summary_report_status = str(summary.get("report_status", "UNKNOWN"))
summary_overall = str(summary.get("overall", "UNKNOWN"))
add_reason("report_summary_status_mismatch", report_status != "UNKNOWN" and report_status != summary_report_status)
add_reason("summary_overall_status_mismatch", summary_overall != summary_report_status)

trend_summary = trend.get("summary", {})
trend_fail = int(trend_summary.get("fail", 0))
trend_unknown = int(trend_summary.get("unknown", 0))
trend_pass_rate = float(trend_summary.get("pass_rate_percent", 0.0))

observed = verdict.get("observed", {})
thresholds = verdict.get("thresholds", {})
verdict_reason_codes = list(verdict.get("reason_codes", []))
overall = str(verdict.get("overall", "UNKNOWN"))

add_reason("verdict_observed_report_status_mismatch", observed.get("report_status") != summary_report_status)
add_reason("verdict_observed_fail_mismatch", int(observed.get("fail", -1)) != trend_fail)
add_reason("verdict_observed_unknown_mismatch", int(observed.get("unknown", -1)) != trend_unknown)
add_reason("verdict_observed_pass_rate_mismatch", abs(float(observed.get("pass_rate_percent", -1.0)) - trend_pass_rate) > 1e-9)

max_fail = int(thresholds.get("max_fail", 0))
max_unknown = int(thresholds.get("max_unknown", 0))
min_pass_rate = float(thresholds.get("min_pass_rate", 100.0))
contract_overall_status = str(observed.get("contract_overall_status", "unknown"))
status_require_all_up = int(observed.get("status_require_all_up", 0))

expected_reasons = []
if summary_report_status != "PASS":
    expected_reasons.append("report_status_not_pass")
if trend_fail > max_fail:
    expected_reasons.append("threshold_fail_exceeded")
if trend_unknown > max_unknown:
    expected_reasons.append("threshold_unknown_exceeded")
if trend_pass_rate < min_pass_rate:
    expected_reasons.append("threshold_pass_rate_below_min")
if status_require_all_up == 1 and contract_overall_status != "up":
    expected_reasons.append("required_all_up_but_degraded")

expected_overall = "PASS" if not expected_reasons else "FAIL"
if not expected_reasons:
    expected_reasons = ["none"]

add_reason("verdict_overall_mismatch", overall != expected_overall)
add_reason("verdict_reason_codes_mismatch", verdict_reason_codes != expected_reasons)

consistency_overall = "PASS" if not reason_codes else "FAIL"
payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "workflow": "fast-contract-gate",
    "overall": consistency_overall,
    "reason_codes": reason_codes or ["none"],
    "paths": {
        "report": report_path,
        "status_summary": summary_path,
        "trend": trend_path,
        "verdict": verdict_path,
    },
    "observed": {
        "report_status": report_status,
        "summary_report_status": summary_report_status,
        "summary_overall": summary_overall,
        "trend_fail": trend_fail,
        "trend_unknown": trend_unknown,
        "trend_pass_rate_percent": trend_pass_rate,
        "verdict_overall": overall,
        "verdict_reason_codes": verdict_reason_codes,
    },
    "expected_from_thresholds": {
        "overall": expected_overall,
        "reason_codes": expected_reasons,
    },
}

if consistency_write == "1":
    with open(consistency_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"))

if consistency_overall != "PASS":
    raise SystemExit("[contracts][fail] fast contract cross-artifact consistency failed")

if consistency_write == "1":
    print(f"[contracts][ok] validated fast contract cross-artifact consistency: {consistency_path}")
else:
    print(f"[contracts][ok] validated fast contract cross-artifact consistency (read-only): {consistency_path}")
PY
