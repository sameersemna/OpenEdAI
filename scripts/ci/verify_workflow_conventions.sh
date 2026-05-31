#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

python3 - <<'PY'
import json
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
FAST_CONTRACT_HEARTBEAT_WORKFLOW = Path(os.getenv('FAST_CONTRACT_HEARTBEAT_WORKFLOW_PATH', '.github/workflows/fast-contract-governance-heartbeat.yml'))
FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST = Path(
    os.getenv(
        'FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST_PATH',
        'scripts/ci/fast_contract_heartbeat_conventions_manifest.json',
    )
)
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
    'Validate fast contract signed-count lock matrix behavior',
    'Validate fast contract signed-count lock error-message behavior',
    'Validate fast contract gate verdict reason-code behavior',
    'Validate fast contract policy fingerprint JSON validator behavior',
    'Validate fast contract policy fingerprint canonical serialization behavior',
    'Validate fast contract policy fingerprint drift behavior',
    'Assert fast contract artifact manifest path integrity',
    'Generate fast contract policy fingerprint JSON',
    'Validate fast contract policy fingerprint JSON',
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
heartbeat_manifest_ready = False
heartbeat_required_commands = []
heartbeat_required_step_names = []
heartbeat_expected_step_count = None

if not FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST.exists():
    errors.append(
        f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: missing heartbeat conventions manifest'
    )
