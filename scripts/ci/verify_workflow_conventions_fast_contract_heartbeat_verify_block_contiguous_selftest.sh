#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-verify-block-contiguous.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
move_block = (
    '      - name: Validate workflow conventions heartbeat make-step-name lock\n'
    '        run: make verify-workflow-conventions-fast-contract-heartbeat-make-step-name-selftest\n'
)
anchor = (
    '      - name: Validate fast contract report markdown validator behavior\n'
    '        run: make fast-contract-report-validate-selftest\n'
)
if move_block not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation move block not found')
if anchor not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation anchor block not found')
text = text.replace(move_block, '', 1)
text = text.replace(anchor, anchor + '\n' + move_block, 1)
path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat verify-block contiguous fixture" >&2
  exit 1
fi

expected='invalid run command class boundary (verify-workflow command after fast-contract command: "make verify-workflow-conventions-fast-contract-heartbeat-make-step-name-selftest")'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat verify-block contiguous error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat verify-block contiguous selftest passed"
