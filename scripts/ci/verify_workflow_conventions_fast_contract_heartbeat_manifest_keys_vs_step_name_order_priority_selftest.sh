#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verifier="${script_dir}/verify_workflow_conventions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_path="${tmp_dir}/fast-contract-heartbeat-conventions-manifest-keys-vs-step-name-order-priority.json"
output_path="${tmp_dir}/verifier-output.txt"
cp "${repo_root}/scripts/ci/fast_contract_heartbeat_conventions_manifest.json" "$manifest_path"

python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding='utf-8'))
step_names = manifest.get('required_step_names', [])
if len(step_names) < 2:
    raise SystemExit('[workflow-conventions][fail] fixture generation expected at least two required_step_names entries')
step_names[0], step_names[1] = step_names[1], step_names[0]
manifest['required_step_names'] = step_names
manifest['unexpected_priority_probe'] = True
path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
PY

set +e
FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST_PATH="$manifest_path" bash "$verifier" >"$output_path" 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[workflow-conventions][fail] verifier should fail for heartbeat manifest keys-vs-step-name-order priority fixture" >&2
  exit 1
fi

expected='unexpected top-level key "unexpected_priority_probe"'
if ! grep -Fq "$expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat manifest keys-vs-step-name-order priority error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

order_expected='invalid required_step_names order (expected: Validate workflow conventions heartbeat mixed-fault priority, Validate workflow conventions heartbeat unexpected-command allowlist, Validate workflow conventions heartbeat unexpected-over-missing priority)'
if ! grep -Fq "$order_expected" "$output_path"; then
  echo "[workflow-conventions][fail] expected heartbeat manifest step-name-order error message not found" >&2
  cat "$output_path" >&2
  exit 1
fi

priority_error_count="$(grep -Ec 'unexpected top-level key|invalid required_step_names order' "$output_path" || true)"
if [[ "$priority_error_count" != "2" ]]; then
  echo "[workflow-conventions][fail] expected exactly two manifest priority errors, got $priority_error_count" >&2
  cat "$output_path" >&2
  exit 1
fi

unknown_line="$(grep -n 'unexpected top-level key "unexpected_priority_probe"' "$output_path" | head -n1 | cut -d: -f1)"
order_line="$(grep -n 'invalid required_step_names order (expected:' "$output_path" | head -n1 | cut -d: -f1)"
if [[ -z "$unknown_line" || -z "$order_line" || "$unknown_line" -ge "$order_line" ]]; then
  echo "[workflow-conventions][fail] expected manifest unknown-key error to appear before step-name-order error" >&2
  cat "$output_path" >&2
  exit 1
fi

echo "[workflow-conventions][ok] heartbeat manifest keys-vs-step-name-order priority selftest passed"
