#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

latest_report="$(ls -1t docs/reports/*-local-release-smoke.md 2>/dev/null | head -n1 || true)"

if [[ -z "$latest_report" ]]; then
  echo '{"error":"no local release smoke report found in docs/reports"}'
  exit 1
fi

ci_local="$(awk -F': ' '/- make ci-local-status:/ {print $2; exit}' "$latest_report")"
ci_all="$(awk -F': ' '/- make test-ci-all:/ {print $2; exit}' "$latest_report")"
smoke_local="$(awk -F': ' '/- make smoke-gateway-local:/ {print $2; exit}' "$latest_report")"
service_status="$(awk -F': ' '/- systemctl --user status openedai-gateway.service:/ {print $2; exit}' "$latest_report")"

if [[ -z "$ci_local" || -z "$ci_all" || -z "$smoke_local" || -z "$service_status" ]]; then
  echo "{\"error\":\"could not parse checklist results from ${latest_report}\"}"
  exit 1
fi

overall="PASS"
if [[ "$ci_local" != "0" || "$ci_all" != "0" || "$smoke_local" != "0" || "$service_status" != "0" ]]; then
  overall="FAIL"
fi

printf '{"report":"%s","overall":"%s","checks":{"ci_local_status":%s,"test_ci_all":%s,"smoke_gateway_local":%s,"service_status":%s}}\n' \
  "$latest_report" "$overall" "$ci_local" "$ci_all" "$smoke_local" "$service_status"
