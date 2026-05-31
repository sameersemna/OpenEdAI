#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-step-name-order-vs-run-order-priority.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
step_first = '      - name: Validate workflow conventions heartbeat mixed-fault priority\n'
step_second = '      - name: Validate workflow conventions heartbeat unexpected-command allowlist\n'
cmd_first = '        run: make verify-workflow-conventions\n'
cmd_second = '        run: make verify-workflow-conventions-fast-contract-expected-count-selftest\n'

if step_first not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation first required step name not found')
if step_second not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation second required step name not found')
if cmd_first not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation first required run command not found')
if cmd_second not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation second required run command not found')

text = text.replace(step_first, '__TMP_STEP_ORDER_SENTINEL__\n', 1)
text = text.replace(step_second, step_first, 1)
text = text.replace('__TMP_STEP_ORDER_SENTINEL__\n', step_second, 1)

text = text.replace(cmd_first, '__TMP_RUN_ORDER_SENTINEL__\n', 1)
text = text.replace(cmd_second, cmd_first, 1)
text = text.replace('__TMP_RUN_ORDER_SENTINEL__\n', cmd_second, 1)

path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat step-name-order-vs-run-order priority fixture" >&2
  exit 1
fi

expected='required step name out of order "Validate workflow conventions heartbeat unexpected-command allowlist"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected step-name-order priority error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

priority_error_count="$(grep -Ec 'required step name out of order|required run command out of order|missing required step name|duplicate required step name|missing required run command|duplicate required run command' "$output_path" || true)"
if [[ "$priority_error_count" != "1" ]]; then
  echo "[workflow-conventions][fail] expected exactly one heartbeat ordering-priority error, got $priority_error_count" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat step-name-order-vs-run-order priority selftest passed"
