#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-${FAST_CONTRACT_REPORT:-}}"
contract_json="${2:-${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}}"
summary_json="${3:-${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}}"
trend_json="${4:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
verdict_json="${5:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"
consistency_json="${6:-${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}}"
kpi_json="${7:-${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}}"
manifest_path="${8:-${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}}"

if [[ -z "$report_path" || ! -f "$report_path" ]]; then
  echo "[contracts][fail] fast contract report not found: ${report_path:-<empty>}" >&2
  exit 1
fi

for path in "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json"; do
  if [[ ! -f "$path" ]]; then
    echo "[contracts][fail] required artifact not found: $path" >&2
    exit 1
  fi
done

python3 - "$report_path" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json" "$manifest_path" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

report_path, contract_json, summary_json, trend_json, verdict_json, consistency_json, kpi_json, manifest_path = sys.argv[1:9]

files = [
    report_path,
    contract_json,
    summary_json,
    trend_json,
    verdict_json,
    consistency_json,
    kpi_json,
]
files = sorted(files)

allowed_prefixes = ["docs/reports/", "artifacts/contracts/"]
env_prefixes = os.getenv("FAST_CONTRACT_ALLOWED_PREFIXES", "").strip()
if env_prefixes:
    allowed_prefixes = [p.strip() for p in env_prefixes.split(",") if p.strip()]
    if not allowed_prefixes:
        raise SystemExit("[contracts][fail] FAST_CONTRACT_ALLOWED_PREFIXES provided but empty after parsing")

payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "workflow": "fast-contract-gate",
    "manifest_version": "v1",
    "allowed_prefixes": allowed_prefixes,
    "files": files,
    "signed_artifact_count": len(files),
}

os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))

print(f"[contracts][ok] wrote fast contract artifact manifest: {manifest_path}")
PY
