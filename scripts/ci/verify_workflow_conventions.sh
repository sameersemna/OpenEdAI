#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 - <<'PY'
import sys
from pathlib import Path

import yaml

WORKFLOWS = {
    '.github/workflows/local-smoke-report-guard.yml': 'smoke',
    '.github/workflows/local-smoke-report-guard-auth.yml': 'smoke',
    '.github/workflows/governance-policy-selftest.yml': 'selftest',
}
SMOKE_WORKFLOWS = {
    '.github/workflows/local-smoke-report-guard.yml',
    '.github/workflows/local-smoke-report-guard-auth.yml',
}
HELPER = Path('scripts/ci/workflow_artifact_manifest.sh')
GOVERNANCE_CONVENTIONS_WORKFLOW = Path('.github/workflows/governance-workflow-conventions.yml')

errors = []
checks = []

if not HELPER.exists():
    errors.append('scripts/ci/workflow_artifact_manifest.sh: missing helper file')
else:
    helper_text = HELPER.read_text(encoding='utf-8')
    if 'status-summary.json' not in helper_text:
        errors.append('scripts/ci/workflow_artifact_manifest.sh: missing status-summary generation')
    else:
        checks.append('scripts/ci/workflow_artifact_manifest.sh: status summary generation OK')

if not GOVERNANCE_CONVENTIONS_WORKFLOW.exists():
    errors.append('.github/workflows/governance-workflow-conventions.yml: missing workflow file')
else:
    try:
        workflow_data = yaml.load(GOVERNANCE_CONVENTIONS_WORKFLOW.read_text(encoding='utf-8'), Loader=yaml.BaseLoader)
    except Exception as exc:
        errors.append(f'.github/workflows/governance-workflow-conventions.yml: invalid yaml: {exc}')
    else:
        on_block = workflow_data.get('on', {}) if isinstance(workflow_data, dict) else {}
        schedules = on_block.get('schedule', []) if isinstance(on_block, dict) else []
        if schedules:
            checks.append('.github/workflows/governance-workflow-conventions.yml: weekly schedule OK')
        else:
            errors.append('.github/workflows/governance-workflow-conventions.yml: missing schedule trigger')

for path_str, mode in WORKFLOWS.items():
    path = Path(path_str)
    if not path.exists():
        errors.append(f'{path_str}: missing file')
        continue

    try:
        data = yaml.load(path.read_text(encoding='utf-8'), Loader=yaml.BaseLoader)
    except Exception as exc:
        errors.append(f'{path_str}: invalid yaml: {exc}')
        continue

    jobs = data.get('jobs', {}) if isinstance(data, dict) else {}
    if not jobs:
        errors.append(f'{path_str}: missing jobs block')
        continue

    job = next(iter(jobs.values()))
    steps = job.get('steps', []) if isinstance(job, dict) else []

    run_blocks = '\n'.join(str(step.get('run', '')) for step in steps if isinstance(step, dict))
    helper_pattern = f'workflow_artifact_manifest.sh {mode} artifacts'
    if helper_pattern not in run_blocks:
        errors.append(f'{path_str}: missing helper call "{helper_pattern}"')
    else:
        checks.append(f'{path_str}: helper call OK')

    if 'sha256sums.txt' not in run_blocks:
        errors.append(f'{path_str}: missing artifact checksum generation step')
    else:
        checks.append(f'{path_str}: checksum step OK')

    verify_pattern = f'verify-governance-artifacts ARTIFACT_DIR=artifacts BUNDLE_MODE={mode}'
    if verify_pattern not in run_blocks:
        errors.append(f'{path_str}: missing artifact bundle verification step "{verify_pattern}"')
    else:
        checks.append(f'{path_str}: artifact bundle verify step OK')

    upload_steps = [
        step for step in steps
        if isinstance(step, dict) and str(step.get('uses', '')).startswith('actions/upload-artifact@')
    ]
    if not upload_steps:
        errors.append(f'{path_str}: missing actions/upload-artifact step')
    else:
        checks.append(f'{path_str}: upload step OK')

    if upload_steps:
        retention = upload_steps[0].get('with', {}).get('retention-days', '')
        if str(retention) != '14':
            errors.append(f'{path_str}: retention-days expected 14, got {retention!r}')
        else:
            checks.append(f'{path_str}: retention-days OK')

    if path_str in SMOKE_WORKFLOWS:
        benchmark_artifact_checks = [
            'artifacts/bench-baseline.json',
            'artifacts/bench-current.json',
            'artifacts/bench-compare.json',
        ]
        for artifact in benchmark_artifact_checks:
            if artifact not in run_blocks:
                errors.append(f'{path_str}: missing benchmark artifact generation for {artifact}')
            else:
                checks.append(f'{path_str}: benchmark artifact generation OK ({artifact})')

if errors:
    print('[workflow-conventions][fail]')
    for err in errors:
        print(f' - {err}')
    sys.exit(1)

print('[workflow-conventions][ok] all checks passed')
for check in checks:
    print(f' - {check}')
PY
