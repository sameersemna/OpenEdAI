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
# Fast Contract Gate Report
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

python3 - "$manifest_path" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
with open(manifest_path, "r", encoding="utf-8") as f:
    payload = json.load(f)
payload["signed_artifact_count"] = payload["signed_artifact_count"] + 1
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

set +e
bash "$verifier" "$checksums_path" "$manifest_path" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] checksum verifier should fail when signed_artifact_count is tampered" >&2
  exit 1
fi

cat >"$manifest_path" <<EOF
{"generated_at":"2026-05-30T22:00:00+00:00","workflow":"fast-contract-gate","manifest_version":"v1","allowed_prefixes":["docs/reports/","artifacts/contracts/","${tmp_dir}/"],"files":["$report_path","$contract_json","$summary_json","$trend_json","$verdict_json","$consistency_json","$kpi_json"],"signed_artifact_count":7}
EOF

python3 - "$checksums_path" "$tmp_dir" <<'PY'
import sys

checksums_path = sys.argv[1]
tmp_dir = sys.argv[2]
with open(checksums_path, "r", encoding="utf-8") as f:
    lines = [line.rstrip("\n") for line in f if line.strip()]
if not lines:
    raise SystemExit("[contracts][fail] expected checksum lines for tamper selftest")
parts = lines[0].split()
parts[-1] = f"{tmp_dir}/unexpected.json"
lines[0] = "  ".join([parts[0], parts[-1]])
with open(checksums_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY

set +e
bash "$verifier" "$checksums_path" "$manifest_path" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] checksum verifier should fail when checksum file list is tampered" >&2
  exit 1
fi

echo "[contracts][ok] fast contract checksum tamper selftest passed"
