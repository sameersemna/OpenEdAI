#!/usr/bin/env bash
set -euo pipefail

json_path="${1:-${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}}"

if [[ ! -f "$json_path" ]]; then
  echo "[contracts][fail] fast contract consistency json not found: $json_path" >&2
  exit 1
fi

python3 - "$json_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

required_top = ["generated_at", "workflow", "overall", "reason_codes", "paths", "observed", "expected_from_thresholds"]
for key in required_top:
    if key not in payload:
        raise SystemExit(f"[contracts][fail] consistency json missing key: {key}")

if payload["workflow"] != "fast-contract-gate":
    raise SystemExit("[contracts][fail] consistency workflow must be fast-contract-gate")

overall = payload["overall"]
if overall not in ("PASS", "FAIL"):
    raise SystemExit("[contracts][fail] consistency overall must be PASS or FAIL")

reason_codes = payload["reason_codes"]
if not isinstance(reason_codes, list) or not reason_codes:
    raise SystemExit("[contracts][fail] consistency reason_codes must be a non-empty array")

if any((not isinstance(code, str) or not code) for code in reason_codes):
    raise SystemExit("[contracts][fail] consistency reason codes must be non-empty strings")

if overall == "PASS" and reason_codes != ["none"]:
    raise SystemExit("[contracts][fail] PASS consistency requires reason_codes=['none']")
if overall == "FAIL" and "none" in reason_codes:
    raise SystemExit("[contracts][fail] FAIL consistency must not include reason code 'none'")

paths = payload["paths"]
for key in ("report", "status_summary", "trend", "verdict"):
    if key not in paths or not isinstance(paths[key], str) or not paths[key]:
        raise SystemExit(f"[contracts][fail] paths.{key} must be a non-empty string")

expected = payload["expected_from_thresholds"]
if expected.get("overall") not in ("PASS", "FAIL"):
    raise SystemExit("[contracts][fail] expected_from_thresholds.overall must be PASS or FAIL")
if not isinstance(expected.get("reason_codes"), list) or not expected.get("reason_codes"):
    raise SystemExit("[contracts][fail] expected_from_thresholds.reason_codes must be a non-empty array")

print(f"[contracts][ok] validated fast contract consistency json: {path}")
PY
