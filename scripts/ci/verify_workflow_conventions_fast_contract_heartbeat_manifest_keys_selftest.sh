#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_path="${tmp_dir}/fast-contract-heartbeat-conventions-manifest-unknown-key.json"
output_path="${tmp_dir}/verifier-output.txt"

cat >"$manifest_path" <<'EOF'
{
  "schema_version": "v1",
  "expected_job_step_count": 1,
  "required_run_commands": [
    "make verify-workflow-conventions"
  ],
  "required_step_names": [
    "Validate workflow conventions heartbeat mixed-fault priority"
  ],
  "unexpected_key": "fixture"
}
EOF

set +e
FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST_PATH="$manifest_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat manifest unknown-key fixture" >&2
  exit 1
fi

expected='unexpected top-level key "unexpected_key"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat manifest unknown-key error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat manifest unknown-key selftest passed"
