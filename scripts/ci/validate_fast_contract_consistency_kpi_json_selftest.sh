#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_consistency_kpi_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "kpi_version": "v1",
  "overall": "PASS",
  "consistency_pass": 1,
  "gate_pass": 1,
  "reason_codes": ["none"],
  "reason_count": 0,
  "has_inconsistency": 0,
  "expected_overall": "PASS",
  "verdict_overall": "PASS",
  "pass_rate_percent": 100.0,
  "fail_count": 0,
  "unknown_count": 0,
  "sources": {
    "consistency": "artifacts/contracts/fast-contract-consistency-status.json",
    "trend": "artifacts/contracts/fast-contract-trend.json",
    "verdict": "artifacts/contracts/fast-contract-gate-verdict.json"
  }
}
EOF

bash "$validator" "$valid_json"

invalid_json="${tmp_dir}/invalid.json"
cat >"$invalid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "kpi_version": "v1",
  "overall": "PASS",
  "consistency_pass": 1,
  "gate_pass": 1,
  "reason_codes": ["report_status_missing"],
  "reason_count": 0,
  "has_inconsistency": 1,
  "expected_overall": "PASS",
  "verdict_overall": "PASS",
  "pass_rate_percent": 100.0,
  "fail_count": 0,
  "unknown_count": 0,
  "sources": {
    "consistency": "artifacts/contracts/fast-contract-consistency-status.json",
    "trend": "artifacts/contracts/fast-contract-trend.json",
    "verdict": "artifacts/contracts/fast-contract-gate-verdict.json"
  }
}
EOF

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] consistency kpi json validator should fail inconsistent reason counters" >&2
  exit 1
fi

echo "[contracts][ok] fast contract consistency kpi json validator selftest passed"
