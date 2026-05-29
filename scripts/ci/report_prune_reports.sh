#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

keep_standard="${1:-${KEEP_STANDARD:-20}}"
keep_auth="${2:-${KEEP_AUTH:-20}}"
dry_run="${DRY_RUN:-0}"

is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

if ! is_non_negative_int "$keep_standard"; then
  echo "{\"error\":\"KEEP_STANDARD must be a non-negative integer\"}"
  exit 1
fi

if ! is_non_negative_int "$keep_auth"; then
  echo "{\"error\":\"KEEP_AUTH must be a non-negative integer\"}"
  exit 1
fi

if [[ "$dry_run" != "0" && "$dry_run" != "1" ]]; then
  echo "{\"error\":\"DRY_RUN must be 0 or 1\"}"
  exit 1
fi

remove_old_reports() {
  local pattern="$1"
  local keep="$2"
  local removed_var="$3"
  local total_var="$4"
  local kept_var="$5"

  local -a files=()
  local -a removed=()
  mapfile -t files < <(ls -1t $pattern 2>/dev/null || true)

  local total="${#files[@]}"
  local kept="$total"

  if (( total > keep )); then
    kept="$keep"
    local idx
    for (( idx=keep; idx<total; idx++ )); do
      removed+=("${files[$idx]}")
      if [[ "$dry_run" == "0" ]]; then
        rm -f -- "${files[$idx]}"
      fi
    done
  fi

  local removed_json=""
  local f
  for f in "${removed[@]}"; do
    if [[ -n "$removed_json" ]]; then
      removed_json+=$'\n'
    fi
    removed_json+="$f"
  done

  printf -v "$removed_var" '%s' "$removed_json"
  printf -v "$total_var" '%s' "$total"
  printf -v "$kept_var" '%s' "$kept"
}

newline_list_to_json_array() {
  local lines="$1"
  local json=""
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="${line//"/\\"}"
    if [[ -z "$json" ]]; then
      json="\"$line\""
    else
      json="$json,\"$line\""
    fi
  done <<< "$lines"
  printf '[%s]' "$json"
}

standard_removed_lines=""
auth_removed_lines=""
standard_total="0"
auth_total="0"
standard_kept="0"
auth_kept="0"

remove_old_reports "docs/reports/*-local-release-smoke.md" "$keep_standard" standard_removed_lines standard_total standard_kept
remove_old_reports "docs/reports/*-local-release-smoke-auth.md" "$keep_auth" auth_removed_lines auth_total auth_kept

standard_removed_json="$(newline_list_to_json_array "$standard_removed_lines")"
auth_removed_json="$(newline_list_to_json_array "$auth_removed_lines")"

standard_removed_count="0"
auth_removed_count="0"
if [[ -n "$standard_removed_lines" ]]; then
  standard_removed_count="$(printf '%s\n' "$standard_removed_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
fi
if [[ -n "$auth_removed_lines" ]]; then
  auth_removed_count="$(printf '%s\n' "$auth_removed_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
fi

printf '{"overall":"PASS","mode":"%s","keep":{"standard":%s,"auth":%s},"summary":{"standard":{"total_before":%s,"kept":%s,"removed":%s},"auth":{"total_before":%s,"kept":%s,"removed":%s}},"removed":{"standard":%s,"auth":%s}}\n' \
  "$( [[ "$dry_run" == "1" ]] && echo "DRY_RUN" || echo "APPLY" )" \
  "$keep_standard" "$keep_auth" \
  "$standard_total" "$standard_kept" "$standard_removed_count" \
  "$auth_total" "$auth_kept" "$auth_removed_count" \
  "$standard_removed_json" "$auth_removed_json"
