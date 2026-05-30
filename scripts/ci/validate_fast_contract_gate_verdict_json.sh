#!/usr/bin/env bash
set -euo pipefail

json_path="${1:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"

if [[ ! -f "$json_path" ]]; then
  echo "[contracts][fail] fast contract gate verdict json not found: $json_path" >&2
  exit 1
fi

python3 - "$json_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

required_top_level = ["generated_at", "workflow", "overall", "reason_codes", "thresholds", "observed"]
for key in required_top_level:
    if key not in payload:
        raise SystemExit(f"[contracts][fail] missing top-level key: {key}")

if payload["workflow"] != "fast-contract-gate":
    raise SystemExit("[contracts][fail] workflow must be 'fast-contract-gate'")

overall = payload["overall"]
if overall not in ("PASS", "FAIL"):
    raise SystemExit("[contracts][fail] overall must be PASS or FAIL")

reason_codes = payload["reason_codes"]
if not isinstance(reason_codes, list) or not reason_codes:
    raise SystemExit("[contracts][fail] reason_codes must be a non-empty array")
if any((not isinstance(code, str) or not code) for code in reason_codes):
    raise SystemExit("[contracts][fail] reason_codes entries must be non-empty strings")

thresholds = payload["thresholds"]
for key in ("max_fail", "max_unknown", "min_pass_rate"):
    if key not in thresholds:
        raise SystemExit(f"[contracts][fail] thresholds missing key: {key}")

for key in ("max_fail", "max_unknown"):
    val = thresholds[key]
    if not isinstance(val, int) or val < 0:
        raise SystemExit(f"[contracts][fail] thresholds.{key} must be a non-negative integer")

mpr = thresholds["min_pass_rate"]
if not isinstance(mpr, (int, float)):
    raise SystemExit("[contracts][fail] thresholds.min_pass_rate must be numeric")
if float(mpr) < 0.0 or float(mpr) > 100.0:
    raise SystemExit("[contracts][fail] thresholds.min_pass_rate must be in [0,100]")

observed = payload["observed"]
for key in (
    "report_status",
    "contract_overall_status",
    "status_require_all_up",
    "fail",
    "unknown",
    "pass_rate_percent",
):
    if key not in observed:
        raise SystemExit(f"[contracts][fail] observed missing key: {key}")

if observed["report_status"] not in ("PASS", "FAIL", "UNKNOWN"):
    raise SystemExit("[contracts][fail] observed.report_status must be PASS, FAIL, or UNKNOWN")

if observed["contract_overall_status"] not in ("up", "degraded", "unknown"):
    raise SystemExit("[contracts][fail] observed.contract_overall_status must be up, degraded, or unknown")

if observed["status_require_all_up"] not in (0, 1):
    raise SystemExit("[contracts][fail] observed.status_require_all_up must be 0 or 1")

for key in ("fail", "unknown"):
    val = observed[key]
    if not isinstance(val, int) or val < 0:
        raise SystemExit(f"[contracts][fail] observed.{key} must be a non-negative integer")

pass_rate = observed["pass_rate_percent"]
if not isinstance(pass_rate, (int, float)):
    raise SystemExit("[contracts][fail] observed.pass_rate_percent must be numeric")
if float(pass_rate) < 0.0 or float(pass_rate) > 100.0:
    raise SystemExit("[contracts][fail] observed.pass_rate_percent must be in [0,100]")

if overall == "PASS":
    if reason_codes != ["none"]:
        raise SystemExit("[contracts][fail] PASS verdict must use reason_codes=['none']")
else:
    if "none" in reason_codes:
        raise SystemExit("[contracts][fail] FAIL verdict must not include reason code 'none'")

print(f"[contracts][ok] validated fast contract gate verdict json: {path}")
PY
