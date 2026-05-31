#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_path="${tmp_dir}/fast-contract-heartbeat-conventions-manifest-command-class-order.json"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/scripts/ci/fast_contract_heartbeat_conventions_manifest.json" "$manifest_path"

python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding='utf-8'))
commands = manifest.get('required_run_commands', [])
if len(commands) < 4:
    raise SystemExit('[workflow-conventions][fail] fixture generation expected at least four required_run_commands')

# Move a verify-workflow command from the middle to the end while preserving
# the first command, so the class-boundary ordering check is exercised.
verify_idx = None
for i, command in enumerate(commands[1:], start=1):
    if command.startswith('make verify-workflow-conventions'):
        verify_idx = i
        break
if verify_idx is None:
    raise SystemExit('[workflow-conventions][fail] fixture generation could not find non-leading verify-workflow command')

moved = commands.pop(verify_idx)
commands.append(moved)
manifest['required_run_commands'] = commands
path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST_PATH="$manifest_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat manifest command-class-order fixture" >&2
  exit 1
fi

expected='invalid required_run_commands order (verify-workflow command after fast-contract command: "'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat manifest command-class-order error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat manifest command-class-order selftest passed"
