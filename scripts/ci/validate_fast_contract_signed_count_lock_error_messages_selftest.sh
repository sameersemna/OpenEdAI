#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assertor="${script_dir}/assert_fast_contract_artifact_manifest_paths.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
cat >"$valid_json" <<'EOF'
{
  "generated_at": "2026-05-30T23:30:00+00:00",
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

expect_fail_message() {
  local label="$1"
  local expected="$2"
  shift 2

  local output
  local rc

  set +e
  output="$(env "$@" bash "$assertor" "$valid_json" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" == "0" ]]; then
    echo "[contracts][fail] ${label} should fail" >&2
    exit 1
  fi

  local last_line
  last_line="$(printf '%s\n' "$output" | awk 'NF{line=$0} END{print line}')"
  if [[ "$last_line" != "$expected" ]]; then
    echo "[contracts][fail] ${label} expected exact message mismatch" >&2
    echo "[contracts][fail] expected: ${expected}" >&2
    echo "[contracts][fail] actual:   ${last_line}" >&2
    echo "[contracts][fail] full output:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_fail_message \
  "expected-count-mismatch-message" \
  "[contracts][fail] artifact manifest signed_artifact_count mismatch (actual=3 expected=4)" \
  FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=4

expect_fail_message \
  "version-map-mismatch-message" \
  "[contracts][fail] artifact manifest signed_artifact_count mismatch for version v1 (actual=3 expected=4)" \
  FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=4

expect_fail_message \
  "version-map-missing-version-message" \
  "[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION missing manifest_version=v1" \
  FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v2=3

expect_fail_message \
  "version-map-format-message" \
  "[contracts][fail] FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION entries must be in <version>=<count> format" \
  FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1:3

echo "[contracts][ok] fast contract signed-count lock error-message selftest passed"
