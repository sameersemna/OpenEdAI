#!/usr/bin/env bash
set -euo pipefail

json_path="${1:-${FAST_CONTRACT_POLICY_FINGERPRINT_JSON:-artifacts/contracts/fast-contract-policy-fingerprint.json}}"

if [[ ! -f "$json_path" ]]; then
  echo "[contracts][fail] fast contract policy fingerprint json not found: $json_path" >&2
  exit 1
fi

python3 - "$json_path" <<'PY'
import hashlib
import json
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

for key in ("generated_at", "workflow", "source_manifest", "policy", "fingerprint_sha256"):
    if key not in payload:
        raise SystemExit(f"[contracts][fail] fast contract policy fingerprint missing key: {key}")

if payload["workflow"] != "fast-contract-gate":
    raise SystemExit("[contracts][fail] fast contract policy fingerprint workflow must be fast-contract-gate")

source_manifest = payload["source_manifest"]
if not isinstance(source_manifest, str) or not source_manifest:
    raise SystemExit("[contracts][fail] source_manifest must be a non-empty string")

policy = payload["policy"]
if not isinstance(policy, dict):
    raise SystemExit("[contracts][fail] policy must be an object")

for key in ("manifest_version", "signed_artifact_count", "version_map"):
    if key not in policy:
        raise SystemExit(f"[contracts][fail] policy missing key: {key}")

manifest_version = policy["manifest_version"]
if not isinstance(manifest_version, str) or not manifest_version:
    raise SystemExit("[contracts][fail] policy.manifest_version must be a non-empty string")

signed_artifact_count = policy["signed_artifact_count"]
if not isinstance(signed_artifact_count, int) or signed_artifact_count < 1:
    raise SystemExit("[contracts][fail] policy.signed_artifact_count must be a positive integer")

version_map = policy["version_map"]
if not isinstance(version_map, dict):
    raise SystemExit("[contracts][fail] policy.version_map must be an object")
for version, count in version_map.items():
    if not isinstance(version, str) or not version:
        raise SystemExit("[contracts][fail] policy.version_map keys must be non-empty strings")
    if not isinstance(count, int) or count < 1:
        raise SystemExit("[contracts][fail] policy.version_map values must be positive integers")

fingerprint = payload["fingerprint_sha256"]
if not isinstance(fingerprint, str) or not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
    raise SystemExit("[contracts][fail] fingerprint_sha256 must be a 64-char lowercase hex sha256")

canonical = json.dumps(policy, sort_keys=True, separators=(",", ":"))
expected = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
if fingerprint != expected:
    raise SystemExit("[contracts][fail] fingerprint_sha256 mismatch for policy payload")

print(f"[contracts][ok] validated fast contract policy fingerprint json: {path}")
PY
