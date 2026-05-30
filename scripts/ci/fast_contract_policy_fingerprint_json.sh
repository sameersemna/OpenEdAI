#!/usr/bin/env bash
set -euo pipefail

manifest_path="${1:-${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}}"
out_path="${2:-${FAST_CONTRACT_POLICY_FINGERPRINT_JSON:-artifacts/contracts/fast-contract-policy-fingerprint.json}}"

if [[ ! -f "$manifest_path" ]]; then
  echo "[contracts][fail] fast contract artifact manifest not found: $manifest_path" >&2
  exit 1
fi

python3 - "$manifest_path" "$out_path" <<'PY'
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

manifest_path, out_path = sys.argv[1:3]

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

manifest_version = manifest.get("manifest_version")
if not isinstance(manifest_version, str) or not manifest_version:
    raise SystemExit("[contracts][fail] artifact manifest manifest_version must be a non-empty string")

signed_artifact_count = manifest.get("signed_artifact_count")
if not isinstance(signed_artifact_count, int) or signed_artifact_count < 1:
    raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must be a positive integer")

version_map_raw = os.getenv("FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION", "").strip()
version_map = {}
if version_map_raw:
    for pair in version_map_raw.split(","):
        pair = pair.strip()
        if not pair:
            continue
        if "=" not in pair:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION entries must be in <version>=<count> format")
        version, count_raw = pair.split("=", 1)
        version = version.strip()
        count_raw = count_raw.strip()
        if not version or not count_raw:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION contains empty version or count")
        if version in version_map:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION contains duplicate version entries")
        try:
            parsed_count = int(count_raw)
        except ValueError as exc:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION count values must be integers") from exc
        if parsed_count < 1:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION count values must be positive")
        version_map[version] = parsed_count

policy_payload = {
    "manifest_version": manifest_version,
    "signed_artifact_count": signed_artifact_count,
    "version_map": {k: version_map[k] for k in sorted(version_map)},
}
canonical = json.dumps(policy_payload, sort_keys=True, separators=(",", ":"))
fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()

payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "workflow": "fast-contract-gate",
    "source_manifest": manifest_path,
    "policy": policy_payload,
    "fingerprint_sha256": fingerprint,
}

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))

print(f"[contracts][ok] wrote fast contract policy fingerprint json: {out_path}")
PY
