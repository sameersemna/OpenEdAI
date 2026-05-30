#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 - <<'PY'
import os
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
HEALTH_CONTRACT_WORKFLOW = Path(os.getenv('FAST_CONTRACT_HEALTH_WORKFLOW_PATH', '.github/workflows/health-contract.yml'))
FAST_CONTRACT_HEARTBEAT_WORKFLOW = Path('.github/workflows/fast-contract-governance-heartbeat.yml')
FAST_CONTRACT_REQUIRED_ORDER = [
    'Capture contract environment status JSON',
    'Validate contract environment status JSON artifact',
    'Validate contract environment JSON validator behavior',
    'Validate contract environment checker behavior',
    'Run fast contract gate report',
    'Resolve latest fast contract report path',
    'Validate fast contract report markdown',
    'Validate fast contract report markdown validator behavior',
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
    'Validate fast contract cross-artifact consistency validator behavior',
    'Validate fast contract gate manifest assertion behavior',
    'Assert fast contract gate manifest conformance',
    'Validate fast contract cross-artifact consistency',
    'Validate fast contract consistency status JSON',
    'Validate fast contract consistency JSON validator behavior',
    'Validate fast contract consistency reason-code stability',
    'Generate fast contract consistency KPI JSON',
    'Validate fast contract consistency KPI JSON',
    'Validate fast contract consistency KPI JSON validator behavior',
    'Assert fast contract consistency KPI thresholds',
    'Validate fast contract consistency KPI assertor behavior',
    'Generate fast contract artifact manifest JSON',
    'Validate fast contract artifact manifest JSON',
    'Validate fast contract artifact manifest validator behavior',
    'Validate fast contract artifact manifest path assertion behavior',
    'Validate fast contract artifact manifest version-lock behavior',
    'Validate fast contract signed-count version-map parser behavior',
    'Assert fast contract artifact manifest path integrity',
    'Generate fast contract artifact checksums',
    'Verify fast contract artifact checksums',
    'Validate fast contract checksum verifier behavior',
    'Validate fast contract checksum tamper-detection behavior',
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

            if 'make fast-contract-report-validate-markdown' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract report markdown validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract report markdown validation OK')

            if 'make fast-contract-report-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract report markdown validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract report markdown validator selftest OK')

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

            if 'make fast-contract-consistency-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract cross-artifact consistency validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract cross-artifact consistency validator selftest OK')

            if 'make fast-contract-gate-manifest-assert-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate manifest assertion selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate manifest assertion selftest OK')

            if 'make fast-contract-gate-manifest-assert' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate manifest assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate manifest assertion step OK')

            if 'make fast-contract-consistency-validate' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract cross-artifact consistency validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract cross-artifact consistency validation OK')

            if 'make fast-contract-consistency-validate-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency status json validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency status json validation OK')

            if 'make fast-contract-consistency-json-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency json validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency json validator selftest OK')

            if 'make fast-contract-consistency-reason-codes-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency reason-code stability selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency reason-code stability selftest OK')

            if 'make fast-contract-consistency-kpi-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency kpi generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency kpi generation OK')

            if 'make fast-contract-consistency-kpi-validate-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency kpi json validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency kpi json validation OK')

            if 'make fast-contract-consistency-kpi-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency kpi validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency kpi validator selftest OK')

            if 'make fast-contract-consistency-kpi-assert' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency kpi assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency kpi assertion OK')

            if 'make fast-contract-consistency-kpi-assert-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract consistency kpi assertor selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract consistency kpi assertor selftest OK')

            if 'make fast-contract-artifact-manifest-generate' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest generation OK')

            if 'make fast-contract-artifact-manifest-validate' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest validation OK')

            if 'make fast-contract-artifact-manifest-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest validator selftest OK')

            if 'make fast-contract-artifact-manifest-assert-paths-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest path assertion selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest path assertion selftest OK')

            if 'make fast-contract-artifact-manifest-version-lock-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest version-lock selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest version-lock selftest OK')

            if 'make fast-contract-signed-count-version-map-parser-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract signed-count version-map parser selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract signed-count version-map parser selftest OK')

            if 'make fast-contract-signed-count-lock-matrix-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract signed-count lock matrix selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract signed-count lock matrix selftest OK')

            if 'make fast-contract-artifact-manifest-assert-paths' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest path assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest path assertion OK')

            if 'FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=7' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing explicit FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=7 in manifest path assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: explicit expected signed artifact count assignment OK')

            if 'FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=7' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing explicit FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=7 in manifest path assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: explicit version-aware signed artifact count assignment OK')

            if 'make fast-contract-checksums-generate' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract checksum generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract checksum generation OK')

            if 'make fast-contract-checksums-verify' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract checksum verification step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract checksum verification OK')

            if 'make fast-contract-checksums-verify-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract checksum verifier selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract checksum verifier selftest OK')

            if 'make fast-contract-checksums-tamper-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract checksum tamper selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract checksum tamper selftest OK')

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
            'make verify-workflow-conventions-fast-contract-expected-count-selftest',
            'make fast-contract-report-validate-selftest',
            'make fast-contract-status-validate-selftest',
            'make fast-contract-trend-validate-selftest',
            'make fast-contract-gate-verdict-validate-selftest',
            'make fast-contract-artifacts-verify-selftest',
            'make fast-contract-consistency-validate-selftest',
            'make fast-contract-consistency-json-validate-selftest',
            'make fast-contract-consistency-reason-codes-selftest',
            'make fast-contract-consistency-kpi-validate-selftest',
            'make fast-contract-consistency-kpi-assert-selftest',
            'make fast-contract-artifact-manifest-validate-selftest',
            'make fast-contract-artifact-manifest-assert-paths-selftest',
            'make fast-contract-artifact-manifest-version-lock-selftest',
            'make fast-contract-signed-count-version-map-parser-selftest',
            'make fast-contract-signed-count-lock-matrix-selftest',
            'make fast-contract-checksums-verify-selftest',
            'make fast-contract-checksums-tamper-selftest',
            'make fast-contract-gate-manifest-assert-selftest',
            'make fast-contract-gate-manifest-assert',
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