else:
    try:
        manifest_data = json.loads(
            FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST.read_text(encoding='utf-8')
        )
    except Exception as exc:
        errors.append(
            f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid heartbeat conventions manifest json: {exc}'
        )
    else:
        if not isinstance(manifest_data, dict):
            errors.append(
                f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid heartbeat conventions manifest root (expected object)'
            )
        else:
            allowed_manifest_keys = {
                'schema_version',
                'expected_job_step_count',
                'required_run_commands',
                'required_step_names',
            }
            unknown_keys = sorted(str(key) for key in manifest_data.keys() if key not in allowed_manifest_keys)
            if unknown_keys:
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: unexpected top-level key "{unknown_keys[0]}"'
                )

            schema_version = manifest_data.get('schema_version')
            if not isinstance(schema_version, str) or not schema_version:
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid schema_version (expected non-empty string)'
                )
            elif schema_version != 'v1':
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: unsupported schema_version "{schema_version}" (supported: v1)'
                )

            expected_step_count = manifest_data.get('expected_job_step_count')
            if not isinstance(expected_step_count, int) or expected_step_count <= 0:
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid expected_job_step_count (expected positive integer)'
                )

            commands = manifest_data.get('required_run_commands')
            if not isinstance(commands, list) or not commands:
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_run_commands (expected non-empty list)'
                )
            elif not all(isinstance(item, str) and item.strip() for item in commands):
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_run_commands entries (expected non-empty strings)'
                )
            elif len(set(commands)) != len(commands):
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: duplicate entry in required_run_commands'
                )
            else:
                first_required_command = 'make verify-workflow-conventions'
                if commands[0] != first_required_command:
                    errors.append(
                        f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_run_commands order '
                        f'(first command must be "{first_required_command}")'
                    )
                else:
                    saw_fast_contract_command = False
                    for command in commands:
                        if command.startswith('make fast-contract-'):
                            saw_fast_contract_command = True
                        elif command.startswith('make verify-workflow-conventions') and saw_fast_contract_command:
                            errors.append(
                                f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_run_commands order '
                                f'(verify-workflow command after fast-contract command: "{command}")'
                            )
                            break

            step_names = manifest_data.get('required_step_names')
            if not isinstance(step_names, list) or not step_names:
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_step_names (expected non-empty list)'
                )
            elif not all(isinstance(item, str) and item.strip() for item in step_names):
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_step_names entries (expected non-empty strings)'
                )
            elif len(set(step_names)) != len(step_names):
                errors.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: duplicate entry in required_step_names'
                )
            else:
                expected_required_step_names_order = [
                    'Validate workflow conventions heartbeat mixed-fault priority',
                    'Validate workflow conventions heartbeat unexpected-command allowlist',
                    'Validate workflow conventions heartbeat unexpected-over-missing priority',
                ]
                if step_names != expected_required_step_names_order:
                    errors.append(
                        f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: invalid required_step_names order '
                        f'(expected: {", ".join(expected_required_step_names_order)})'
                    )

            if not errors:
                heartbeat_required_commands = list(commands)
                heartbeat_required_step_names = list(step_names)
                heartbeat_expected_step_count = expected_step_count
                heartbeat_manifest_ready = True
                checks.append(
                    f'{FAST_CONTRACT_HEARTBEAT_CONVENTIONS_MANIFEST}: heartbeat conventions manifest OK'
                )

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

            if 'make fast-contract-signed-count-lock-error-messages-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract signed-count lock error-message selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract signed-count lock error-message selftest OK')

            if 'make fast-contract-gate-verdict-reason-codes-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract gate verdict reason-code selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract gate verdict reason-code selftest OK')

            if 'make fast-contract-policy-fingerprint-validate-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract policy fingerprint validator selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract policy fingerprint validator selftest OK')

            if 'make fast-contract-policy-fingerprint-canonical-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract policy fingerprint canonical serialization selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract policy fingerprint canonical serialization selftest OK')

            if 'make fast-contract-policy-fingerprint-drift-selftest' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract policy fingerprint drift selftest step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract policy fingerprint drift selftest OK')

            if 'make fast-contract-artifact-manifest-assert-paths' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract artifact manifest path assertion step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract artifact manifest path assertion OK')

            if 'make fast-contract-policy-fingerprint-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract policy fingerprint generation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract policy fingerprint generation OK')

            if 'make fast-contract-policy-fingerprint-validate-json' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing fast contract policy fingerprint json validation step')
            else:
                checks.append('.github/workflows/health-contract.yml: fast contract policy fingerprint json validation OK')

            if 'Policy fingerprint (sha256):' not in run_blocks:
                errors.append('.github/workflows/health-contract.yml: missing policy fingerprint summary line in step summary block')
            else:
                checks.append('.github/workflows/health-contract.yml: policy fingerprint summary line convention OK')

            summary_order = [
                'echo "- Checksum status: VERIFIED"',
                'echo "- Signed artifacts: $${signed_artifact_count}"',
                'echo "- Policy fingerprint (sha256): $${policy_fingerprint}"',
                'echo "- Verdict: $${verdict_overall} ($${verdict_reasons})"',
            ]
            summary_index = -1
            for line in summary_order:
                line_count = run_blocks.count(line)
                if line_count == 0:
                    errors.append(f'.github/workflows/health-contract.yml: missing fast-contract summary line "{line}"')
                    break
                if line_count > 1:
                    errors.append(f'.github/workflows/health-contract.yml: duplicate fast-contract summary line "{line}"')
                    break
            else:
                summary_index = -1
                for line in summary_order:
                    idx = run_blocks.find(line)
                    if idx <= summary_index:
                        errors.append('.github/workflows/health-contract.yml: fast-contract summary lines are out of required order (checksum, signed artifacts, policy fingerprint, verdict)')
                        break
                    summary_index = idx
                else:
                    checks.append('.github/workflows/health-contract.yml: fast-contract summary line ordering convention OK')

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
        run_lines = []
        step_names = []
        missing_step_name_make_command = None
        for step in steps:
            if not isinstance(step, dict):
                continue
            step_name = step.get('name', '')
            if isinstance(step_name, str) and step_name.strip():
                step_names.append(step_name.strip())
            run_value = step.get('run', '')
            step_make_commands = []
            for raw_line in str(run_value).splitlines():
                line = raw_line.strip()
                if not line or line.startswith('#'):
                    continue
                run_lines.append(line)
                if line.startswith('make '):
                    step_make_commands.append(line)
            if (not isinstance(step_name, str) or not step_name.strip()) and step_make_commands and missing_step_name_make_command is None:
                missing_step_name_make_command = step_make_commands[0]
        if heartbeat_manifest_ready:
            if missing_step_name_make_command is not None:
                errors.append(
                    '.github/workflows/fast-contract-governance-heartbeat.yml: '
                    f'missing step name for make run command "{missing_step_name_make_command}"'
                )

            heartbeat_required_command_set = set(heartbeat_required_commands)
            heartbeat_convention_prefixes = (
                'make verify-workflow-conventions-fast-contract-',
                'make fast-contract-',
            )

            for line in run_lines:
                if line.startswith(heartbeat_convention_prefixes) and line not in heartbeat_required_command_set:
                    errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: unexpected fast-contract run command "{line}"')
                    break

            if not errors:
                first_fast_contract_idx = None
                for idx, line in enumerate(run_lines):
                    if line.startswith('make fast-contract-'):
                        first_fast_contract_idx = idx
                        break

                if first_fast_contract_idx is not None:
                    for line in run_lines[first_fast_contract_idx + 1:]:
                        if line.startswith('make verify-workflow-conventions'):
                            errors.append(
                                '.github/workflows/fast-contract-governance-heartbeat.yml: '
                                f'invalid run command class boundary (verify-workflow command after fast-contract command: "{line}")'
                            )
                            break
                    else:
                        checks.append(
                            '.github/workflows/fast-contract-governance-heartbeat.yml: '
                            'verify-workflow command block is contiguous before fast-contract commands'
                        )

            if not errors:
                required_step_name_positions = {}
                for required_name in heartbeat_required_step_names:
                    name_count = sum(1 for name in step_names if name == required_name)
                    if name_count == 0:
                        errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: missing required step name "{required_name}"')
                        break
                    if name_count > 1:
                        errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: duplicate required step name "{required_name}"')
                        break
                    required_step_name_positions[required_name] = step_names.index(required_name)
                    checks.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: required step name OK ({required_name})')

            if not errors:
                previous_step_position = -1
                for required_name in heartbeat_required_step_names:
                    position = required_step_name_positions[required_name]
                    if position <= previous_step_position:
                        errors.append(
                            '.github/workflows/fast-contract-governance-heartbeat.yml: '
                            f'required step name out of order "{required_name}"'
                        )
                        break
                    previous_step_position = position
                else:
                    checks.append(
                        '.github/workflows/fast-contract-governance-heartbeat.yml: '
                        'required step name ordering OK'
                    )

            if not errors:
                checks.append('.github/workflows/fast-contract-governance-heartbeat.yml: fast-contract run command allowlist OK')

                heartbeat_command_positions = {}
                for idx, line in enumerate(run_lines):
                    if line in heartbeat_required_commands and line not in heartbeat_command_positions:
                        heartbeat_command_positions[line] = idx

                for required in heartbeat_required_commands:
                    command_count = sum(1 for line in run_lines if line == required)
                    if command_count == 0:
                        errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: missing required run command "{required}"')
                        break
                    elif command_count > 1:
                        errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: duplicate required run command "{required}"')
                        break
                    else:
                        checks.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: required run command OK ({required})')
                else:
                    previous_position = -1
                    for required in heartbeat_required_commands:
                        position = heartbeat_command_positions.get(required, -1)
                        if position <= previous_position:
                            errors.append(f'.github/workflows/fast-contract-governance-heartbeat.yml: required run command out of order "{required}"')
                            break
                        previous_position = position
                    else:
                        checks.append('.github/workflows/fast-contract-governance-heartbeat.yml: required run command ordering OK')

            if not errors:
                actual_step_count = len(steps)
                if actual_step_count != heartbeat_expected_step_count:
                    errors.append(
                        '.github/workflows/fast-contract-governance-heartbeat.yml: '
                        f'expected {heartbeat_expected_step_count} steps, found {actual_step_count}'
                    )
                else:
                    checks.append(
                        '.github/workflows/fast-contract-governance-heartbeat.yml: '
                        f'step count OK ({heartbeat_expected_step_count})'
                    )

if errors:
    print('[workflow-conventions][fail]')
    for err in errors:
        print(f' - {err}')
    sys.exit(1)

print('[workflow-conventions][ok] all checks passed')
for check in checks:
    print(f' - {check}')
PY
