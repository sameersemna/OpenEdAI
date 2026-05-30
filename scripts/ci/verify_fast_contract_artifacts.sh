#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

report_path="${1:-${FAST_CONTRACT_REPORT:-}}"
contract_json="${2:-${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}}"
summary_json="${3:-${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}}"
trend_json="${4:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
verdict_json="${5:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"
consistency_json="${6:-${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}}"
kpi_json="${7:-${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}}"
checksums_path="${8:-${FAST_CONTRACT_CHECKSUMS:-artifacts/contracts/sha256sums.txt}}"
manifest_path="${9:-${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}}"

if [[ -z "$report_path" || ! -f "$report_path" ]]; then
  echo "[contracts][fail] fast contract report not found: ${report_path:-<empty>}" >&2
  exit 1
fi

for artifact in "$contract_json" "$summary_json" "$trend_json" "$verdict_json"; do
  if [[ ! -s "$artifact" ]]; then
    echo "[contracts][fail] artifact missing or empty: $artifact" >&2
    exit 1
  fi
done

bash "$repo_root/scripts/ci/validate_fast_contract_report_markdown.sh" "$report_path"

bash "$repo_root/scripts/ci/validate_contract_env_status_json.sh" "$contract_json"
bash "$repo_root/scripts/ci/validate_fast_contract_status_summary_json.sh" "$summary_json"
bash "$repo_root/scripts/ci/validate_fast_contract_trend_json.sh" "$trend_json"
bash "$repo_root/scripts/ci/validate_fast_contract_gate_verdict_json.sh" "$verdict_json"
FAST_CONTRACT_CONSISTENCY_WRITE=0 bash "$repo_root/scripts/ci/validate_fast_contract_consistency.sh" "$report_path" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json"
bash "$repo_root/scripts/ci/validate_fast_contract_consistency_json.sh" "$consistency_json"
bash "$repo_root/scripts/ci/validate_fast_contract_consistency_kpi_json.sh" "$kpi_json"
bash "$repo_root/scripts/ci/validate_fast_contract_artifact_manifest.sh" "$manifest_path"
bash "$repo_root/scripts/ci/assert_fast_contract_artifact_manifest_paths.sh" "$manifest_path"
bash "$repo_root/scripts/ci/verify_fast_contract_checksums.sh" "$checksums_path" "$manifest_path"

echo "[contracts][ok] verified fast contract artifacts for upload"
