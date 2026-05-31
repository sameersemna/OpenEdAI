#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-required-step-name-order.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
first = '      - name: Validate workflow conventions heartbeat mixed-fault priority\n'
second = '      - name: Validate workflow conventions heartbeat unexpected-command allowlist\n'
if first not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation first required step name not found')
if second not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation second required step name not found')
text = text.replace(first, '__TMP_REQUIRED_STEP_ORDER_SENTINEL__\n', 1)
text = text.replace(second, first, 1)
text = text.replace('__TMP_REQUIRED_STEP_ORDER_SENTINEL__\n', second, 1)
path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat required-step-name-order fixture" >&2
  exit 1
fi

expected='required step name out of order "Validate workflow conventions heartbeat unexpected-command allowlist"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat required-step-name-order error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat required-step-name-order selftest passed"
