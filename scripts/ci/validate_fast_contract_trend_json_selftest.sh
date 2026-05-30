#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
validator="${repo_root}/scripts/ci/validate_fast_contract_trend_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
invalid_json="${tmp_dir}/invalid.json"

cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T21:00:00+00:00",
  "limit": 10,
  "count": 2,
  "summary": {
    "pass": 2,
    "fail": 0,
    "unknown": 0,
    "pass_rate_percent": 100.0
  },
  "reports": [
    {"report": "20260530-211406-fast-contract-gate-report.md", "timestamp": "20260530-211406", "status": "PASS"},
    {"report": "20260530-211357-fast-contract-gate-report.md", "timestamp": "20260530-211357", "status": "PASS"}
  ]
}
EOF

cat >"$invalid_json" <<'EOF'
{
  "generated_at": "2026-05-30T21:00:00+00:00",
  "limit": 10,
  "count": 2,
  "summary": {
    "pass": 2,
    "fail": 0,
    "unknown": 0,
    "pass_rate_percent": 100.0
  },
  "reports": [
    {"report": "20260530-211406-fast-contract-gate-report.md", "timestamp": "20260530-211406", "status": "BAD"}
  ]
}
EOF

bash "$validator" "$valid_json"

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] trend validator should reject invalid status values" >&2
  exit 1
fi

echo "[contracts][ok] fast contract trend validator selftest passed"
