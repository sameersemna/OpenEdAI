#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

latest_report="$(ls -1t docs/reports/*-local-release-smoke.md 2>/dev/null | head -n1 || true)"

if [[ -z "$latest_report" ]]; then
  echo "[report][fail] no local release smoke report found in docs/reports"
  exit 1
fi

ci_local="$(awk -F': ' '/- make ci-local-status:/ {print $2; exit}' "$latest_report")"
ci_all="$(awk -F': ' '/- make test-ci-all:/ {print $2; exit}' "$latest_report")"
smoke_local="$(awk -F': ' '/- make smoke-gateway-local:/ {print $2; exit}' "$latest_report")"
service_status="$(awk -F': ' '/- systemctl --user status openedai-gateway.service:/ {print $2; exit}' "$latest_report")"

if [[ -z "$ci_local" || -z "$ci_all" || -z "$smoke_local" || -z "$service_status" ]]; then
  echo "[report][fail] could not parse checklist results from $latest_report"
  exit 1
fi

overall="PASS"
if [[ "$ci_local" != "0" || "$ci_all" != "0" || "$smoke_local" != "0" || "$service_status" != "0" ]]; then
  overall="FAIL"
fi

echo "report: $latest_report"
echo "summary: ${overall} (ci-local=${ci_local}, ci-all=${ci_all}, smoke-local=${smoke_local}, service=${service_status})"
