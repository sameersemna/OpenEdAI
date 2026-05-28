#!/usr/bin/env bash
set -euo pipefail

SERVICES=(
  "promaxgb10-6116:11434:Ollama"
  "latitude:4000:LiteLLM"
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
if curl -fsS "http://latitude:4000/health" >/dev/null 2>&1; then
  echo "  OK   LiteLLM /health"
else
  echo "  WARN LiteLLM /health not reachable (endpoint may differ)"
fi

if curl -fsS "http://latitude:9200" >/dev/null 2>&1; then
  echo "  OK   Elasticsearch root"
else
  echo "  WARN Elasticsearch root not reachable"
fi

if curl -fsS "http://promaxgb10-6116:6333/collections" >/dev/null 2>&1; then
  echo "  OK   Qdrant /collections"
else
  echo "  WARN Qdrant /collections not reachable"
fi

echo "Connectivity checks completed."
