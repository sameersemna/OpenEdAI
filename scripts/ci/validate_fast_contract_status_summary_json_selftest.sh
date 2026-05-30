#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
validator="${repo_root}/scripts/ci/validate_fast_contract_status_summary_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
invalid_json="${tmp_dir}/invalid.json"

cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T21:00:00+00:00",
  "workflow": "fast-contract-gate",
  "report_path": "docs/reports/20260530-210000-fast-contract-gate-report.md",
  "report_status": "PASS",
  "contract_overall_status": "degraded",
  "status_require_all_up": 0,
  "auto_source_env": false,
  "api_key_hash_pepper": "missing",
  "overall": "PASS"
}
EOF

cat >"$invalid_json" <<'EOF'
{
  "generated_at": "2026-05-30T21:00:00+00:00",
  "workflow": "fast-contract-gate",
  "report_path": "docs/reports/20260530-210000-fast-contract-gate-report.md",
  "report_status": "FAIL",
  "contract_overall_status": "degraded",
  "status_require_all_up": 0,
  "auto_source_env": false,
  "api_key_hash_pepper": "missing",
  "overall": "PASS"
}
EOF

bash "$validator" "$valid_json"

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] validator should reject mismatched overall and report_status" >&2
  exit 1
fi

echo "[contracts][ok] fast contract status summary validator selftest passed"
