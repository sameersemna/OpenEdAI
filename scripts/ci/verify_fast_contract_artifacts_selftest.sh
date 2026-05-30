#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${repo_root}/scripts/ci/verify_fast_contract_artifacts.sh"
consistency_validator="${repo_root}/scripts/ci/validate_fast_contract_consistency.sh"
kpi_builder="${repo_root}/scripts/ci/fast_contract_consistency_kpi_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

report_ok="${tmp_dir}/ok-fast-contract-gate-report.md"
contract_json="${tmp_dir}/contract-env-status.json"
summary_json="${tmp_dir}/fast-contract-status-summary.json"
trend_json="${tmp_dir}/fast-contract-trend.json"
verdict_json="${tmp_dir}/fast-contract-gate-verdict.json"
consistency_json="${tmp_dir}/fast-contract-consistency-status.json"
kpi_json="${tmp_dir}/fast-contract-consistency-kpi.json"

cat >"$report_ok" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
ok
```
EOF

cat >"$contract_json" <<'EOF'
{
  "mode": "status-json",
  "auto_source_env": false,
  "overall_status": "degraded",
  "status_require_all_up": 0,
  "api_key_hash_pepper": "missing",
  "services": {
    "postgres": {"host": "127.0.0.1", "port": 5432, "status": "down"},
    "redis": {"host": "127.0.0.1", "port": 6379, "status": "down"},
    "litellm": {"host": "127.0.0.1", "port": 4000, "status": "down"}
  }
}
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

bash "$consistency_validator" "$report_ok" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json"
bash "$kpi_builder" "$consistency_json" "$trend_json" "$verdict_json" "$kpi_json"
bash "$verifier" "$report_ok" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json"

report_bad="${tmp_dir}/bad-fast-contract-gate-report.md"
cat >"$report_bad" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Command: make test-ci-fast-contracts
EOF

set +e
bash "$verifier" "$report_bad" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] artifact verifier should fail when report status line is missing" >&2
  exit 1
fi

report_bad_command="${tmp_dir}/bad-command-fast-contract-gate-report.md"
cat >"$report_bad_command" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS
- Command: make test-ci-fast

## Output
```text
ok
```
EOF

set +e
bash "$verifier" "$report_bad_command" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] artifact verifier should fail when report command line is invalid" >&2
  exit 1
fi

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
bash "$verifier" "$report_ok" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] artifact verifier should fail on cross-artifact inconsistency" >&2
  exit 1
fi

echo "[contracts][ok] fast contract artifact verifier selftest passed"
