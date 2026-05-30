#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assertor="${script_dir}/assert_fast_contract_artifact_manifest_paths.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/fast-contract-status-summary.json",
    "docs/reports/20260530-000000-fast-contract-gate-report.md"
  ],
  "signed_artifact_count": 3
}
EOF

bash "$assertor" "$valid_json"
FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=3 bash "$assertor" "$valid_json"
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3 bash "$assertor" "$valid_json"

invalid_non_normalized="${tmp_dir}/invalid-non-normalized.json"
cat >"$invalid_non_normalized" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "docs/reports/20260530-000000-fast-contract-gate-report.md",
    "artifacts/contracts/./contract-env-status.json"
  ],
  "signed_artifact_count": 2
}
EOF

set +e
bash "$assertor" "$invalid_non_normalized" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest path assertor should reject non-normalized paths" >&2
  exit 1
fi

invalid_duplicate="${tmp_dir}/invalid-duplicate.json"
cat >"$invalid_duplicate" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "docs/reports/20260530-000000-fast-contract-gate-report.md",
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/contract-env-status.json"
  ],
  "signed_artifact_count": 3
}
EOF

set +e
bash "$assertor" "$invalid_duplicate" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest path assertor should reject duplicate file paths" >&2
  exit 1
fi

invalid_unsorted="${tmp_dir}/invalid-unsorted.json"
cat >"$invalid_unsorted" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "docs/reports/20260530-000000-fast-contract-gate-report.md",
    "artifacts/contracts/contract-env-status.json"
  ],
  "signed_artifact_count": 2
}
EOF

set +e
bash "$assertor" "$invalid_unsorted" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest path assertor should reject unsorted file paths" >&2
  exit 1
fi

set +e
FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=4 bash "$assertor" "$valid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest path assertor should reject unexpected signed artifact count" >&2
  exit 1
fi

set +e
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=4 bash "$assertor" "$valid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest path assertor should reject version-mapped signed artifact count mismatch" >&2
  exit 1
fi

set +e
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v2=3 bash "$assertor" "$valid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest path assertor should reject missing manifest version in version map" >&2
  exit 1
fi

echo "[contracts][ok] fast contract artifact manifest path assertor selftest passed"
