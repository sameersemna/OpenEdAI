#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

keep_standard="${KEEP_STANDARD:-20}"
keep_auth="${KEEP_AUTH:-20}"
max_standard_total="${MAX_STANDARD_TOTAL:-200}"
max_auth_total="${MAX_AUTH_TOTAL:-200}"
max_standard_age_days="${MAX_STANDARD_AGE_DAYS:--1}"
max_auth_age_days="${MAX_AUTH_AGE_DAYS:--1}"

is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_int() {
  [[ "$1" =~ ^-?[0-9]+$ ]]
}

if ! is_non_negative_int "$max_standard_total"; then
  echo "{\"status\":\"error\",\"error\":\"MAX_STANDARD_TOTAL must be a non-negative integer\"}"
  exit 1
fi
if ! is_non_negative_int "$max_auth_total"; then
  echo "{\"status\":\"error\",\"error\":\"MAX_AUTH_TOTAL must be a non-negative integer\"}"
  exit 1
fi
if ! is_int "$max_standard_age_days"; then
  echo "{\"status\":\"error\",\"error\":\"MAX_STANDARD_AGE_DAYS must be an integer (use -1 to disable)\"}"
  exit 1
fi
if ! is_int "$max_auth_age_days"; then
  echo "{\"status\":\"error\",\"error\":\"MAX_AUTH_AGE_DAYS must be an integer (use -1 to disable)\"}"
  exit 1
fi

output="$(DRY_RUN=1 bash scripts/ci/report_prune_reports.sh "$keep_standard" "$keep_auth")"

standard_total="$(printf '%s\n' "$output" | sed -n 's/.*"standard":{"total_before":\([0-9][0-9]*\).*/\1/p')"
auth_total="$(printf '%s\n' "$output" | sed -n 's/.*"auth":{"total_before":\([0-9][0-9]*\).*/\1/p')"

if [[ -z "$standard_total" || -z "$auth_total" ]]; then
  echo "{\"status\":\"error\",\"error\":\"unable to parse prune summary totals\",\"context\":${output}}"
  exit 1
fi

calc_age_metrics() {
  local pattern="$1"
  local max_age="$2"
  local old_count_var="$3"
  local oldest_age_var="$4"

  local now_epoch
  now_epoch="$(date +%s)"
  local old_count=0
  local oldest_age=-1
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local mtime_epoch
    mtime_epoch="$(stat -c %Y "$file" 2>/dev/null || true)"
    [[ -z "$mtime_epoch" ]] && continue
    local age_days=$(( (now_epoch - mtime_epoch) / 86400 ))
    if (( age_days > oldest_age )); then
      oldest_age=$age_days
    fi
    if (( max_age >= 0 )) && (( age_days > max_age )); then
      old_count=$((old_count + 1))
    fi
  done < <(ls -1t $pattern 2>/dev/null || true)

  printf -v "$old_count_var" '%s' "$old_count"
  printf -v "$oldest_age_var" '%s' "$oldest_age"
}

standard_old_count=0
auth_old_count=0
standard_oldest_age=-1
auth_oldest_age=-1

calc_age_metrics "docs/reports/*-local-release-smoke.md" "$max_standard_age_days" standard_old_count standard_oldest_age
calc_age_metrics "docs/reports/*-local-release-smoke-auth.md" "$max_auth_age_days" auth_old_count auth_oldest_age

status="ok"
if (( standard_total > max_standard_total )); then
  status="fail"
fi
if (( auth_total > max_auth_total )); then
  status="fail"
fi
if (( max_standard_age_days >= 0 )) && (( standard_old_count > 0 )); then
  status="fail"
fi
if (( max_auth_age_days >= 0 )) && (( auth_old_count > 0 )); then
  status="fail"
fi

printf '{"status":"%s","keep":{"standard":%s,"auth":%s},"totals":{"standard":%s,"auth":%s},"limits":{"max_standard_total":%s,"max_auth_total":%s},"age_policy":{"max_standard_age_days":%s,"max_auth_age_days":%s},"age_summary":{"standard":{"old_count":%s,"oldest_age_days":%s},"auth":{"old_count":%s,"oldest_age_days":%s}}}\n' \
  "$status" "$keep_standard" "$keep_auth" "$standard_total" "$auth_total" "$max_standard_total" "$max_auth_total" "$max_standard_age_days" "$max_auth_age_days" "$standard_old_count" "$standard_oldest_age" "$auth_old_count" "$auth_oldest_age"

if [[ "$status" != "ok" ]]; then
  exit 1
fi
