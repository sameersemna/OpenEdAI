#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-unexpected-vs-run-order-priority.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
first_run = '        run: make verify-workflow-conventions\n'
second_run = '        run: make verify-workflow-conventions-fast-contract-expected-count-selftest\n'
anchor = (
    '      - name: Validate workflow conventions policy-fingerprint-summary behavior\n'
    '        run: make verify-workflow-conventions-fast-contract-policy-fingerprint-summary-selftest\n'
)
injected = anchor + '\n      - name: Validate workflow conventions unexpected-vs-run-order priority fixture\n        run: make fast-contract-unexpected-priority-selftest\n'
if first_run not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation first required run command not found')
if second_run not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation second required run command not found')
if anchor not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation insertion anchor not found')

# Create required_run_commands order drift.
text = text.replace(first_run, '__TMP_RUN_ORDER_SENTINEL__\n', 1)
text = text.replace(second_run, first_run, 1)
text = text.replace('__TMP_RUN_ORDER_SENTINEL__\n', second_run, 1)

# Inject an unexpected fast-contract command that should win precedence.
text = text.replace(anchor, injected, 1)
path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat unexpected-vs-run-order priority fixture" >&2
  exit 1
fi

expected='unexpected fast-contract run command "make fast-contract-unexpected-priority-selftest"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected unexpected-command priority error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

priority_error_count="$(grep -Ec 'unexpected fast-contract run command|required run command out of order|missing required run command|duplicate required run command' "$output_path" || true)"
if [[ "$priority_error_count" != "1" ]]; then
  echo "[workflow-conventions][fail] expected exactly one heartbeat run-command priority error, got $priority_error_count" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat unexpected-vs-run-order priority selftest passed"
