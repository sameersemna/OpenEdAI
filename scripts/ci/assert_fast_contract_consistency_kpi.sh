#!/usr/bin/env bash
set -euo pipefail

kpi_json="${1:-${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}}"
expected_consistency_pass="${2:-${FAST_CONTRACT_EXPECTED_CONSISTENCY_PASS:-1}}"
expected_gate_pass="${3:-${FAST_CONTRACT_EXPECTED_GATE_PASS:-1}}"
max_reason_count="${4:-${FAST_CONTRACT_MAX_REASON_COUNT:-0}}"

if [[ ! -f "$kpi_json" ]]; then
  echo "[contracts][fail] fast contract consistency kpi json not found: $kpi_json" >&2
  exit 1
fi

python3 - "$kpi_json" "$expected_consistency_pass" "$expected_gate_pass" "$max_reason_count" <<'PY'
import json
import sys

path, expected_consistency_pass, expected_gate_pass, max_reason_count = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

consistency_pass = int(payload.get("consistency_pass", -1))
gate_pass = int(payload.get("gate_pass", -1))
reason_count = int(payload.get("reason_count", -1))
overall = str(payload.get("overall", "UNKNOWN"))

expected_consistency_pass = int(expected_consistency_pass)
expected_gate_pass = int(expected_gate_pass)
max_reason_count = int(max_reason_count)

failures = []
if consistency_pass != expected_consistency_pass:
    failures.append(f"consistency_pass expected {expected_consistency_pass}, got {consistency_pass}")
if gate_pass != expected_gate_pass:
    failures.append(f"gate_pass expected {expected_gate_pass}, got {gate_pass}")
if reason_count > max_reason_count:
    failures.append(f"reason_count expected <= {max_reason_count}, got {reason_count}")
if expected_consistency_pass == 1 and overall != "PASS":
    failures.append(f"overall expected PASS when consistency_pass is required, got {overall}")

if failures:
    for msg in failures:
        print(f"[contracts][fail] {msg}")
    raise SystemExit(1)

print(f"[contracts][ok] fast contract consistency kpi assertions satisfied: {path}")
PY
