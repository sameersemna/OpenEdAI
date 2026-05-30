#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-${FAST_CONTRACT_REPORT:-}}"
summary_json="${2:-${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}}"
trend_json="${3:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
verdict_json="${4:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"

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

python3 - "$report_path" "$summary_json" "$trend_json" "$verdict_json" <<'PY'
import json
import re
import sys

report_path, summary_path, trend_path, verdict_path = sys.argv[1:5]

with open(report_path, "r", encoding="utf-8") as f:
    report_text = f.read()
with open(summary_path, "r", encoding="utf-8") as f:
    summary = json.load(f)
with open(trend_path, "r", encoding="utf-8") as f:
    trend = json.load(f)
with open(verdict_path, "r", encoding="utf-8") as f:
    verdict = json.load(f)

m = re.search(r"^- Status:[ \t]*(PASS|FAIL)$", report_text, flags=re.MULTILINE)
if not m:
    raise SystemExit("[contracts][fail] report status line not found while checking consistency")
report_status = m.group(1)

summary_report_status = str(summary.get("report_status", "UNKNOWN"))
summary_overall = str(summary.get("overall", "UNKNOWN"))
if report_status != summary_report_status:
    raise SystemExit("[contracts][fail] inconsistency: report status does not match summary.report_status")
if summary_overall != summary_report_status:
    raise SystemExit("[contracts][fail] inconsistency: summary.overall does not match summary.report_status")

trend_summary = trend.get("summary", {})
trend_fail = int(trend_summary.get("fail", 0))
trend_unknown = int(trend_summary.get("unknown", 0))
trend_pass_rate = float(trend_summary.get("pass_rate_percent", 0.0))

observed = verdict.get("observed", {})
thresholds = verdict.get("thresholds", {})
reason_codes = verdict.get("reason_codes", [])
overall = str(verdict.get("overall", "UNKNOWN"))

if observed.get("report_status") != summary_report_status:
    raise SystemExit("[contracts][fail] inconsistency: verdict.observed.report_status does not match summary.report_status")
if int(observed.get("fail", -1)) != trend_fail:
    raise SystemExit("[contracts][fail] inconsistency: verdict.observed.fail does not match trend.summary.fail")
if int(observed.get("unknown", -1)) != trend_unknown:
    raise SystemExit("[contracts][fail] inconsistency: verdict.observed.unknown does not match trend.summary.unknown")
if abs(float(observed.get("pass_rate_percent", -1.0)) - trend_pass_rate) > 1e-9:
    raise SystemExit("[contracts][fail] inconsistency: verdict.observed.pass_rate_percent does not match trend.summary.pass_rate_percent")

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

if overall != expected_overall:
    raise SystemExit("[contracts][fail] inconsistency: verdict.overall does not match computed outcome")
if list(reason_codes) != expected_reasons:
    raise SystemExit("[contracts][fail] inconsistency: verdict.reason_codes do not match computed reasons")

print("[contracts][ok] validated fast contract cross-artifact consistency")
PY
