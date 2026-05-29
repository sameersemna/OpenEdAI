#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

keep_standard="${KEEP_STANDARD:-20}"
keep_auth="${KEEP_AUTH:-20}"
max_standard_total="${MAX_STANDARD_TOTAL:-200}"
max_auth_total="${MAX_AUTH_TOTAL:-200}"

set +e
output="$(KEEP_STANDARD="$keep_standard" KEEP_AUTH="$keep_auth" MAX_STANDARD_TOTAL="$max_standard_total" MAX_AUTH_TOTAL="$max_auth_total" bash scripts/ci/report_prune_assert_json.sh 2>&1)"
rc=$?
set -e

echo "[prune-assert][json] ${output}"

if [[ "$rc" == "0" ]]; then
  echo "[prune-assert][ok] totals within limits"
  exit 0
fi

status="$(printf '%s\n' "$output" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
if [[ "$status" == "fail" ]]; then
  standard_total="$(printf '%s\n' "$output" | sed -n 's/.*"totals":{"standard":\([0-9][0-9]*\),"auth".*/\1/p')"
  auth_total="$(printf '%s\n' "$output" | sed -n 's/.*"totals":{"standard":[0-9][0-9]*,"auth":\([0-9][0-9]*\).*/\1/p')"
  standard_old_count="$(printf '%s\n' "$output" | sed -n 's/.*"age_summary":{"standard":{"old_count":\([0-9][0-9]*\),"oldest_age_days".*/\1/p')"
  auth_old_count="$(printf '%s\n' "$output" | sed -n 's/.*"age_summary":{"standard":{"old_count":[0-9][0-9]*,"oldest_age_days":[0-9-][0-9-]*},"auth":{"old_count":\([0-9][0-9]*\),"oldest_age_days".*/\1/p')"
  max_standard_age_days="$(printf '%s\n' "$output" | sed -n 's/.*"age_policy":{"max_standard_age_days":\(-*[0-9][0-9]*\),"max_auth_age_days".*/\1/p')"
  max_auth_age_days="$(printf '%s\n' "$output" | sed -n 's/.*"age_policy":{"max_standard_age_days":-*[0-9][0-9]*,"max_auth_age_days":\(-*[0-9][0-9]*\).*/\1/p')"

  if [[ -n "$standard_total" && "$standard_total" =~ ^[0-9]+$ ]] && (( standard_total > max_standard_total )); then
    echo "[prune-assert][fail] standard report total exceeded (total=${standard_total}, max=${max_standard_total})"
  fi
  if [[ -n "$auth_total" && "$auth_total" =~ ^[0-9]+$ ]] && (( auth_total > max_auth_total )); then
    echo "[prune-assert][fail] auth report total exceeded (total=${auth_total}, max=${max_auth_total})"
  fi
  if [[ -n "$standard_old_count" && "$standard_old_count" =~ ^[0-9]+$ && -n "$max_standard_age_days" && "$max_standard_age_days" =~ ^-?[0-9]+$ ]] && (( max_standard_age_days >= 0 )) && (( standard_old_count > 0 )); then
    echo "[prune-assert][fail] standard report age policy violated (old_count=${standard_old_count}, max_age_days=${max_standard_age_days})"
  fi
  if [[ -n "$auth_old_count" && "$auth_old_count" =~ ^[0-9]+$ && -n "$max_auth_age_days" && "$max_auth_age_days" =~ ^-?[0-9]+$ ]] && (( max_auth_age_days >= 0 )) && (( auth_old_count > 0 )); then
    echo "[prune-assert][fail] auth report age policy violated (old_count=${auth_old_count}, max_age_days=${max_auth_age_days})"
  fi
else
  echo "[prune-assert][fail] prune assert JSON command returned an error"
fi

exit 1
