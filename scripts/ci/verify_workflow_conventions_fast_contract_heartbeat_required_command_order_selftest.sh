#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-required-command-order.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
a = '      - name: Validate workflow conventions summary error-message stability\n        run: make verify-workflow-conventions-fast-contract-summary-error-messages-selftest\n'
b = '      - name: Validate workflow conventions summary single-fault determinism\n        run: make verify-workflow-conventions-fast-contract-summary-single-fault-selftest\n'
if a not in text or b not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation order block not found')
text = text.replace(a + '\n' + b, b + '\n' + a, 1)
path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat required-command order fixture" >&2
  exit 1
fi

expected='.github/workflows/fast-contract-governance-heartbeat.yml: required run command out of order "make verify-workflow-conventions-fast-contract-summary-single-fault-selftest"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected required-command order error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat required-command order selftest passed"
