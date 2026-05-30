#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
checker="${repo_root}/scripts/ci/check_contract_gate_env.sh"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "[selftest][fail] expected output to contain: $needle" >&2
    echo "[selftest][fail] file content:" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_status_json() {
  local require_all_up="$1"
  local out_file="$2"
  local err_file="$3"

  set +e
  POSTGRES_HOST=127.0.0.1 \
  POSTGRES_PORT=1 \
  REDIS_HOST=127.0.0.1 \
  REDIS_PORT=1 \
  LITELLM_HOST=127.0.0.1 \
  LITELLM_PORT=1 \
  STATUS_REQUIRE_ALL_UP="$require_all_up" \
  API_KEY_HASH_PEPPER="" \
  bash "$checker" status-json >"$out_file" 2>"$err_file"
  local rc=$?
  set -e

  echo "$rc"
}

cleanup() {
  rm -f "${out1:-}" "${err1:-}" "${out2:-}" "${err2:-}"
}

main() {
  local rc

  out1="$(mktemp)"
  err1="$(mktemp)"
  out2="$(mktemp)"
  err2="$(mktemp)"

  trap cleanup EXIT

  rc="$(run_status_json 0 "$out1" "$err1")"
  if [[ "$rc" != "0" ]]; then
    echo "[selftest][fail] expected STATUS_REQUIRE_ALL_UP=0 to succeed, got rc=$rc" >&2
    cat "$err1" >&2
    exit 1
  fi
  assert_contains "$out1" '"mode": "status-json"'
  assert_contains "$out1" '"overall_status": "degraded"'
  assert_contains "$out1" '"status_require_all_up": 0'

  rc="$(run_status_json 1 "$out2" "$err2")"
  if [[ "$rc" == "0" ]]; then
    echo "[selftest][fail] expected STATUS_REQUIRE_ALL_UP=1 to fail when services are down" >&2
    cat "$out2" >&2
    cat "$err2" >&2
    exit 1
  fi
  assert_contains "$out2" '"status_require_all_up": 1'
  assert_contains "$err2" '[contracts][fail] one or more services are down while STATUS_REQUIRE_ALL_UP=1'

  echo "[selftest][ok] check_contract_gate_env status-json behavior validated"
}

main "$@"
