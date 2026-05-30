#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_gate_verdict_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "overall": "PASS",
  "reason_codes": ["none"],
  "thresholds": {
    "max_fail": 0,
    "max_unknown": 0,
    "min_pass_rate": 100.0
  },
  "observed": {
    "report_status": "PASS",
    "contract_overall_status": "degraded",
    "status_require_all_up": 0,
    "fail": 0,
    "unknown": 0,
    "pass_rate_percent": 100.0
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
  "thresholds": {
    "max_fail": 0,
    "max_unknown": 0,
    "min_pass_rate": 100.0
  },
  "observed": {
    "report_status": "PASS",
    "contract_overall_status": "degraded",
    "status_require_all_up": 0,
    "fail": 0,
    "unknown": 0,
    "pass_rate_percent": 100.0
  }
}
EOF

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] validator should fail PASS payloads that do not use reason_codes=['none']" >&2
  exit 1
fi

echo "[contracts][ok] fast contract gate verdict json validator selftest passed"
