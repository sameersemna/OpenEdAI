#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

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

for path in "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json"; do
  if [[ ! -f "$path" ]]; then
    echo "[contracts][fail] required artifact not found: $path" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$checksums_path")"

python3 - "$checksums_path" "$manifest_path" "$report_path" "$contract_json" "$summary_json" "$trend_json" "$verdict_json" "$consistency_json" "$kpi_json" <<'PY'
import hashlib
import os
import sys
from pathlib import Path
import json

out_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
default_files = [Path(p) for p in sys.argv[3:]]

if manifest_path.exists():
  with manifest_path.open("r", encoding="utf-8") as f:
    manifest = json.load(f)
  files = [Path(p) for p in manifest.get("files", [])]
  if not files:
    raise SystemExit("[contracts][fail] artifact manifest files list is empty")
else:
  files = default_files

lines = []
for p in files:
  if not p.exists():
    raise SystemExit(f"[contracts][fail] cannot checksum missing file: {p}")
  digest = hashlib.sha256(p.read_bytes()).hexdigest()
  rel = os.path.relpath(str(p), start=os.getcwd())
  lines.append(f"{digest}  {rel}")

out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"[contracts][ok] wrote fast contract checksums: {out_path}")
PY
