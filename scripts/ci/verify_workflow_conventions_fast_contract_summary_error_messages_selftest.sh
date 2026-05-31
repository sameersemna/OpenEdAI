#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case() {
  local fixture_path="$1"
  local expected_message="$2"
  local output_path="${tmp_dir}/$(basename "$fixture_path").out"

  set +e
  FAST_CONTRACT_HEALTH_WORKFLOW_PATH="$fixture_path" bash "$verifier" >"$output_path" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" == "0" ]]; then
    echo "[workflow-conventions][fail] verifier should fail for fixture: $fixture_path" >&2
    exit 1
  fi

  if ! grep -Fq "$expected_message" "$output_path"; then
    echo "[workflow-conventions][fail] expected verifier error message not found for fixture: $fixture_path" >&2
    echo "[workflow-conventions][fail] expected: $expected_message" >&2
    echo "[workflow-conventions][fail] actual output:" >&2
    cat "$output_path" >&2
    exit 1
  fi
}

missing_checksum_fixture="${tmp_dir}/health-contract-summary-missing-checksum.yml"
cp "${repo_root}/.github/workflows/health-contract.yml" "$missing_checksum_fixture"
python3 - "$missing_checksum_fixture" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = '            echo "- Checksum status: VERIFIED"\n'
if needle not in text:
    raise SystemExit("[workflow-conventions][fail] fixture generation checksum summary line not found")
path.write_text(text.replace(needle, "", 1), encoding="utf-8")
PY

run_case "$missing_checksum_fixture" '.github/workflows/health-contract.yml: missing fast-contract summary line "echo "- Checksum status: VERIFIED""'

missing_verdict_fixture="${tmp_dir}/health-contract-summary-missing-verdict.yml"
cp "${repo_root}/.github/workflows/health-contract.yml" "$missing_verdict_fixture"
python3 - "$missing_verdict_fixture" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = '            echo "- Verdict: $${verdict_overall} ($${verdict_reasons})"\n'
if needle not in text:
    raise SystemExit("[workflow-conventions][fail] fixture generation verdict summary line not found")
path.write_text(text.replace(needle, "", 1), encoding="utf-8")
PY

run_case "$missing_verdict_fixture" '.github/workflows/health-contract.yml: missing fast-contract summary line "echo "- Verdict: $${verdict_overall} ($${verdict_reasons})""'

swap_order_fixture="${tmp_dir}/health-contract-summary-order-swap.yml"
cp "${repo_root}/.github/workflows/health-contract.yml" "$swap_order_fixture"
python3 - "$swap_order_fixture" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old_block = (
    '            echo "- Checksum status: VERIFIED"\n'
    '            echo "- Signed artifacts: $${signed_artifact_count}"\n'
)
new_block = (
    '            echo "- Signed artifacts: $${signed_artifact_count}"\n'
    '            echo "- Checksum status: VERIFIED"\n'
)
if old_block not in text:
    raise SystemExit("[workflow-conventions][fail] fixture generation summary ordering block not found")
path.write_text(text.replace(old_block, new_block, 1), encoding="utf-8")
PY

run_case "$swap_order_fixture" '.github/workflows/health-contract.yml: fast-contract summary lines are out of required order (checksum, signed artifacts, policy fingerprint, verdict)'

echo "[workflow-conventions][ok] fast-contract summary error-message stability selftest passed"
