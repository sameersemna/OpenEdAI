#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
assertor="${script_dir}/assert_fast_contract_gate_manifest.sh"

base_manifest="${repo_root}/scripts/ci/fast_contract_gate_manifest.json"
base_workflow="${repo_root}/.github/workflows/health-contract.yml"

if [[ ! -f "$base_manifest" || ! -f "$base_workflow" ]]; then
  echo "[contracts][fail] missing base manifest or workflow for selftest" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cp "$base_workflow" "$tmp_dir/health-contract.yml"
python3 - "$base_manifest" "$tmp_dir/manifest-ok.json" "$tmp_dir/health-contract.yml" <<'PY'
import json
import sys

src_manifest, out_manifest, workflow_path = sys.argv[1:4]
with open(src_manifest, "r", encoding="utf-8") as f:
    m = json.load(f)
m["workflow_path"] = workflow_path
with open(out_manifest, "w", encoding="utf-8") as f:
    json.dump(m, f, indent=2)
PY

bash "$assertor" "$tmp_dir/manifest-ok.json"

python3 - "$tmp_dir/health-contract.yml" <<'PY'
import sys
import yaml

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = yaml.load(f, Loader=yaml.BaseLoader)

steps = data["jobs"]["fast-contract-gate"]["steps"]
for i, step in enumerate(steps):
    if step.get("name") == "Validate fast contract gate verdict JSON":
        del steps[i]
        break

with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, sort_keys=False)
PY

set +e
bash "$assertor" "$tmp_dir/manifest-ok.json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] manifest assert selftest should fail when required step is removed" >&2
  exit 1
fi

echo "[contracts][ok] fast contract gate manifest assert selftest passed"
