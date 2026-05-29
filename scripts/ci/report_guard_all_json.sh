#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

summary_json="$(bash scripts/ci/report_latest_smoke_summary_json.sh)"
compare_json="$(bash scripts/ci/report_compare_latest_json.sh)"

summary_overall="$(printf '%s\n' "$summary_json" | sed -n 's/.*"overall":"\([^"]*\)".*/\1/p')"
compare_overall="$(printf '%s\n' "$compare_json" | sed -n 's/.*"overall":"\([^"]*\)".*/\1/p')"

standard_overall="PASS"
if [[ "$summary_overall" != "PASS" || "$compare_overall" != "NO_DRIFT" ]]; then
  standard_overall="FAIL"
fi

auth_mode="SKIPPED"
auth_overall="SKIPPED"
auth_report=""
auth_checks_json='{}'

latest_auth_report="$(ls -1t docs/reports/*-local-release-smoke-auth.md 2>/dev/null | head -n1 || true)"
if [[ -n "$latest_auth_report" ]]; then
  auth_mode="ENFORCED"
  auth_report="$latest_auth_report"

  ci_local="$(awk -F': ' '/- make ci-local-status:/ {print $2; exit}' "$latest_auth_report")"
  ci_all="$(awk -F': ' '/- make test-ci-all:/ {print $2; exit}' "$latest_auth_report")"
  smoke_auth="$(awk -F': ' '/- make smoke-gateway-auth:/ {print $2; exit}' "$latest_auth_report")"
  service_status="$(awk -F': ' '/- systemctl --user status openedai-gateway.service:/ {print $2; exit}' "$latest_auth_report")"

  if [[ -z "$ci_local" || -z "$ci_all" || -z "$smoke_auth" || -z "$service_status" ]]; then
    auth_overall="FAIL"
    auth_checks_json='{"error":"could not parse required checklist fields"}'
  elif [[ "$ci_local" == "0" && "$ci_all" == "0" && "$smoke_auth" == "0" && "$service_status" == "0" ]]; then
    auth_overall="PASS"
    auth_checks_json=$(printf '{"ci_local_status":%s,"test_ci_all":%s,"smoke_gateway_auth":%s,"service_status":%s}' "$ci_local" "$ci_all" "$smoke_auth" "$service_status")
  else
    auth_overall="FAIL"
    auth_checks_json=$(printf '{"ci_local_status":%s,"test_ci_all":%s,"smoke_gateway_auth":%s,"service_status":%s}' "$ci_local" "$ci_all" "$smoke_auth" "$service_status")
  fi
fi

overall="PASS"
if [[ "$standard_overall" != "PASS" ]]; then
  overall="FAIL"
fi
if [[ "$auth_mode" == "ENFORCED" && "$auth_overall" != "PASS" ]]; then
  overall="FAIL"
fi

printf '{"overall":"%s","standard":{"overall":"%s","summary":%s,"compare":%s},"auth":{"mode":"%s","overall":"%s","report":"%s","checks":%s}}\n' \
  "$overall" "$standard_overall" "$summary_json" "$compare_json" "$auth_mode" "$auth_overall" "$auth_report" "$auth_checks_json"

if [[ "$overall" != "PASS" ]]; then
  exit 1
fi
