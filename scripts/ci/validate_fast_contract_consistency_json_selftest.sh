#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_consistency_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "overall": "PASS",
  "reason_codes": ["none"],
  "paths": {
    "report": "docs/reports/synthetic.md",
    "status_summary": "artifacts/contracts/fast-contract-status-summary.json",
    "trend": "artifacts/contracts/fast-contract-trend.json",
    "verdict": "artifacts/contracts/fast-contract-gate-verdict.json"
  },
  "observed": {
    "report_status": "PASS",
    "summary_report_status": "PASS",
    "summary_overall": "PASS",
    "trend_fail": 0,
    "trend_unknown": 0,
    "trend_pass_rate_percent": 100.0,
    "verdict_overall": "PASS",
    "verdict_reason_codes": ["none"]
  },
  "expected_from_thresholds": {
    "overall": "PASS",
    "reason_codes": ["none"]
  }
}
EOF

bash "$validator" "$valid_json"

invalid_json="${tmp_dir}/invalid.json"
cat >"$invalid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "overall": "PASS",
  "reason_codes": ["threshold_fail_exceeded"],
  "paths": {
    "report": "docs/reports/synthetic.md",
    "status_summary": "artifacts/contracts/fast-contract-status-summary.json",
    "trend": "artifacts/contracts/fast-contract-trend.json",
    "verdict": "artifacts/contracts/fast-contract-gate-verdict.json"
  },
  "observed": {},
  "expected_from_thresholds": {
    "overall": "PASS",
    "reason_codes": ["none"]
  }
}
EOF

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] consistency json validator should fail invalid PASS reason codes" >&2
  exit 1
fi

echo "[contracts][ok] fast contract consistency json validator selftest passed"
