#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

set -a
source .env
set +a

base_url="http://127.0.0.1:${GATEWAY_PORT}"

echo "[smoke] building gateway binary"
go build -o openedai-gateway ./cmd/gateway

echo "[smoke] restarting user service"
systemctl --user restart openedai-gateway.service

echo "[smoke] waiting for /livez"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "${base_url}/livez" >/tmp/openedai_livez.json; then
    break
  fi
  sleep 1
done

livez_status="$(curl -sS -o /tmp/openedai_livez_http.json -w '%{http_code}' "${base_url}/livez")"
healthz_status="$(curl -sS -o /tmp/openedai_healthz_http.json -w '%{http_code}' "${base_url}/healthz")"
unauth_usage_status="$(curl -sS -o /tmp/openedai_usage_unauth.json -w '%{http_code}' "${base_url}/v1/management/usage")"

if [[ "$livez_status" != "200" ]]; then
  echo "[smoke][fail] /livez returned ${livez_status}"
  exit 1
fi

if [[ "$healthz_status" != "200" && "$healthz_status" != "503" ]]; then
  echo "[smoke][fail] /healthz returned unexpected status ${healthz_status}"
  exit 1
fi

if [[ "$unauth_usage_status" != "401" ]]; then
  echo "[smoke][fail] expected unauthorized /v1/management/usage status 401, got ${unauth_usage_status}"
  exit 1
fi

echo "[smoke][ok] /livez=${livez_status} /healthz=${healthz_status} unauthorized_usage=${unauth_usage_status}"

if [[ -n "${GATEWAY_TEST_API_KEY:-}" ]]; then
  auth_usage_status="$(curl -sS -o /tmp/openedai_usage_auth.json -w '%{http_code}' -H "Authorization: Bearer ${GATEWAY_TEST_API_KEY}" "${base_url}/v1/management/usage")"
  if [[ "$auth_usage_status" != "200" ]]; then
    echo "[smoke][fail] expected authorized /v1/management/usage status 200, got ${auth_usage_status}"
    exit 1
  fi
  echo "[smoke][ok] authorized_usage=${auth_usage_status}"
else
  echo "[smoke][skip] set GATEWAY_TEST_API_KEY to include authorized management check"
fi
