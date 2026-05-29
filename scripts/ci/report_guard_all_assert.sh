#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

expected_overall="${1:-PASS}"
expected_auth_mode="${2:-ANY}"

if [[ "$expected_overall" != "PASS" && "$expected_overall" != "FAIL" ]]; then
  echo "[guard-assert][fail] expected_overall must be PASS or FAIL (got: $expected_overall)"
  exit 1
fi

if [[ "$expected_auth_mode" != "ANY" && "$expected_auth_mode" != "SKIPPED" && "$expected_auth_mode" != "ENFORCED" ]]; then
  echo "[guard-assert][fail] expected_auth_mode must be ANY, SKIPPED, or ENFORCED (got: $expected_auth_mode)"
  exit 1
fi

guard_json="$(bash scripts/ci/report_guard_all_json.sh || true)"

actual_overall="$(printf '%s\n' "$guard_json" | sed -n 's/^{"overall":"\([^"]*\)".*/\1/p' | head -n1)"
actual_auth_mode="$(printf '%s\n' "$guard_json" | sed -n 's/.*"auth":{"mode":"\([^"]*\)".*/\1/p' | head -n1)"
actual_auth_overall="$(printf '%s\n' "$guard_json" | sed -n 's/.*"auth":{[^}]*"overall":"\([^"]*\)".*/\1/p' | head -n1)"

if [[ -z "$actual_overall" || -z "$actual_auth_mode" ]]; then
  echo "[guard-assert][fail] unable to parse report-guard-all-json output"
  echo "[guard-assert][context] $guard_json"
  exit 1
fi

if [[ "$actual_overall" != "$expected_overall" ]]; then
  echo "[guard-assert][fail] overall mismatch (expected=$expected_overall actual=$actual_overall)"
  echo "[guard-assert][context] $guard_json"
  exit 1
fi

if [[ "$expected_auth_mode" != "ANY" && "$actual_auth_mode" != "$expected_auth_mode" ]]; then
  echo "[guard-assert][fail] auth mode mismatch (expected=$expected_auth_mode actual=$actual_auth_mode)"
  echo "[guard-assert][context] $guard_json"
  exit 1
fi

echo "[guard-assert][ok] overall=$actual_overall auth_mode=$actual_auth_mode auth_overall=${actual_auth_overall:-unknown}"
echo "[guard-assert][json] $guard_json"
