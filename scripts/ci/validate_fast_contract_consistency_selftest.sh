#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_consistency.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

report_ok="${tmp_dir}/ok-fast-contract-gate-report.md"
summary_json="${tmp_dir}/fast-contract-status-summary.json"
trend_json="${tmp_dir}/fast-contract-trend.json"
verdict_json="${tmp_dir}/fast-contract-gate-verdict.json"

cat >"$report_ok" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
ok
```
EOF

cat >"$summary_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "report_path": "docs/reports/synthetic.md",
  "report_status": "PASS",
  "contract_overall_status": "degraded",
  "status_require_all_up": 0,
  "auto_source_env": false,
  "api_key_hash_pepper": "missing",
  "overall": "PASS"
}
EOF

cat >"$trend_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "limit": 10,
  "count": 1,
  "summary": {
    "pass": 1,
    "fail": 0,
    "unknown": 0,
    "pass_rate_percent": 100.0
  },
  "reports": [
    {"report": "synthetic-fast-contract-gate-report.md", "timestamp": "20260530-220000", "status": "PASS"}
  ]
}
EOF

cat >"$verdict_json" <<'EOF'
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

bash "$validator" "$report_ok" "$summary_json" "$trend_json" "$verdict_json"

cat >"$verdict_json" <<'EOF'
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
    "fail": 1,
    "unknown": 0,
    "pass_rate_percent": 100.0
  }
}
EOF

set +e
bash "$validator" "$report_ok" "$summary_json" "$trend_json" "$verdict_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] consistency validator should fail when verdict observed does not match trend summary" >&2
  exit 1
fi

echo "[contracts][ok] fast contract consistency validator selftest passed"
