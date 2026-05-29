#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

latest_two="$(ls -1t docs/reports/*-local-release-smoke.md 2>/dev/null | head -n2 || true)"
latest_report="$(printf '%s\n' "$latest_two" | sed -n '1p')"
previous_report="$(printf '%s\n' "$latest_two" | sed -n '2p')"

if [[ -z "$latest_report" || -z "$previous_report" ]]; then
  echo '{"error":"need at least two standard local smoke reports (*-local-release-smoke.md) in docs/reports"}'
  exit 1
fi

extract_checks() {
  local file="$1"
  awk -F': ' '/^- make / {print $1 "\t" $2}' "$file"
}

declare -A latest_map
while IFS=$'\t' read -r key value; do
  [[ -z "$key" ]] && continue
  latest_map["$key"]="$value"
done < <(extract_checks "$latest_report")

declare -A previous_map
while IFS=$'\t' read -r key value; do
  [[ -z "$key" ]] && continue
  previous_map["$key"]="$value"
done < <(extract_checks "$previous_report")

keys="$({ printf '%s\n' "${!latest_map[@]}"; printf '%s\n' "${!previous_map[@]}"; } | sort -u)"

changes_json=""
changes_count=0

while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  latest_value="${latest_map[$key]:-missing}"
  previous_value="${previous_map[$key]:-missing}"
  if [[ "$latest_value" != "$previous_value" ]]; then
    key_escaped="${key//\"/\\\"}"
    latest_escaped="${latest_value//\"/\\\"}"
    previous_escaped="${previous_value//\"/\\\"}"
    item="{\"check\":\"${key_escaped}\",\"latest\":\"${latest_escaped}\",\"previous\":\"${previous_escaped}\"}"
    if [[ -z "$changes_json" ]]; then
      changes_json="$item"
    else
      changes_json="${changes_json},${item}"
    fi
    changes_count=$((changes_count + 1))
  fi
done <<< "$keys"

if [[ "$changes_count" -eq 0 ]]; then
  overall="NO_DRIFT"
else
  overall="DRIFT"
fi

printf '{"latest":"%s","previous":"%s","overall":"%s","changes_count":%d,"changes":[%s]}\n' \
  "$latest_report" "$previous_report" "$overall" "$changes_count" "$changes_json"
