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

service_status() {
  local host="$1"
  local port="$2"
  if check_tcp "$host" "$port"; then
    echo "up"
  else
    echo "down"
  fi
}

print_status() {
  local pg_status
  local redis_status
  local litellm_status

  pg_status="$(service_status "$postgres_host" "$postgres_port")"
  redis_status="$(service_status "$redis_host" "$redis_port")"
  litellm_status="$(service_status "$litellm_host" "$litellm_port")"

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

print_status_json() {
  local pg_status
  local redis_status
  local litellm_status
  local pepper_status
  local sourced_env="false"

  pg_status="$(service_status "$postgres_host" "$postgres_port")"
  redis_status="$(service_status "$redis_host" "$redis_port")"
  litellm_status="$(service_status "$litellm_host" "$litellm_port")"

  if [[ -n "${API_KEY_HASH_PEPPER:-}" ]]; then
    pepper_status="set"
  else
    pepper_status="missing"
  fi
  if [[ "${AUTO_SOURCE_ENV:-0}" == "1" ]]; then
    sourced_env="true"
  fi

  cat <<EOF
{
  "mode": "${mode}",
  "auto_source_env": ${sourced_env},
  "api_key_hash_pepper": "${pepper_status}",
  "services": {
    "postgres": {"host": "${postgres_host}", "port": ${postgres_port}, "status": "${pg_status}"},
    "redis": {"host": "${redis_host}", "port": ${redis_port}, "status": "${redis_status}"},
    "litellm": {"host": "${litellm_host}", "port": ${litellm_port}, "status": "${litellm_status}"}
  }
}
EOF
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

if [[ "$mode" == "status-json" ]]; then
  print_status_json
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
