#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:-${ARTIFACT_DIR:-artifacts}}"
bundle_mode="${2:-${BUNDLE_MODE:-auto}}"

if [[ ! -d "$artifact_dir" ]]; then
  echo "[artifact-verify][fail] artifact directory not found: $artifact_dir" >&2
  exit 1
fi

if [[ ! -f "$artifact_dir/sha256sums.txt" ]]; then
  echo "[artifact-verify][fail] missing checksum file: $artifact_dir/sha256sums.txt" >&2
  exit 1
fi

if [[ ! -f "$artifact_dir/status-summary.json" ]]; then
  echo "[artifact-verify][fail] missing status summary: $artifact_dir/status-summary.json" >&2
  exit 1
fi

(
  cd "$artifact_dir"
  sha256sum -c sha256sums.txt
)

python3 - "$artifact_dir/status-summary.json" "$bundle_mode" <<'PY'
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
mode = sys.argv[2]
obj = json.loads(p.read_text(encoding='utf-8'))


def require_fields(data, fields, label):
  missing = [f for f in fields if f not in data]
  if missing:
    raise SystemExit(f'[artifact-verify][fail] {label} missing fields: {", ".join(missing)}')


require_fields(
  obj,
  ['generated_at', 'workflow', 'run_id', 'run_attempt', 'policy_status'],
  'status-summary',
)

if mode == 'auto':
  if 'selftest_passed' in obj:
    mode = 'selftest'
  elif 'overall' in obj:
    mode = 'smoke'
  else:
    raise SystemExit('[artifact-verify][fail] unable to infer mode from status-summary fields')

if mode == 'smoke':
  require_fields(obj, ['overall', 'dashboard_mode'], 'status-summary (smoke mode)')
elif mode == 'selftest':
  require_fields(obj, ['selftest_passed'], 'status-summary (selftest mode)')
else:
  raise SystemExit(f'[artifact-verify][fail] unsupported mode: {mode}')

print('[artifact-verify][ok] status summary loaded')
print(' - mode=' + mode)
print(' - generated_at=' + str(obj.get('generated_at', '')))
print(' - workflow=' + str(obj.get('workflow', '')))
print(' - run_id=' + str(obj.get('run_id', '')))

if 'overall' in obj:
    print(' - overall=' + str(obj.get('overall', '')))
if 'selftest_passed' in obj:
    print(' - selftest_passed=' + str(obj.get('selftest_passed', '')))
print(' - policy_status=' + str(obj.get('policy_status', '')))
if 'dashboard_mode' in obj:
    print(' - dashboard_mode=' + str(obj.get('dashboard_mode', '')))
PY
