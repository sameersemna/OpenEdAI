#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
generator="${script_dir}/fast_contract_policy_fingerprint_json.sh"
validator="${script_dir}/validate_fast_contract_policy_fingerprint_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

base_manifest="${tmp_dir}/manifest-base.json"
base_out="${tmp_dir}/fingerprint-base.json"
mut_version_manifest="${tmp_dir}/manifest-version.json"
mut_version_out="${tmp_dir}/fingerprint-version.json"
mut_count_manifest="${tmp_dir}/manifest-count.json"
mut_count_out="${tmp_dir}/fingerprint-count.json"
mut_map_out="${tmp_dir}/fingerprint-map.json"

cat >"$base_manifest" <<'EOF'
{
  "generated_at": "2026-05-31T00:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/fast-contract-status-summary.json",
    "docs/reports/20260531-000000-fast-contract-gate-report.md"
  ],
  "signed_artifact_count": 7
}
EOF

cp "$base_manifest" "$mut_version_manifest"
python3 - "$mut_version_manifest" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)
payload["manifest_version"] = "v2"
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

cp "$base_manifest" "$mut_count_manifest"
python3 - "$mut_count_manifest" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)
payload["signed_artifact_count"] = 8
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=7 bash "$generator" "$base_manifest" "$base_out"
bash "$validator" "$base_out"

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v2=7 bash "$generator" "$mut_version_manifest" "$mut_version_out"
bash "$validator" "$mut_version_out"

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=8 bash "$generator" "$mut_count_manifest" "$mut_count_out"
bash "$validator" "$mut_count_out"

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=8 bash "$generator" "$base_manifest" "$mut_map_out"
bash "$validator" "$mut_map_out"

python3 - "$base_out" "$mut_version_out" "$mut_count_out" "$mut_map_out" <<'PY'
import json
import sys

base, version_mut, count_mut, map_mut = sys.argv[1:5]

def fp(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)["fingerprint_sha256"]

base_fp = fp(base)
version_fp = fp(version_mut)
count_fp = fp(count_mut)
map_fp = fp(map_mut)

pairs = [
    ("manifest_version", base_fp, version_fp),
    ("signed_artifact_count", base_fp, count_fp),
    ("version_map", base_fp, map_fp),
]

for label, original, changed in pairs:
    if original == changed:
        raise SystemExit(f"[contracts][fail] fingerprint should change when mutating {label}")

print("[contracts][ok] policy fingerprint drift mutations produce distinct fingerprints")
PY

echo "[contracts][ok] fast contract policy fingerprint drift selftest passed"
