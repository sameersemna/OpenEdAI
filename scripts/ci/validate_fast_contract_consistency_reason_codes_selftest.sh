#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_consistency.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

summary_json="${tmp_dir}/summary.json"
trend_json="${tmp_dir}/trend.json"
verdict_json="${tmp_dir}/verdict.json"
consistency_json="${tmp_dir}/consistency.json"

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

report_ok="${tmp_dir}/report-ok.md"
cat >"$report_ok" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
ok
```
EOF

bash "$validator" "$report_ok" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json"
python3 - "$consistency_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

if payload.get("reason_codes") != ["none"]:
    raise SystemExit("[contracts][fail] expected baseline reason codes ['none']")
PY

report_missing_status="${tmp_dir}/report-missing-status.md"
cat >"$report_missing_status" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Command: make test-ci-fast-contracts

## Output
```text
ok
```
EOF

set +e
bash "$validator" "$report_missing_status" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] expected consistency validator failure for missing report status" >&2
  exit 1
fi

python3 - "$consistency_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

expected = ["report_status_missing"]
if payload.get("reason_codes") != expected:
    raise SystemExit(f"[contracts][fail] expected reason codes {expected}, got {payload.get('reason_codes')}")
PY

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
bash "$validator" "$report_ok" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] expected consistency validator failure for observed fail mismatch" >&2
  exit 1
fi

python3 - "$consistency_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

expected = ["verdict_observed_fail_mismatch"]
if payload.get("reason_codes") != expected:
    raise SystemExit(f"[contracts][fail] expected reason codes {expected}, got {payload.get('reason_codes')}")
PY

echo "[contracts][ok] fast contract consistency reason-code stability selftest passed"
