#!/usr/bin/env bash
set -euo pipefail

manifest_path="${1:-scripts/ci/fast_contract_gate_manifest.json}"

if [[ ! -f "$manifest_path" ]]; then
  echo "[contracts][fail] fast contract gate manifest not found: $manifest_path" >&2
  exit 1
fi

python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

import yaml

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

workflow_path = Path(manifest["workflow_path"])
if not workflow_path.exists():
    raise SystemExit(f"[contracts][fail] workflow not found: {workflow_path}")

workflow = yaml.load(workflow_path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
if not isinstance(workflow, dict):
    raise SystemExit("[contracts][fail] workflow yaml root must be a mapping")

job_name = manifest["job_name"]
jobs = workflow.get("jobs", {})
if job_name not in jobs:
    raise SystemExit(f"[contracts][fail] workflow missing job: {job_name}")

job = jobs[job_name]
steps = job.get("steps", []) if isinstance(job, dict) else []
if not isinstance(steps, list):
    raise SystemExit(f"[contracts][fail] workflow job '{job_name}' steps must be a list")

step_names = [str(step.get("name", "")) for step in steps if isinstance(step, dict)]
required_order = manifest.get("ordered_steps", [])
required_runs = manifest.get("required_run_commands", [])

cursor = -1
for name in required_order:
    try:
        idx = step_names.index(name, cursor + 1)
    except ValueError:
        raise SystemExit(f"[contracts][fail] manifest missing ordered step in workflow: {name}")
    cursor = idx

run_blocks = "\n".join(str(step.get("run", "")) for step in steps if isinstance(step, dict))
for cmd in required_runs:
    if cmd not in run_blocks:
        raise SystemExit(f"[contracts][fail] manifest required run command missing: {cmd}")

print(f"[contracts][ok] fast contract gate workflow matches manifest: {manifest_path}")
PY
