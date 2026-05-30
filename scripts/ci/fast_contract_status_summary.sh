#!/usr/bin/env bash
set -euo pipefail

contract_json="${1:-artifacts/contracts/contract-env-status.json}"
report_path="${2:-}"
out_path="${3:-artifacts/contracts/fast-contract-status-summary.json}"

if [[ -z "$report_path" ]]; then
  report_path="$(ls -1t docs/reports/*-fast-contract-gate-report.md 2>/dev/null | head -1 || true)"
fi

if [[ ! -f "$contract_json" ]]; then
  echo "[contracts][fail] contract status json not found: $contract_json" >&2
  exit 1
fi

if [[ -z "$report_path" || ! -f "$report_path" ]]; then
  echo "[contracts][fail] fast contract report not found: ${report_path:-<empty>}" >&2
  exit 1
fi

extract_json_value() {
  local key="$1"
  local default_value="$2"
  local raw
  raw="$(grep -E "\"${key}\"[[:space:]]*:" "$contract_json" | head -1 || true)"
  if [[ -z "$raw" ]]; then
    echo "$default_value"
    return
  fi
  echo "$raw" | sed -E 's/^[^:]*:[[:space:]]*"?([^",}]+)"?.*$/\1/'
}

report_status="UNKNOWN"
if grep -Eq '^- Status:[[:space:]]*PASS$' "$report_path"; then
  report_status="PASS"
elif grep -Eq '^- Status:[[:space:]]*FAIL$' "$report_path"; then
  report_status="FAIL"
fi

contract_overall_status="$(extract_json_value overall_status unknown)"
status_require_all_up="$(extract_json_value status_require_all_up 0)"
auto_source_env="$(extract_json_value auto_source_env false)"
api_key_hash_pepper="$(extract_json_value api_key_hash_pepper missing)"

mkdir -p "$(dirname "$out_path")"

cat >"$out_path" <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "workflow": "fast-contract-gate",
  "report_path": "${report_path}",
  "report_status": "${report_status}",
  "contract_overall_status": "${contract_overall_status}",
  "status_require_all_up": ${status_require_all_up},
  "auto_source_env": ${auto_source_env},
  "api_key_hash_pepper": "${api_key_hash_pepper}",
  "overall": "${report_status}"
}
EOF

echo "[contracts][ok] wrote fast contract status summary: $out_path"
