#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_path="${tmp_dir}/fast-contract-heartbeat-conventions-manifest-command-class-priority.json"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/scripts/ci/fast_contract_heartbeat_conventions_manifest.json" "$manifest_path"

python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding='utf-8'))
commands = manifest.get('required_run_commands', [])
if len(commands) < 6:
    raise SystemExit('[workflow-conventions][fail] fixture generation expected at least six required_run_commands')

# Move two verify-workflow commands from the verify block tail to the end so
# both violate class ordering; the first moved command must win deterministically.
verify_indexes = [
    idx
    for idx, command in enumerate(commands)
    if idx > 0 and command.startswith('make verify-workflow-conventions')
]
if len(verify_indexes) < 2:
    raise SystemExit('[workflow-conventions][fail] fixture generation expected at least two non-leading verify-workflow commands')

move_indexes = verify_indexes[-2:]
moved_commands = [commands[i] for i in move_indexes]
commands = [command for i, command in enumerate(commands) if i not in set(move_indexes)]
commands.extend(moved_commands)
manifest['required_run_commands'] = commands
path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST_PATH="$manifest_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat manifest command-class-priority fixture" >&2
  exit 1
fi

expected='.json: invalid required_run_commands order (verify-workflow command after fast-contract command: "make verify-workflow-conventions-fast-contract-heartbeat-step-count-selftest")'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat manifest command-class-priority error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat manifest command-class-priority selftest passed"
