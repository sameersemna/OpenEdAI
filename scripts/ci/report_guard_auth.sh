#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

latest_auth_report="$(ls -1t docs/reports/*-local-release-smoke-auth.md 2>/dev/null | head -n1 || true)"

if [[ -z "$latest_auth_report" ]]; then
  echo "[guard-auth][fail] no auth smoke report found in docs/reports"
  echo "[guard-auth][hint] run make report-generate-local-smoke-auth"
  exit 1
fi

ci_local="$(awk -F': ' '/- make ci-local-status:/ {print $2; exit}' "$latest_auth_report")"
ci_all="$(awk -F': ' '/- make test-ci-all:/ {print $2; exit}' "$latest_auth_report")"
smoke_auth="$(awk -F': ' '/- make smoke-gateway-auth:/ {print $2; exit}' "$latest_auth_report")"
service_status="$(awk -F': ' '/- systemctl --user status openedai-gateway.service:/ {print $2; exit}' "$latest_auth_report")"

if [[ -z "$ci_local" || -z "$ci_all" || -z "$smoke_auth" || -z "$service_status" ]]; then
  echo "[guard-auth][fail] could not parse required checklist fields in $latest_auth_report"
  exit 1
fi

if [[ "$ci_local" != "0" || "$ci_all" != "0" || "$smoke_auth" != "0" || "$service_status" != "0" ]]; then
  echo "[guard-auth][fail] auth report contains non-zero checks"
  echo "[guard-auth][context] report=$latest_auth_report ci-local=$ci_local ci-all=$ci_all smoke-auth=$smoke_auth service=$service_status"
  exit 1
fi

echo "[guard-auth][ok] auth report checks passed"
echo "[guard-auth][report] $latest_auth_report"
