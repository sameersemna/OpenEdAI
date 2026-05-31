#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

override_workflow="${tmp_dir}/fast-contract-governance-heartbeat-missing-canonical.yml"
cp "${repo_root}/.github/workflows/fast-contract-governance-heartbeat.yml" "$override_workflow"

python3 - "$override_workflow" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = "      - name: Validate fast contract policy fingerprint canonical serialization behavior\n        run: make fast-contract-policy-fingerprint-canonical-selftest\n"
if needle not in text:
    raise SystemExit("[workflow-conventions][fail] fixture generation canonical command not found")
path.write_text(text.replace(needle, "", 1), encoding="utf-8")
PY

set +e
FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH="$override_workflow" bash "$verifier" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail when heartbeat canonical selftest command is missing" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat canonical workflow conformance selftest passed"
