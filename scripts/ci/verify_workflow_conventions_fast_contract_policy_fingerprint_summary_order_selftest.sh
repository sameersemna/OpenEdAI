#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

override_workflow="${tmp_dir}/health-contract-summary-order-drift.yml"
cp "${repo_root}/.github/workflows/health-contract.yml" "$override_workflow"

python3 - "$override_workflow" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = (
    '            echo "- Policy fingerprint (sha256): $${policy_fingerprint}"\n'
    '            verdict_overall="$$(python3 -c "import json;print(json.load(open(\'artifacts/contracts/fast-contract-gate-verdict.json\', \'r\', encoding=\'utf-8\')).get(\'overall\', \'UNKNOWN\'))")"\n'
    '            verdict_reasons="$$(python3 -c "import json;d=json.load(open(\'artifacts/contracts/fast-contract-gate-verdict.json\', \'r\', encoding=\'utf-8\'));r=d.get(\'reason_codes\', []);print(\',\'.join(r) if r else \'none\')")"\n'
    '            echo "- Verdict: $${verdict_overall} ($${verdict_reasons})"\n'
)
new = (
    '            verdict_overall="$$(python3 -c "import json;print(json.load(open(\'artifacts/contracts/fast-contract-gate-verdict.json\', \'r\', encoding=\'utf-8\')).get(\'overall\', \'UNKNOWN\'))")"\n'
    '            verdict_reasons="$$(python3 -c "import json;d=json.load(open(\'artifacts/contracts/fast-contract-gate-verdict.json\', \'r\', encoding=\'utf-8\'));r=d.get(\'reason_codes\', []);print(\',\'.join(r) if r else \'none\')")"\n'
    '            echo "- Verdict: $${verdict_overall} ($${verdict_reasons})"\n'
    '            echo "- Policy fingerprint (sha256): $${policy_fingerprint}"\n'
)
if old not in text:
    raise SystemExit("[workflow-conventions][fail] fixture generation summary ordering block not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

set +e
FAST_CONTRACT_HEALTH_WORKFLOW_PATH="$override_workflow" bash "$verifier" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail when policy fingerprint summary line order drifts" >&2
  exit 1
fi

echo "[workflow-conventions][ok] policy-fingerprint-summary-order workflow conformance selftest passed"
