#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assertor="${script_dir}/assert_fast_contract_artifact_manifest_paths.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_v2="${tmp_dir}/manifest-v2.json"
cat >"$manifest_v2" <<'EOF'
{
  "generated_at": "2026-05-30T23:30:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v2",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/fast-contract-status-summary.json",
    "docs/reports/20260530-000000-fast-contract-gate-report.md"
  ],
  "signed_artifact_count": 3
}
EOF

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3,v2=3 bash "$assertor" "$manifest_v2"

set +e
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3 bash "$assertor" "$manifest_v2" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] version-lock selftest should fail when manifest_version is missing from version map" >&2
  exit 1
fi

echo "[contracts][ok] fast contract artifact manifest version-lock selftest passed"
