#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_artifact_manifest.sh"

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
    "docs/reports/20260530-000000-fast-contract-gate-report.md",
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/fast-contract-status-summary.json"
  ],
  "signed_artifact_count": 3
}
EOF

bash "$validator" "$valid_json"

invalid_json="${tmp_dir}/invalid.json"
cat >"$invalid_json" <<'EOF'
{
  "generated_at": "2026-05-30T22:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "docs/reports/20260530-000000-fast-contract-gate-report.md",
    "tmp/outside.json"
  ],
  "signed_artifact_count": 2
}
EOF

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] artifact manifest validator should fail files outside allowed prefixes" >&2
  exit 1
fi

echo "[contracts][ok] fast contract artifact manifest validator selftest passed"
