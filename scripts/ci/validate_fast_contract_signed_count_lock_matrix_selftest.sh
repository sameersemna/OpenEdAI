#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assertor="${script_dir}/assert_fast_contract_artifact_manifest_paths.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T23:00:00+00:00",
  "workflow": "fast-contract-gate",
  "manifest_version": "v1",
  "allowed_prefixes": ["docs/reports/", "artifacts/contracts/"],
  "files": [
    "artifacts/contracts/contract-env-status.json",
    "artifacts/contracts/fast-contract-status-summary.json",
    "docs/reports/20260530-000000-fast-contract-gate-report.md"
  ],
  "signed_artifact_count": 3
}
EOF

run_expect_pass() {
  local label="$1"
  shift

  if ! env "$@" bash "$assertor" "$valid_json" >/dev/null 2>&1; then
    echo "[contracts][fail] ${label} should pass" >&2
    exit 1
  fi
}

run_expect_fail() {
  local label="$1"
  shift

  set +e
  env "$@" bash "$assertor" "$valid_json" >"${tmp_dir}/fail.log" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" == "0" ]]; then
    echo "[contracts][fail] ${label} should fail" >&2
    exit 1
  fi

  if ! grep -q "signed_artifact_count mismatch" "${tmp_dir}/fail.log"; then
    echo "[contracts][fail] ${label} should fail with signed_artifact_count mismatch" >&2
    cat "${tmp_dir}/fail.log" >&2
    exit 1
  fi
}

run_expect_pass "baseline-without-lock-overrides"
run_expect_pass "expected-count-only" FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=3
run_expect_pass "version-map-only" FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3
run_expect_pass "both-locks-consistent" FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=3 FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3

run_expect_fail "expected-count-mismatch-with-valid-version-map" FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=4 FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=3
run_expect_fail "version-map-mismatch-with-valid-expected-count" FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=3 FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=4

echo "[contracts][ok] fast contract signed-count lock matrix selftest passed"
