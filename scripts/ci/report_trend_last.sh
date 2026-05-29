#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

limit="${1:-5}"
if ! [[ "$limit" =~ ^[1-9][0-9]*$ ]]; then
  echo "[trend][fail] limit must be a positive integer (got: $limit)"
  exit 1
fi

mapfile -t reports < <(ls -1t docs/reports/*-local-release-smoke*.md 2>/dev/null | head -n "$limit")

if [[ "${#reports[@]}" -eq 0 ]]; then
  echo "[trend][fail] no local smoke reports found in docs/reports"
  exit 1
fi

echo "report trend (latest ${#reports[@]} reports):"
printf '  %-45s | %-8s | %-8s | %-8s | %-8s | %-8s\n' "report" "ci-local" "ci-all" "smoke" "service" "overall"
printf '  %s\n' "----------------------------------------------------------------------------------------------------------"

for report in "${reports[@]}"; do
  ci_local="$(awk -F': ' '/- make ci-local-status:/ {print $2; exit}' "$report")"
  ci_all="$(awk -F': ' '/- make test-ci-all:/ {print $2; exit}' "$report")"
  smoke_local="$(awk -F': ' '/- make smoke-gateway-local:/ {print $2; exit}' "$report")"
  smoke_auth="$(awk -F': ' '/- make smoke-gateway-auth:/ {print $2; exit}' "$report")"
  service_status="$(awk -F': ' '/- systemctl --user status openedai-gateway.service:/ {print $2; exit}' "$report")"

  ci_local="${ci_local:-missing}"
  ci_all="${ci_all:-missing}"
  smoke_value="${smoke_local:-}"
  if [[ -z "$smoke_value" ]]; then
    smoke_value="${smoke_auth:-}"
  fi
  smoke_value="${smoke_value:-missing}"
  service_status="${service_status:-missing}"

  report_overall="PASS"
  if [[ "$ci_local" == "missing" || "$ci_all" == "missing" || "$smoke_value" == "missing" || "$service_status" == "missing" ]]; then
    report_overall="UNKNOWN"
  elif [[ "$ci_local" != "0" || "$ci_all" != "0" || "$smoke_value" != "0" || "$service_status" != "0" ]]; then
    report_overall="FAIL"
  fi

  printf '  %-45s | %-8s | %-8s | %-8s | %-8s | %-8s\n' "$(basename "$report")" "$ci_local" "$ci_all" "$smoke_value" "$service_status" "$report_overall"
done
