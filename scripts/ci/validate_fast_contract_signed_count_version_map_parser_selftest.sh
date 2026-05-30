#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assertor="${script_dir}/assert_fast_contract_artifact_manifest_paths.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T23:30:00+00:00",
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

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3 bash "$assertor" "$valid_json"

set +e
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1:3 bash "$assertor" "$valid_json" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] parser selftest should fail on malformed version-map format" >&2
  exit 1
fi

set +e
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=three bash "$assertor" "$valid_json" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] parser selftest should fail on non-integer version-map count" >&2
  exit 1
fi

set +e
FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3,v1=4 bash "$assertor" "$valid_json" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] parser selftest should fail on duplicate version-map entries" >&2
  exit 1
fi

echo "[contracts][ok] fast contract signed-count version-map parser selftest passed"
