#!/usr/bin/env bash
set -euo pipefail

consistency_json="${1:-${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}}"
trend_json="${2:-${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}}"
verdict_json="${3:-${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}}"
out_json="${4:-${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}}"

for path in "$consistency_json" "$trend_json" "$verdict_json"; do
  if [[ ! -f "$path" ]]; then
    echo "[contracts][fail] required artifact not found: $path" >&2
    exit 1
  fi
done

python3 - "$consistency_json" "$trend_json" "$verdict_json" "$out_json" <<'PY'
import json
import sys
from datetime import datetime, timezone

consistency_path, trend_path, verdict_path, out_path = sys.argv[1:5]

with open(consistency_path, "r", encoding="utf-8") as f:
    consistency = json.load(f)
with open(trend_path, "r", encoding="utf-8") as f:
    trend = json.load(f)
with open(verdict_path, "r", encoding="utf-8") as f:
    verdict = json.load(f)

reason_codes = list(consistency.get("reason_codes", []))
non_none_reasons = [code for code in reason_codes if code != "none"]
trend_summary = trend.get("summary", {})

payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "workflow": "fast-contract-gate",
    "kpi_version": "v1",
    "overall": str(consistency.get("overall", "UNKNOWN")),
    "consistency_pass": 1 if str(consistency.get("overall", "UNKNOWN")) == "PASS" else 0,
    "gate_pass": 1 if str(verdict.get("overall", "UNKNOWN")) == "PASS" else 0,
    "reason_codes": reason_codes,
    "reason_count": len(non_none_reasons),
    "has_inconsistency": 1 if non_none_reasons else 0,
    "expected_overall": str(consistency.get("expected_from_thresholds", {}).get("overall", "UNKNOWN")),
    "verdict_overall": str(verdict.get("overall", "UNKNOWN")),
    "pass_rate_percent": float(trend_summary.get("pass_rate_percent", 0.0)),
    "fail_count": int(trend_summary.get("fail", 0)),
    "unknown_count": int(trend_summary.get("unknown", 0)),
    "sources": {
        "consistency": consistency_path,
        "trend": trend_path,
        "verdict": verdict_path,
    },
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))

print(f"[contracts][ok] wrote fast contract consistency kpi json: {out_path}")
PY
