#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
generator="${script_dir}/generate_fast_contract_checksums.sh"
verifier="${script_dir}/verify_fast_contract_checksums.sh"
manifest_validator="${script_dir}/validate_fast_contract_artifact_manifest.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

report_path="${tmp_dir}/report.md"
contract_json="${tmp_dir}/contract-env-status.json"
summary_json="${tmp_dir}/fast-contract-status-summary.json"
trend_json="${tmp_dir}/fast-contract-trend.json"
verdict_json="${tmp_dir}/fast-contract-gate-verdict.json"
consistency_json="${tmp_dir}/fast-contract-consistency-status.json"
kpi_json="${tmp_dir}/fast-contract-consistency-kpi.json"
checksums_path="${tmp_dir}/sha256sums.txt"
manifest_path="${tmp_dir}/fast-contract-artifact-manifest.json"

cat >"$report_path" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
ok
```
EOF

cat >"$contract_json" <<'EOF'
{"mode":"status-json"}
EOF

cat >"$summary_json" <<'EOF'
{"overall":"PASS","report_status":"PASS"}
EOF

cat >"$trend_json" <<'EOF'
{"summary":{"pass":1,"fail":0,"unknown":0,"pass_rate_percent":100.0}}
EOF

cat >"$verdict_json" <<'EOF'
{"overall":"PASS","reason_codes":["none"],"observed":{"report_status":"PASS","fail":0,"unknown":0,"pass_rate_percent":100.0,"contract_overall_status":"degraded","status_require_all_up":0},"thresholds":{"max_fail":0,"max_unknown":0,"min_pass_rate":100.0}}
EOF

cat >"$consistency_json" <<'EOF'
{"overall":"PASS","reason_codes":["none"]}
EOF

cat >"$kpi_json" <<'EOF'
{"overall":"PASS","consistency_pass":1,"gate_pass":1,"reason_codes":["none"],"reason_count":0,"has_inconsistency":0,"expected_overall":"PASS","verdict_overall":"PASS","pass_rate_percent":100.0,"fail_count":0,"unknown_count":0,"workflow":"fast-contract-gate","kpi_version":"v1","generated_at":"2026-05-30T22:00:00+00:00","sources":{"consistency":"x","trend":"y","verdict":"z"}}
EOF

cat >"$manifest_path" <<EOF
{"generated_at":"2026-05-30T22:00:00+00:00","workflow":"fast-contract-gate","manifest_version":"v1","allowed_prefixes":["docs/reports/","artifacts/contracts/","${tmp_dir}/"],"files":["$report_path","$contract_json","$summary_json","$trend_json","$verdict_json","$consistency_json","$kpi_json"],"signed_artifact_count":7}
EOF

bash "$manifest_validator" "$manifest_path"
bash "$generator" "$report_path" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json" "$checksums_path" "$manifest_path"
bash "$verifier" "$checksums_path" "$manifest_path"

printf '\n' >>"$kpi_json"

set +e
bash "$verifier" "$checksums_path" "$manifest_path" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] checksum verifier should fail after artifact mutation" >&2
  exit 1
fi

cat >"$manifest_path" <<EOF
{"generated_at":"2026-05-30T22:00:00+00:00","workflow":"fast-contract-gate","manifest_version":"v1","allowed_prefixes":["docs/reports/","artifacts/contracts/"],"files":["tmp/outside.json"],"signed_artifact_count":1}
EOF

set +e
bash "$manifest_validator" "$manifest_path" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] artifact manifest validator should fail disallowed path prefix" >&2
  exit 1
fi

echo "[contracts][ok] fast contract checksum verifier selftest passed"
