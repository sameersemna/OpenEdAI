#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/fast-contract-governance-heartbeat-step-name-duplicate.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
needle = '      - name: Validate workflow conventions heartbeat unexpected-command allowlist\n'
if needle not in text:
    raise SystemExit('[workflow-conventions][fail] fixture generation required step name not found')
text = text.replace(needle, needle + needle, 1)
path.write_text(text, encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat step-name duplicate fixture" >&2
  exit 1
fi

expected='.github/workflows/fast-contract-governance-heartbeat.yml: duplicate required step name "Validate workflow conventions heartbeat unexpected-command allowlist"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected step-name duplicate error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat step-name duplicate selftest passed"
