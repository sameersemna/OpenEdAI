#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_path="${tmp_dir}/fast-contract-heartbeat-conventions-manifest-step-name-order.json"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/scripts/ci/fast_contract_heartbeat_conventions_manifest.json" "$manifest_path"

python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding='utf-8'))
step_names = manifest.get('required_step_names', [])
if len(step_names) < 2:
    raise SystemExit('[workflow-conventions][fail] fixture generation expected at least two required_step_names entries')
step_names[0], step_names[1] = step_names[1], step_names[0]
manifest['required_step_names'] = step_names
path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST_PATH="$manifest_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat manifest step-name-order fixture" >&2
  exit 1
fi

expected='invalid required_step_names order (expected: Validate workflow conventions heartbeat mixed-fault priority, Validate workflow conventions heartbeat unexpected-command allowlist, Validate workflow conventions heartbeat unexpected-over-missing priority)'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat manifest step-name-order error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat manifest step-name-order selftest passed"
