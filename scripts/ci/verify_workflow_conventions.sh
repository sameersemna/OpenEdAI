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
HEALTH_CONTRACT_WORKFLOW = Path('.github/workflows/health-contract.yml')
FAST_CONTRACT_HEARTBEAT_WORKFLOW = Path('.github/workflows/fast-contract-governance-heartbeat.yml')
FAST_CONTRACT_REQUIRED_ORDER = [
    'Capture contract environment status JSON',
    'Validate contract environment status JSON artifact',
    'Validate contract environment JSON validator behavior',
    'Validate contract environment checker behavior',
    'Run fast contract gate report',
    'Resolve latest fast contract report path',
    'Generate fast contract status summary JSON',
    'Validate fast contract status summary JSON',
    'Validate fast contract status summary validator behavior',
    'Generate fast contract trend JSON',
    'Validate fast contract trend JSON',
    'Assert fast contract trend thresholds',
    'Generate fast contract gate verdict JSON',
    'Validate fast contract gate verdict JSON',
    'Validate fast contract trend validator behavior',
    'Validate fast contract gate verdict JSON validator behavior',
    'Validate fast contract gate verdict behavior',
    'Validate fast contract artifact verifier behavior',
    'Verify fast contract artifacts before upload',
    'Upload fast contract report artifact',
    'Append fast contract summary',
]

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

if not HEALTH_CONTRACT_WORKFLOW.exists():
    errors.append('.github/workflows/health-contract.yml: missing workflow file')
else:
    try:
        health_data = yaml.load(HEALTH_CONTRACT_WORKFLOW.read_text(encoding='utf-8'), Loader=yaml.BaseLoader)
    except Exception as exc:
        errors.append(f'.github/workflows/health-contract.yml: invalid yaml: {exc}')
    else:
        jobs = health_data.get('jobs', {}) if isinstance(health_data, dict) else {}
        fast_gate = jobs.get('fast-contract-gate', {}) if isinstance(jobs, dict) else {}
        steps = fast_gate.get('steps', []) if isinstance(fast_gate, dict) else []
        if not steps:
            errors.append('.github/workflows/health-contract.yml: fast-contract-gate missing steps')
        else:
            step_names = [str(step.get('name', '')) for step in steps if isinstance(step, dict)]
            index = -1
            for required in FAST_CONTRACT_REQUIRED_ORDER:
                try:
                    next_index = step_names.index(required, index + 1)
                except ValueError:
                    errors.append(f'.github/workflows/health-contract.yml: fast-contract-gate missing ordered step "{required}"')
                    break
                index = next_index
            else:
                checks.append('.github/workflows/health-contract.yml: fast-contract-gate ordered steps OK')

            run_blocks = '\n'.join(str(step.get('run', '')) for step in steps if isinstance(step, dict))
            if 'make fast-contract-status-summary' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract status summary generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract status summary generation OK')

            if 'make fast-contract-status-validate-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract status summary json validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract status summary json validation OK')

            if 'make fast-contract-status-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract status summary validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract status summary validator selftest OK')

            if 'make fast-contract-trend-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract trend generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract trend generation OK')

            if 'make fast-contract-trend-validate-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract trend json validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract trend json validation OK')

            if 'make fast-contract-trend-assert' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract trend threshold assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract trend threshold assertion OK')

            if 'make fast-contract-gate-verdict' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate verdict generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate verdict generation OK')

            if 'make fast-contract-gate-verdict-validate-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate verdict json validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate verdict json validation OK')

            if 'make fast-contract-trend-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract trend validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract trend validator selftest OK')

            if 'make fast-contract-gate-verdict-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate verdict json validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate verdict json validator selftest OK')

            if 'make fast-contract-gate-verdict-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate verdict selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate verdict selftest OK')

            if 'make fast-contract-artifacts-verify-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact verifier selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact verifier selftest OK')

            if 'make fast-contract-artifacts-verify' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact verification step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact verification step OK')

if not FAST_CONTRACT_HEARTBEAT_WORKFLOW.exists():
    errors.append('.github/workflows/fast-contract-governance-heartbeat.yml: missing workflow file')
else:
    try:
        heartbeat_data = yaml.load(FAST_CONTRACT_HEARTBEAT_WORKFLOW.read_text(encoding='utf-8'), Loader=yaml.BaseLoader)
    except Exception as exc:
        errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: invalid yaml: {exc}')
    else:
        on_block = heartbeat_data.get('on', {}) if isinstance(heartbeat_data, dict) else {}
        schedules = on_block.get('schedule', []) if isinstance(on_block, dict) else []
        if schedules:
            checks.append('.github/workflows/fast-contract-governance-heartbeat.yml: weekly schedule OK')
        else:
            errors.append('.github/workflows/fast-contract-governance-heartbeat.yml: missing schedule trigger')

        jobs = heartbeat_data.get('jobs', {}) if isinstance(heartbeat_data, dict) else {}
        heartbeat_job = jobs.get('fast-contract-governance-heartbeat', {}) if isinstance(jobs, dict) else {}
        steps = heartbeat_job.get('steps', []) if isinstance(heartbeat_job, dict) else []
        run_blocks = '\n'.join(str(step.get('run', '')) for step in steps if isinstance(step, dict))
        for required in [
            'make verify-workflow-conventions',
            'make fast-contract-status-validate-selftest',
            'make fast-contract-trend-validate-selftest',
            'make fast-contract-gate-verdict-validate-selftest',
            'make fast-contract-artifacts-verify-selftest',
        ]:
            if required not in run_blocks:
                errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: missing required run command "{required}"')
            else:
                checks.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: required run command OK ({required})')

if errors:
    print('[workflow-conventions][fail]')
    for err in errors:
        print(f' - {err}')
    sys.exit(1)

print('[workflow-conventions][ok] all checks passed')
for check in checks:
    print(f' - {check}')
PY
