#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_old_report="docs/reports/19990101-000000-local-release-smoke.md"
cleanup() {
  rm -f "$tmp_old_report"
}
trap cleanup EXIT

run_expect_fail() {
  local label="$1"
  shift

  set +e
  "$@" >/tmp/openedai_policy_selftest.out 2>&1
  local rc=$?
  set -e

  if [[ "$rc" == "0" ]]; then
    echo "[policy-selftest][fail] expected failure for ${label}, but command succeeded"
    cat /tmp/openedai_policy_selftest.out
    exit 1
  fi

  echo "[policy-selftest][ok] ${label} failed as expected"
}

echo "[policy-selftest] baseline policy overview"
bash scripts/ci/report_policy_overview_json.sh >/tmp/openedai_policy_selftest_baseline.json

echo "[policy-selftest] forced trend threshold failure"
run_expect_fail "trend threshold" env MIN_PASS_RATE=101 bash scripts/ci/report_policy_overview_json.sh

echo "[policy-selftest] forced prune total failure"
run_expect_fail "prune totals" env MAX_STANDARD_TOTAL=1 MAX_AUTH_TOTAL=1 bash scripts/ci/report_policy_overview_json.sh

echo "[policy-selftest] forced prune age failure"
mkdir -p docs/reports
cat >"$tmp_old_report" <<'EOF'
# Synthetic smoke report for policy self-test
- CHECK:PLACEHOLDER=PASS
EOF
touch -d '45 days ago' "$tmp_old_report"
run_expect_fail "prune age" env MAX_STANDARD_AGE_DAYS=30 MAX_AUTH_AGE_DAYS=-1 bash scripts/ci/report_policy_overview_json.sh

echo "[policy-selftest][ok] all regression checks passed"
