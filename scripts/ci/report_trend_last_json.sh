#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

limit="${1:-5}"
if ! [[ "$limit" =~ ^[1-9][0-9]*$ ]]; then
  echo '{"error":"limit must be a positive integer"}'
  exit 1
fi

mapfile -t reports < <(ls -1t docs/reports/*-local-release-smoke*.md 2>/dev/null | head -n "$limit")

if [[ "${#reports[@]}" -eq 0 ]]; then
  echo '{"error":"no local smoke reports found in docs/reports"}'
  exit 1
fi

items=""
pass_count=0
fail_count=0
unknown_count=0
for report in "${reports[@]}"; do
  ci_local="$(awk -F': ' '/- make ci-local-status:/ {print $2; exit}' "$report")"
  ci_all="$(awk -F': ' '/- make test-ci-all:/ {print $2; exit}' "$report")"
  smoke_local="$(awk -F': ' '/- make smoke-gateway-local:/ {print $2; exit}' "$report")"
  smoke_auth="$(awk -F': ' '/- make smoke-gateway-auth:/ {print $2; exit}' "$report")"
  service_status="$(awk -F': ' '/- systemctl --user status openedai-gateway.service:/ {print $2; exit}' "$report")"

  ci_local="${ci_local:-missing}"
  ci_all="${ci_all:-missing}"
  smoke_value="${smoke_local:-}"
  smoke_source="smoke_gateway_local"
  if [[ -z "$smoke_value" ]]; then
    smoke_value="${smoke_auth:-}"
    smoke_source="smoke_gateway_auth"
  fi
  smoke_value="${smoke_value:-missing}"
  service_status="${service_status:-missing}"

  report_overall="PASS"
  if [[ "$ci_local" == "missing" || "$ci_all" == "missing" || "$smoke_value" == "missing" || "$service_status" == "missing" ]]; then
    report_overall="UNKNOWN"
    unknown_count=$((unknown_count + 1))
  elif [[ "$ci_local" == "0" && "$ci_all" == "0" && "$smoke_value" == "0" && "$service_status" == "0" ]]; then
    pass_count=$((pass_count + 1))
  else
    report_overall="FAIL"
    fail_count=$((fail_count + 1))
  fi

  report_base="$(basename "$report")"

  item=$(printf '{"report":"%s","overall":"%s","checks":{"ci_local_status":"%s","test_ci_all":"%s","smoke_source":"%s","smoke_status":"%s","service_status":"%s"}}' \
    "$report_base" "$report_overall" "$ci_local" "$ci_all" "$smoke_source" "$smoke_value" "$service_status")

  if [[ -z "$items" ]]; then
    items="$item"
  else
    items="$items,$item"
  fi
done

count="${#reports[@]}"
pass_rate_percent="$(awk -v p="$pass_count" -v c="$count" 'BEGIN { if (c == 0) { printf "0.0" } else { printf "%.1f", (p * 100.0) / c } }')"

printf '{"limit":%s,"count":%s,"summary":{"pass":%s,"fail":%s,"unknown":%s,"pass_rate_percent":%s},"reports":[%s]}\n' \
  "$limit" "$count" "$pass_count" "$fail_count" "$unknown_count" "$pass_rate_percent" "$items"
