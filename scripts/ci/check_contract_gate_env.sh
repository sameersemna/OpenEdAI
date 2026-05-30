#!/usr/bin/env bash
set -euo pipefail

mode="${1:-fast}"
strict_env_required="${FAST_CONTRACTS_REQUIRE_INTEGRATION_ENV:-0}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
env_file="${repo_root}/.env"

if [[ "${AUTO_SOURCE_ENV:-0}" == "1" && -f "$env_file" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a
  echo "[contracts][info] sourced $env_file"
fi

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

print_status() {
  local pg_status="down"
  local redis_status="down"
  local litellm_status="down"

  if check_tcp "$postgres_host" "$postgres_port"; then
    pg_status="up"
  fi
  if check_tcp "$redis_host" "$redis_port"; then
    redis_status="up"
  fi
  if check_tcp "$litellm_host" "$litellm_port"; then
    litellm_status="up"
  fi

  echo "[contracts][status] mode=${mode}"
  if [[ -n "${API_KEY_HASH_PEPPER:-}" ]]; then
    echo "[contracts][status] API_KEY_HASH_PEPPER=set"
  else
    echo "[contracts][status] API_KEY_HASH_PEPPER=missing"
  fi
  echo "[contracts][status] POSTGRES=${postgres_host}:${postgres_port} (${pg_status})"
  echo "[contracts][status] REDIS=${redis_host}:${redis_port} (${redis_status})"
  echo "[contracts][status] LITELLM=${litellm_host}:${litellm_port} (${litellm_status})"
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

if [[ "$mode" == "status" ]]; then
  print_status
  exit 0
fi

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
