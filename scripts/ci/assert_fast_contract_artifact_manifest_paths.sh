#!/usr/bin/env bash
set -euo pipefail

manifest_path="${1:-${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}}"

if [[ ! -f "$manifest_path" ]]; then
  echo "[contracts][fail] fast contract artifact manifest not found: $manifest_path" >&2
  exit 1
fi

python3 - "$manifest_path" <<'PY'
import json
import os
import sys

manifest_path = sys.argv[1]

with open(manifest_path, "r", encoding="utf-8") as f:
    payload = json.load(f)

files = payload.get("files")
if not isinstance(files, list) or not files:
    raise SystemExit("[contracts][fail] artifact manifest files must be a non-empty array")

signed_artifact_count = payload.get("signed_artifact_count")
if not isinstance(signed_artifact_count, int) or signed_artifact_count < 1:
    raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must be a positive integer")
if signed_artifact_count != len(files):
    raise SystemExit("[contracts][fail] artifact manifest signed_artifact_count must match files length")

manifest_version = payload.get("manifest_version")
if not isinstance(manifest_version, str) or not manifest_version:
    raise SystemExit("[contracts][fail] artifact manifest manifest_version must be a non-empty string")

version_map_raw = os.getenv("FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION", "").strip()
if version_map_raw:
    parsed_map = {}
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
        if version in parsed_map:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION contains duplicate version entries")
        try:
            parsed_count = int(count_raw)
        except ValueError as exc:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION count values must be integers") from exc
        if parsed_count < 1:
            raise SystemExit("[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION count values must be positive")
        parsed_map[version] = parsed_count

    expected_for_version = parsed_map.get(manifest_version)
    if expected_for_version is None:
        raise SystemExit(
            f"[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION missing manifest_version={manifest_version}"
        )
    if signed_artifact_count != expected_for_version:
        raise SystemExit(
            f"[contracts][fail] artifact manifest signed_artifact_count mismatch for version {manifest_version} (actual={signed_artifact_count} expected={expected_for_version})"
        )

expected_signed_count_raw = os.getenv("FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT", "").strip()
if expected_signed_count_raw:
    try:
        expected_signed_count = int(expected_signed_count_raw)
    except ValueError as exc:
        raise SystemExit("[contracts][fail] FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT must be an integer") from exc
    if signed_artifact_count != expected_signed_count:
        raise SystemExit(
            f"[contracts][fail] artifact manifest signed_artifact_count mismatch (actual={signed_artifact_count} expected={expected_signed_count})"
        )

if files != sorted(files):
    raise SystemExit("[contracts][fail] artifact manifest files must be lexicographically sorted")

seen_normalized = set()
for entry in files:
    if not isinstance(entry, str) or not entry:
        raise SystemExit("[contracts][fail] artifact manifest files must contain non-empty strings")
    if entry != entry.strip():
        raise SystemExit(f"[contracts][fail] artifact manifest file contains leading/trailing whitespace: {entry!r}")
    if "\\" in entry:
        raise SystemExit(f"[contracts][fail] artifact manifest file must use forward slashes: {entry}")
    if entry.endswith("/"):
        raise SystemExit(f"[contracts][fail] artifact manifest file must not end with '/': {entry}")

    normalized = os.path.normpath(entry)
    if normalized != entry:
        raise SystemExit(f"[contracts][fail] artifact manifest file path is not normalized: {entry}")
    if normalized in seen_normalized:
        raise SystemExit(f"[contracts][fail] artifact manifest contains duplicate normalized file path: {entry}")
    seen_normalized.add(normalized)

print(f"[contracts][ok] asserted fast contract artifact manifest path integrity: {manifest_path}")
PY
