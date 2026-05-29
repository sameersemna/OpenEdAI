#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

latest_two="$(ls -1t docs/reports/*-local-release-smoke.md 2>/dev/null | head -n2 || true)"
latest_report="$(printf '%s\n' "$latest_two" | sed -n '1p')"
previous_report="$(printf '%s\n' "$latest_two" | sed -n '2p')"

if [[ -z "$latest_report" || -z "$previous_report" ]]; then
  echo "[compare][fail] need at least two standard local smoke reports (*-local-release-smoke.md) in docs/reports"
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

keys="$(
  {
    printf '%s\n' "${!latest_map[@]}"
    printf '%s\n' "${!previous_map[@]}"
  } | sort -u
)"

echo "latest:   $latest_report"
echo "previous: $previous_report"
echo "summary:"

changes=0
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  latest_value="${latest_map[$key]:-missing}"
  previous_value="${previous_map[$key]:-missing}"
  if [[ "$latest_value" == "$previous_value" ]]; then
    printf '  [same]   %s -> %s\n' "$key" "$latest_value"
  else
    printf '  [change] %s -> latest=%s previous=%s\n' "$key" "$latest_value" "$previous_value"
    changes=$((changes + 1))
  fi
done <<< "$keys"

if [[ "$changes" -eq 0 ]]; then
  echo "result: no checklist drift detected"
else
  echo "result: checklist drift detected (${changes} change(s))"
fi
