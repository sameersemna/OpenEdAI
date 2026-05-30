#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
verdict_script="${repo_root}/scripts/ci/fast_contract_gate_verdict.sh"

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
if ! grep -q '"overall":"PASS"' "$verdict_ok"; then
  echo "[contracts][fail] expected PASS verdict" >&2
  cat "$verdict_ok" >&2
  exit 1
fi

summary_bad="${tmp_dir}/summary-bad.json"
trend_bad="${tmp_dir}/trend-bad.json"
verdict_bad="${tmp_dir}/verdict-bad.json"

cat >"$summary_bad" <<'EOF'
{"report_status":"FAIL","contract_overall_status":"degraded","status_require_all_up":1}
EOF
cat >"$trend_bad" <<'EOF'
{"summary":{"fail":2,"unknown":1,"pass_rate_percent":70.0}}
EOF

bash "$verdict_script" "$summary_bad" "$trend_bad" "$verdict_bad" 0 0 100 >/dev/null
if ! grep -q '"overall":"FAIL"' "$verdict_bad"; then
  echo "[contracts][fail] expected FAIL verdict" >&2
  cat "$verdict_bad" >&2
  exit 1
fi
if ! grep -q 'threshold_fail_exceeded' "$verdict_bad"; then
  echo "[contracts][fail] expected threshold fail reason code" >&2
  cat "$verdict_bad" >&2
  exit 1
fi

echo "[contracts][ok] fast contract gate verdict selftest passed"
