#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

ts="$(date +%Y%m%d-%H%M%S)"
report="docs/reports/${ts}-local-release-smoke.md"

run_capture() {
  local cmd="$1"
  local output_var="$2"
  local status_var="$3"
  local output
  local status

  set +e
  output="$(eval "$cmd" 2>&1)"
  status=$?
  set -e

  printf -v "$output_var" '%s' "$output"
  printf -v "$status_var" '%s' "$status"
}

run_capture "make ci-local-status" ci_local_output ci_local_rc
run_capture "make test-ci-all" ci_all_output ci_all_rc
run_capture "make smoke-gateway-local" smoke_output smoke_rc
run_capture "systemctl --user status openedai-gateway.service --no-pager -l | sed -n '1,20p'" service_output service_rc

cat > "$report" <<EOF
# Local Release Smoke Report (${ts})

## Scope
- Repository: OpenEdAI
- Host: $(hostname)
- Generated: $(date -Iseconds)

## Checklist Results
- make ci-local-status: ${ci_local_rc}
- make test-ci-all: ${ci_all_rc}
- make smoke-gateway-local: ${smoke_rc}
- systemctl --user status openedai-gateway.service: ${service_rc}

## make ci-local-status
\`\`\`txt
${ci_local_output}
\`\`\`

## make test-ci-all
\`\`\`txt
${ci_all_output}
\`\`\`

## make smoke-gateway-local
\`\`\`txt
${smoke_output}
\`\`\`

## Service Status Snapshot
\`\`\`txt
${service_output}
\`\`\`

## Notes
- shellcheck may be absent locally; script lint remains covered by CI workflow.
- Authorized management endpoint smoke check is optional and requires GATEWAY_TEST_API_KEY.
EOF

echo "generated report: ${report}"

if [[ "$ci_local_rc" != "0" || "$ci_all_rc" != "0" || "$smoke_rc" != "0" || "$service_rc" != "0" ]]; then
  exit 1
fi
