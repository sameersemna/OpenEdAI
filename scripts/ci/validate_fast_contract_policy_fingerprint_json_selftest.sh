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
  "generated_at": "2026-05-30T23:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/fast-contract-status-summary.json",
    "docs/reports/20260530-000000-fast-contract-gate-report.md"
  ],
  "signed_artifact_count": 7
}
EOF

FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=7 bash "$generator" "$manifest_json" "$out_json"
bash "$validator" "$out_json"

python3 - "$out_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

expected = "57604afaf50fa12afa7110685f6e246a799322157093e77243fadc23086cb08f"
actual = payload.get("fingerprint_sha256")
if actual != expected:
    raise SystemExit(f"[contracts][fail] expected fingerprint {expected}, got {actual}")
PY

tampered_json="${tmp_dir}/policy-fingerprint-tampered.json"
cp "$out_json" "$tampered_json"
python3 - "$tampered_json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)
payload["fingerprint_sha256"] = "0" * 64
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

set +e
bash "$validator" "$tampered_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] policy fingerprint validator should reject tampered fingerprint" >&2
  exit 1
fi

echo "[contracts][ok] fast contract policy fingerprint validator selftest passed"
