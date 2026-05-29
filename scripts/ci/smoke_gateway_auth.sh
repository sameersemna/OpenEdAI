#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

set -a
source .env
set +a

cleanup_key_id=""

sha256_text() {
  local text="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  echo "[smoke-auth][fail] missing sha256sum/shasum; cannot hash bootstrap key"
  return 1
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi
  if command -v od >/dev/null 2>&1; then
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
    return 0
  fi
  echo "[smoke-auth][fail] missing openssl/od; cannot generate bootstrap secret"
  return 1
}

cleanup_bootstrap_key() {
  if [[ -z "$cleanup_key_id" ]]; then
    return 0
  fi
  if ! command -v psql >/dev/null 2>&1; then
    return 0
  fi

  PGPASSWORD="${POSTGRES_PASSWORD:-}" \
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 -qAt \
    -c "DELETE FROM api_keys WHERE id='${cleanup_key_id}'" >/dev/null 2>&1 || true
}

bootstrap_split_admin_key() {
  if [[ -z "${API_KEY_HASH_PEPPER:-}" ]]; then
    echo "[smoke-auth][fail] API_KEY_HASH_PEPPER is required to bootstrap an auth smoke key"
    return 1
  fi
  if ! command -v psql >/dev/null 2>&1; then
    echo "[smoke-auth][fail] psql is required to bootstrap an auth smoke key"
    return 1
  fi

  local key_id
  key_id="$(cat /proc/sys/kernel/random/uuid)"
  local secret
  secret="$(random_secret)"
  local hash
  hash="$(sha256_text "${API_KEY_HASH_PEPPER}:${secret}")"

  PGPASSWORD="${POSTGRES_PASSWORD:-}" \
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 -qAt \
    -c "INSERT INTO api_keys(id, name, key_hash, is_active, is_admin, rate_limit_per_minute) VALUES ('${key_id}', 'ci-smoke-bootstrap', '${hash}', TRUE, TRUE, 120)" >/dev/null

  cleanup_key_id="$key_id"
  GATEWAY_TEST_API_KEY="sk_ed_${key_id}.${secret}"
  export GATEWAY_TEST_API_KEY
  echo "[smoke-auth] bootstrapped temporary admin key id=${key_id}"
}

trap cleanup_bootstrap_key EXIT

run_smoke_auth() {
  set +e
  bash scripts/ci/smoke_gateway.sh
  local rc=$?
  set -e
  return "$rc"
}

if [[ -z "${GATEWAY_TEST_API_KEY:-}" ]]; then
  echo "[smoke-auth] GATEWAY_TEST_API_KEY is not set; bootstrapping temporary admin key"
  bootstrap_split_admin_key
fi

echo "[smoke-auth] running authenticated local smoke checks"
if run_smoke_auth; then
  exit 0
fi

if [[ -z "$cleanup_key_id" ]]; then
  echo "[smoke-auth][warn] provided key failed; retrying with a bootstrapped temporary admin key"
  bootstrap_split_admin_key
  run_smoke_auth
else
  echo "[smoke-auth][fail] auth smoke failed even with a bootstrapped temporary admin key"
  exit 1
fi
