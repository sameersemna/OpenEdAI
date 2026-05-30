#!/usr/bin/env bash
set -euo pipefail

manifest_path="${1:-${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}}"

if [[ ! -f "$manifest_path" ]]; then
  echo "[contracts][fail] fast contract artifact manifest not found: $manifest_path" >&2
  exit 1
fi

python3 - "$manifest_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

required = ["generated_at", "workflow", "manifest_version", "allowed_prefixes", "files", "signed_artifact_count"]
for key in required:
    if key not in payload:
        raise SystemExit(f"[contracts][fail] artifact manifest missing key: {key}")

if payload["workflow"] != "fast-contract-gate":
    raise SystemExit("[contracts][fail] artifact manifest workflow must be fast-contract-gate")
if payload["manifest_version"] != "v1":
    raise SystemExit("[contracts][fail] artifact manifest version must be v1")

allowed_prefixes = payload["allowed_prefixes"]
if not isinstance(allowed_prefixes, list) or not allowed_prefixes:
    raise SystemExit("[contracts][fail] artifact manifest allowed_prefixes must be a non-empty array")
if any((not isinstance(prefix, str) or not prefix) for prefix in allowed_prefixes):
    raise SystemExit("[contracts][fail] artifact manifest allowed_prefixes entries must be non-empty strings")

files = payload["files"]
if not isinstance(files, list) or not files:
    raise SystemExit("[contracts][fail] artifact manifest files must be a non-empty array")
if len(set(files)) != len(files):
    raise SystemExit("[contracts][fail] artifact manifest files must be unique")
if any((not isinstance(entry, str) or not entry) for entry in files):
    raise SystemExit("[contracts][fail] artifact manifest files must contain non-empty strings")

for entry in files:
    if not any(entry.startswith(prefix) for prefix in allowed_prefixes):
        raise SystemExit(f"[contracts][fail] artifact manifest file outside allowed prefixes: {entry}")

signed_artifact_count = payload["signed_artifact_count"]
if not isinstance(signed_artifact_count, int) or signed_artifact_count < 1:
    raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must be a positive integer")
if signed_artifact_count != len(files):
    raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must match files length")

print(f"[contracts][ok] validated fast contract artifact manifest: {path}")
PY
