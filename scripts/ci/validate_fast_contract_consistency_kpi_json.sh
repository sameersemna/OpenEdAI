#!/usr/bin/env bash
set -euo pipefail

json_path="${1:-${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}}"

if [[ ! -f "$json_path" ]]; then
  echo "[contracts][fail] fast contract consistency kpi json not found: $json_path" >&2
  exit 1
fi

python3 - "$json_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

required_top = [
    "generated_at",
    "workflow",
    "kpi_version",
    "overall",
    "consistency_pass",
    "gate_pass",
    "reason_codes",
    "reason_count",
    "has_inconsistency",
    "expected_overall",
    "verdict_overall",
    "pass_rate_percent",
    "fail_count",
    "unknown_count",
    "sources",
]
for key in required_top:
    if key not in payload:
        raise SystemExit(f"[contracts][fail] consistency kpi json missing key: {key}")

if payload["workflow"] != "fast-contract-gate":
    raise SystemExit("[contracts][fail] consistency kpi workflow must be fast-contract-gate")
if payload["kpi_version"] != "v1":
    raise SystemExit("[contracts][fail] consistency kpi version must be v1")
if payload["overall"] not in ("PASS", "FAIL"):
    raise SystemExit("[contracts][fail] consistency kpi overall must be PASS or FAIL")
if payload["expected_overall"] not in ("PASS", "FAIL"):
    raise SystemExit("[contracts][fail] consistency kpi expected_overall must be PASS or FAIL")
if payload["verdict_overall"] not in ("PASS", "FAIL"):
    raise SystemExit("[contracts][fail] consistency kpi verdict_overall must be PASS or FAIL")

for key in ("consistency_pass", "gate_pass", "has_inconsistency"):
    if payload[key] not in (0, 1):
        raise SystemExit(f"[contracts][fail] consistency kpi {key} must be 0 or 1")

reason_codes = payload["reason_codes"]
if not isinstance(reason_codes, list) or not reason_codes:
    raise SystemExit("[contracts][fail] consistency kpi reason_codes must be a non-empty array")
if any((not isinstance(code, str) or not code) for code in reason_codes):
    raise SystemExit("[contracts][fail] consistency kpi reason_codes entries must be non-empty strings")

if not isinstance(payload["reason_count"], int) or payload["reason_count"] < 0:
    raise SystemExit("[contracts][fail] consistency kpi reason_count must be a non-negative integer")
if payload["reason_count"] == 0 and payload["has_inconsistency"] != 0:
    raise SystemExit("[contracts][fail] consistency kpi has_inconsistency must be 0 when reason_count is 0")
if payload["reason_count"] > 0 and payload["has_inconsistency"] != 1:
    raise SystemExit("[contracts][fail] consistency kpi has_inconsistency must be 1 when reason_count is > 0")

if payload["consistency_pass"] == 1 and payload["overall"] != "PASS":
    raise SystemExit("[contracts][fail] consistency_pass=1 requires overall=PASS")
if payload["consistency_pass"] == 0 and payload["overall"] != "FAIL":
    raise SystemExit("[contracts][fail] consistency_pass=0 requires overall=FAIL")

if not isinstance(payload["pass_rate_percent"], (int, float)):
    raise SystemExit("[contracts][fail] consistency kpi pass_rate_percent must be numeric")
for key in ("fail_count", "unknown_count"):
    if not isinstance(payload[key], int) or payload[key] < 0:
        raise SystemExit(f"[contracts][fail] consistency kpi {key} must be a non-negative integer")

sources = payload["sources"]
for key in ("consistency", "trend", "verdict"):
    if key not in sources or not isinstance(sources[key], str) or not sources[key]:
        raise SystemExit(f"[contracts][fail] consistency kpi sources.{key} must be a non-empty string")

print(f"[contracts][ok] validated fast contract consistency kpi json: {path}")
PY
