#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

checksums_path="${1:-${FAST_CONTRACT_CHECKSUMS:-artifacts/contracts/sha256sums.txt}}"
manifest_path="${2:-${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}}"

if [[ ! -f "$checksums_path" ]]; then
  echo "[contracts][fail] checksum file not found: $checksums_path" >&2
  exit 1
fi

if [[ ! -f "$manifest_path" ]]; then
  echo "[contracts][fail] artifact manifest not found: $manifest_path" >&2
  exit 1
fi

python3 - "$checksums_path" "$manifest_path" <<'PY'
import json
import os
import sys

checksums_path, manifest_path = sys.argv[1:3]

with open(manifest_path, "r", encoding="utf-8") as f:
  manifest = json.load(f)

files = manifest.get("files", [])
allowed_prefixes = manifest.get("allowed_prefixes", [])
signed_artifact_count = manifest.get("signed_artifact_count", -1)

if not isinstance(files, list) or not files:
  raise SystemExit("[contracts][fail] artifact manifest files must be a non-empty array")
if not isinstance(allowed_prefixes, list) or not allowed_prefixes:
  raise SystemExit("[contracts][fail] artifact manifest allowed_prefixes must be a non-empty array")
if not isinstance(signed_artifact_count, int) or signed_artifact_count < 1:
  raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must be a positive integer")
if signed_artifact_count != len(files):
  raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must match files length")

expected = set(os.path.relpath(entry, start=os.getcwd()) for entry in files)
actual = []
normalized_allowed = []
for prefix in allowed_prefixes:
  if not isinstance(prefix, str) or not prefix:
    continue
  normalized_allowed.append((prefix, os.path.abspath(prefix.rstrip("/"))))

if not normalized_allowed:
  raise SystemExit("[contracts][fail] artifact manifest allowed_prefixes could not be normalized")

with open(checksums_path, "r", encoding="utf-8") as f:
  for line in f:
    line = line.strip()
    if not line:
      continue
    parts = line.split()
    if len(parts) < 2:
      raise SystemExit(f"[contracts][fail] malformed checksum line: {line}")
    actual.append(parts[-1])

if len(actual) != signed_artifact_count:
  raise SystemExit(f"[contracts][fail] checksum entry count does not match manifest signed_artifact_count (actual={len(actual)} expected={signed_artifact_count})")

actual_set = set(actual)
if actual_set != expected:
  missing = sorted(expected - actual_set)
  extra = sorted(actual_set - expected)
  if missing:
    raise SystemExit(f"[contracts][fail] checksum entries missing manifest files: {', '.join(missing)}")
  raise SystemExit(f"[contracts][fail] checksum entries include unexpected files: {', '.join(extra)}")

for entry in actual:
  abs_entry = os.path.abspath(entry)
  if not any(entry.startswith(prefix) or abs_entry == abs_prefix or abs_entry.startswith(abs_prefix + os.sep) for prefix, abs_prefix in normalized_allowed):
    raise SystemExit(f"[contracts][fail] checksum path outside allowed prefixes: {entry}")

print(f"[contracts][ok] checksum file paths match artifact manifest: {checksums_path}")
print(f"[contracts][ok] signed artifact count: {signed_artifact_count}")
PY

sha256sum -c "$checksums_path"

echo "[contracts][ok] verified fast contract checksums: $checksums_path"
