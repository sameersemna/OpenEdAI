#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-required-command-priority.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
missing = '        run: make verify-workflow-conventions-fast-contract-expected-count-selftest\n'
duplicate = '        run: make verify-workflow-conventions-fast-contract-heartbeat-canonical-selftest\n'
if missing not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation missing-command line not found')
if duplicate not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation duplicate-command line not found')
text = text.replace(missing, '', 1)
text = text.replace(duplicate, duplicate + duplicate, 1)
path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for required-command priority fixture" >&2
  exit 1
fi

expected='.github/workflows/fast-contract-governance-heartbeat.yml: missing required run command "make verify-workflow-conventions-fast-contract-expected-count-selftest"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected priority missing-command message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

required_error_count="$(grep -Ec 'missing required run command|duplicate required run command|required run command out of order' "$output_path" || true)"
if [[ "$required_error_count" != "1" ]]; then
  echo "[workflow-conventions][fail] expected exactly one heartbeat required-command error, got $required_error_count" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat required-command priority selftest passed"
