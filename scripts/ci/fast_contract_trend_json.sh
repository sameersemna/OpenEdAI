#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

limit="${1:-${FAST_CONTRACT_TREND_LIMIT:-10}}"
out_path="${2:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"

if ! [[ "$limit" =~ ^[1-9][0-9]*$ ]]; then
  echo '{"error":"limit must be a positive integer"}'
  exit 1
fi

mapfile -t reports < <(ls -1t docs/reports/*-fast-contract-gate-report.md 2>/dev/null | head -n "$limit")

if [[ "${#reports[@]}" -eq 0 ]]; then
  echo '{"error":"no fast contract reports found in docs/reports"}'
  exit 1
fi

items=""
pass_count=0
fail_count=0
unknown_count=0

for report in "${reports[@]}"; do
  base="$(basename "$report")"
  ts="${base%%-fast-contract-gate-report.md}"

  status="UNKNOWN"
  if grep -Eq '^- Status:[[:space:]]*PASS$' "$report"; then
    status="PASS"
    pass_count=$((pass_count + 1))
  elif grep -Eq '^- Status:[[:space:]]*FAIL$' "$report"; then
    status="FAIL"
    fail_count=$((fail_count + 1))
  else
    unknown_count=$((unknown_count + 1))
  fi

  item=$(printf '{"report":"%s","timestamp":"%s","status":"%s"}' "$base" "$ts" "$status")
  if [[ -z "$items" ]]; then
    items="$item"
  else
    items="$items,$item"
  fi
 done

count="${#reports[@]}"
pass_rate_percent="$(awk -v p="$pass_count" -v c="$count" 'BEGIN { if (c == 0) { printf "0.0" } else { printf "%.1f", (p * 100.0) / c } }')"

mkdir -p "$(dirname "$out_path")"

printf '{"generated_at":"%s","limit":%s,"count":%s,"summary":{"pass":%s,"fail":%s,"unknown":%s,"pass_rate_percent":%s},"reports":[%s]}
' \
  "$(date -Iseconds)" "$limit" "$count" "$pass_count" "$fail_count" "$unknown_count" "$pass_rate_percent" "$items" > "$out_path"

echo "[contracts][ok] wrote fast contract trend json: $out_path"
