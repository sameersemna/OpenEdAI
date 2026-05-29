#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
artifacts_dir="${2:-artifacts}"

if [[ -z "$mode" ]]; then
  echo "usage: $0 <smoke|selftest> [artifacts_dir]" >&2
  exit 1
fi

python3 - "$mode" "$artifacts_dir" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

mode = sys.argv[1]
artifacts_dir = Path(sys.argv[2])
artifacts_dir.mkdir(parents=True, exist_ok=True)


def load_json(path: Path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        return {}


if mode == 'smoke':
    combined = load_json(artifacts_dir / 'combined-guard.json')
    policy = load_json(artifacts_dir / 'policy-overview.json')
    dashboard = load_json(artifacts_dir / 'dashboard.json')

    manifest = {
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'workflow': os.getenv('GITHUB_WORKFLOW', ''),
        'run_id': os.getenv('GITHUB_RUN_ID', ''),
        'run_attempt': os.getenv('GITHUB_RUN_ATTEMPT', ''),
        'dashboard_mode': dashboard.get('meta', {}).get(
            'mode', 'lean' if os.getenv('DASHBOARD_LEAN') == '1' else 'full'
        ),
        'guard_overall': combined.get('overall', 'UNKNOWN'),
        'guard_auth_mode': combined.get('auth_mode', 'UNKNOWN'),
        'policy_status': policy.get('status', 'UNKNOWN'),
        'thresholds': {
            'trend_limit': os.getenv('TREND_LIMIT', ''),
            'max_fail': os.getenv('MAX_FAIL', ''),
            'max_unknown': os.getenv('MAX_UNKNOWN', ''),
            'min_pass_rate': os.getenv('MIN_PASS_RATE', ''),
            'max_standard_total': os.getenv('MAX_STANDARD_TOTAL', ''),
            'max_auth_total': os.getenv('MAX_AUTH_TOTAL', ''),
            'max_standard_age_days': os.getenv('MAX_STANDARD_AGE_DAYS', ''),
            'max_auth_age_days': os.getenv('MAX_AUTH_AGE_DAYS', ''),
        },
    }

    summary_title = '## Governance Artifact Summary'
    summary_lines = [
        f"- Guard overall: {manifest['guard_overall']}",
        f"- Guard auth mode: {manifest['guard_auth_mode']}",
        f"- Policy status: {manifest['policy_status']}",
        f"- Dashboard mode: {manifest['dashboard_mode']}",
        '- Artifact manifest: artifacts/artifact-manifest.json',
    ]

    status_summary = {
        'generated_at': manifest['generated_at'],
        'workflow': manifest['workflow'],
        'run_id': manifest['run_id'],
        'run_attempt': manifest['run_attempt'],
        'overall': manifest['guard_overall'],
        'policy_status': manifest['policy_status'],
        'dashboard_mode': manifest['dashboard_mode'],
    }
elif mode == 'selftest':
    policy = load_json(artifacts_dir / 'policy-overview.json')
    log_path = artifacts_dir / 'policy-selftest.log'
    log_text = log_path.read_text(encoding='utf-8') if log_path.exists() else ''

    manifest = {
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'workflow': os.getenv('GITHUB_WORKFLOW', ''),
        'run_id': os.getenv('GITHUB_RUN_ID', ''),
        'run_attempt': os.getenv('GITHUB_RUN_ATTEMPT', ''),
        'selftest_passed': '[policy-selftest][ok] all regression checks passed' in log_text,
        'policy_status': policy.get('status', 'UNKNOWN'),
    }

    summary_title = '## Governance Self-Test Summary'
    summary_lines = [
        f"- Self-test passed: {manifest['selftest_passed']}",
        f"- Policy status: {manifest['policy_status']}",
        '- Artifact manifest: artifacts/artifact-manifest.json',
    ]

    status_summary = {
        'generated_at': manifest['generated_at'],
        'workflow': manifest['workflow'],
        'run_id': manifest['run_id'],
        'run_attempt': manifest['run_attempt'],
        'selftest_passed': manifest['selftest_passed'],
        'policy_status': manifest['policy_status'],
    }
else:
    raise SystemExit(f'unsupported mode: {mode}')

(artifacts_dir / 'artifact-manifest.json').write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8'
)

(artifacts_dir / 'status-summary.json').write_text(
    json.dumps(status_summary, indent=2, sort_keys=True) + '\n', encoding='utf-8'
)

summary_path = os.getenv('GITHUB_STEP_SUMMARY')
if summary_path:
    with open(summary_path, 'a', encoding='utf-8') as out:
        out.write(summary_title + '\n\n')
        out.write('\n'.join(summary_lines) + '\n\n')
PY
