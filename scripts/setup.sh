#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

LITELLM_BASE_URL=${LITELLM_BASE_URL:-http://latitude:11435}
LITELLM_HOST=$(echo "$LITELLM_BASE_URL" | sed -E 's#^[a-zA-Z]+://([^:/]+).*$#\1#')
LITELLM_PORT=$(echo "$LITELLM_BASE_URL" | sed -E 's#^[a-zA-Z]+://[^:/]+:([0-9]+).*$#\1#')
if [[ "$LITELLM_PORT" == "$LITELLM_BASE_URL" ]]; then
  LITELLM_PORT=11435
fi

SERVICES=(
  "promaxgb10-6116:11434:Ollama"
  "${LITELLM_HOST}:${LITELLM_PORT}:LiteLLM"
  "latitude:5432:PostgreSQL"
  "latitude:6379:Redis"
  "latitude:9200:Elasticsearch"
  "promaxgb10-6116:6333:Qdrant"
)

echo "[1/3] DNS resolution checks"
for entry in "${SERVICES[@]}"; do
  IFS=":" read -r host port name <<< "$entry"
  if getent hosts "$host" >/dev/null 2>&1; then
    echo "  OK   $name ($host)"
  else
    echo "  FAIL $name ($host)"
    exit 1
  fi
done

echo "[2/3] TCP connectivity checks"
for entry in "${SERVICES[@]}"; do
  IFS=":" read -r host port name <<< "$entry"
  if nc -z -w 2 "$host" "$port"; then
    echo "  OK   $name ($host:$port)"
  else
    echo "  FAIL $name ($host:$port)"
    exit 1
  fi
done

echo "[3/3] HTTP health probes"
if curl -fsS "${LITELLM_BASE_URL}/health" >/dev/null 2>&1; then
  echo "  OK   LiteLLM /health"
else
  echo "  WARN LiteLLM /health not reachable (endpoint may differ)"
fi

ES_URL=${ELASTICSEARCH_URL:-http://latitude:9200}
ES_CURL_ARGS=(-sS -m 5 -o /tmp/es_probe.out -w "%{http_code}")
if [[ "${ELASTICSEARCH_INSECURE_SKIP_VERIFY:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  ES_CURL_ARGS+=(-k)
fi
if [[ -n "${ELASTICSEARCH_API_KEY:-}" ]]; then
  ES_CURL_ARGS+=(-H "Authorization: ApiKey ${ELASTICSEARCH_API_KEY}")
elif [[ -n "${ELASTICSEARCH_USERNAME:-}" || -n "${ELASTICSEARCH_PASSWORD:-}" ]]; then
  ES_CURL_ARGS+=(-u "${ELASTICSEARCH_USERNAME:-}:${ELASTICSEARCH_PASSWORD:-}")
fi

ES_STATUS=$(curl "${ES_CURL_ARGS[@]}" "${ES_URL}/_cluster/health" 2>/dev/null || true)
if [[ "$ES_STATUS" == "200" || "$ES_STATUS" == "401" || "$ES_STATUS" == "403" ]]; then
  echo "  OK   Elasticsearch reachable (status ${ES_STATUS})"
else
  echo "  WARN Elasticsearch probe failed (status ${ES_STATUS:-000})"
fi

if curl -fsS "http://promaxgb10-6116:6333/collections" >/dev/null 2>&1; then
  echo "  OK   Qdrant /collections"
else
  echo "  WARN Qdrant /collections not reachable"
fi

echo "Connectivity checks completed."
