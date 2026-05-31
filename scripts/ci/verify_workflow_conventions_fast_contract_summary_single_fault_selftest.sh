#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_path="${tmp_dir}/health-contract-summary-multi-fault.yml"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/.github/workflows/health-contract.yml" "$fixture_path"

python3 - "$fixture_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needles = [
    '            echo "- Checksum status: VERIFIED"\n',
    '            echo "- Verdict: $${verdict_overall} ($${verdict_reasons})"\n',
]
for needle in needles:
    if needle not in text:
        raise SystemExit("[workflow-conventions][fail] fixture generation summary line not found")
    text = text.replace(needle, "", 1)
path.write_text(text, encoding="utf-8")
PY

set +e
FAST_CONTRACT_HEALTH_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for multi-fault summary fixture" >&2
  exit 1
fi

expected='.github/workflows/health-contract.yml: missing fast-contract summary line "echo "- Checksum status: VERIFIED""'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected first summary-line error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

summary_error_count="$(grep -Ec 'fast-contract summary line|out of required order' "$output_path" || true)"
if [[ "$summary_error_count" != "1" ]]; then
  echo "[workflow-conventions][fail] expected exactly one summary-line error, got $summary_error_count" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] fast-contract summary single-fault determinism selftest passed"
