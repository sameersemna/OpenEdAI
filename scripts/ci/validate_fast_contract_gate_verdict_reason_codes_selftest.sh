#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verdict_script="${script_dir}/fast_contract_gate_verdict.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

summary_ok="${tmp_dir}/summary-ok.json"
trend_ok="${tmp_dir}/trend-ok.json"
verdict_ok="${tmp_dir}/verdict-ok.json"

cat >"$summary_ok" <<'EOF'
{"report_status":"PASS","contract_overall_status":"degraded","status_require_all_up":0}
EOF
cat >"$trend_ok" <<'EOF'
{"summary":{"fail":0,"unknown":0,"pass_rate_percent":100.0}}
EOF

bash "$verdict_script" "$summary_ok" "$trend_ok" "$verdict_ok" 0 0 100 >/dev/null
python3 - "$verdict_ok" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

expected = ["none"]
if payload.get("reason_codes") != expected:
    raise SystemExit(f"[contracts][fail] expected baseline reason codes {expected}, got {payload.get('reason_codes')}")
PY

summary_fail="${tmp_dir}/summary-fail.json"
trend_fail="${tmp_dir}/trend-fail.json"
verdict_fail="${tmp_dir}/verdict-fail.json"

cat >"$summary_fail" <<'EOF'
{"report_status":"FAIL","contract_overall_status":"degraded","status_require_all_up":1}
EOF
cat >"$trend_fail" <<'EOF'
{"summary":{"fail":2,"unknown":1,"pass_rate_percent":70.0}}
EOF

bash "$verdict_script" "$summary_fail" "$trend_fail" "$verdict_fail" 0 0 100 >/dev/null
python3 - "$verdict_fail" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

expected = [
    "report_status_not_pass",
    "threshold_fail_exceeded",
    "threshold_unknown_exceeded",
    "threshold_pass_rate_below_min",
    "required_all_up_but_degraded",
]
if payload.get("reason_codes") != expected:
    raise SystemExit(f"[contracts][fail] expected ordered reason codes {expected}, got {payload.get('reason_codes')}")
PY

echo "[contracts][ok] fast contract gate verdict reason-code selftest passed"
