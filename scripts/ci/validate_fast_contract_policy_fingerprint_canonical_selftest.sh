#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
generator="${script_dir}/fast_contract_policy_fingerprint_json.sh"
validator="${script_dir}/validate_fast_contract_policy_fingerprint_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_json="${tmp_dir}/manifest.json"
out_json="${tmp_dir}/policy-fingerprint.json"

cat >"$manifest_json" <<'EOF'
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
  "signed_artifact_count": 11
}
EOF

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v10=10,v2=2,v1=1 bash "$generator" "$manifest_json" "$out_json"
bash "$validator" "$out_json"

python3 - "$out_json" <<'PY'
import hashlib
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

policy = payload.get("policy", {})
version_keys = list((policy.get("version_map") or {}).keys())
expected_version_keys = ["v1", "v10", "v2"]
if version_keys != expected_version_keys:
    raise SystemExit(f"[contracts][fail] expected sorted version_map keys {expected_version_keys}, got {version_keys}")

expected_canonical = '{"manifest_version":"v1","signed_artifact_count":11,"version_map":{"v1":1,"v10":10,"v2":2}}'
expected_fingerprint = hashlib.sha256(expected_canonical.encode("utf-8")).hexdigest()
actual_fingerprint = payload.get("fingerprint_sha256")
if actual_fingerprint != expected_fingerprint:
    raise SystemExit(
        "[contracts][fail] policy fingerprint canonical serialization mismatch: "
        f"expected {expected_fingerprint}, got {actual_fingerprint}"
    )

noncanonical = json.dumps(policy, sort_keys=False, indent=2)
noncanonical_fingerprint = hashlib.sha256(noncanonical.encode("utf-8")).hexdigest()
if actual_fingerprint == noncanonical_fingerprint:
    raise SystemExit("[contracts][fail] policy fingerprint unexpectedly matched non-canonical serialization")
PY

echo "[contracts][ok] fast contract policy fingerprint canonical serialization selftest passed"
