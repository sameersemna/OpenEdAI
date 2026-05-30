#!/usr/bin/env bash
set -euo pipefail

mode="${1:-fast}"
strict_env_required="${FAST_CONTRACTS_REQUIRE_INTEGRATION_ENV:-0}"

postgres_host="${POSTGRES_HOST:-127.0.0.1}"
postgres_port="${POSTGRES_PORT:-5432}"
redis_host="${REDIS_HOST:-127.0.0.1}"
redis_port="${REDIS_PORT:-6379}"
litellm_host="${LITELLM_HOST:-127.0.0.1}"
litellm_port="${LITELLM_PORT:-4000}"

check_tcp() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

warn_or_fail() {
  local message="$1"
  local should_fail="$2"
  if [[ "$should_fail" == "1" ]]; then
    echo "[contracts][fail] ${message}" >&2
    exit 1
  fi
  echo "[contracts][warn] ${message}" >&2
}

if [[ -z "${API_KEY_HASH_PEPPER:-}" ]]; then
  fail_missing_env=0
  if [[ "$strict_env_required" == "1" || "$mode" == "strict" ]]; then
    fail_missing_env=1
  fi
  warn_or_fail "API_KEY_HASH_PEPPER is not set; some focused integration contracts can skip." "$fail_missing_env"
fi

if [[ "$mode" == "strict-local" ]]; then
  if ! check_tcp "$postgres_host" "$postgres_port"; then
    warn_or_fail "Postgres is not reachable at ${postgres_host}:${postgres_port}." 1
  fi
  if ! check_tcp "$redis_host" "$redis_port"; then
    warn_or_fail "Redis is not reachable at ${redis_host}:${redis_port}." 1
  fi
  if ! check_tcp "$litellm_host" "$litellm_port"; then
    warn_or_fail "LiteLLM is not reachable at ${litellm_host}:${litellm_port}." 1
  fi
  echo "[contracts][ok] strict-local backend reachability checks passed."
fi
