# OpenEdAI Gateway (Go)

OpenAI-compatible API gateway for LAN-hosted LiteLLM/Ollama with:
- Bearer API key validation from PostgreSQL
- Per-key token usage logging to PostgreSQL
- Redis-backed rate limiting
- RAG endpoints over Elasticsearch + Qdrant

## LAN Topology
- Ollama: http://promaxgb10-6116:11434
- LiteLLM: http://latitude:11435
- PostgreSQL: latitude:5432
- Redis: latitude:6379
- Elasticsearch: https://latitude:9200 (security enabled)
- Qdrant: http://promaxgb10-6116:6333

## Quick Start
1. Copy `.env.example` to `.env` and fill credentials.
   - For secured Elasticsearch, set `ELASTICSEARCH_URL`, `ELASTICSEARCH_USERNAME`/`ELASTICSEARCH_PASSWORD` or `ELASTICSEARCH_API_KEY`, and `ELASTICSEARCH_INSECURE_SKIP_VERIFY=true` if using self-signed certs.
2. Run connectivity checks:
   - `bash scripts/setup.sh`
3. Apply schema:
   - `set -a && source .env && set +a`
   - `PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f migrations/001_init.sql`
4. Build and run:
   - `go mod tidy`
   - `go run ./cmd/gateway`

## Create API Key
- Generate a client key and hash:
  - `go run ./cmd/keygen --name your-key-name`
- Insert resulting hash into table `api_keys`.

## Service Endpoints
- `POST /v1/chat/completions` (proxy to LiteLLM)
- `POST /v1/completions` (proxy to LiteLLM)
- `POST /v1/rag/index`
- `POST /v1/rag/search`
- `GET /v1/management/api-keys` (masked key metadata)
- `GET /v1/management/usage` (per-key usage summary + recent logs)
- `GET /healthz`
- `GET /discovery`

`/healthz` now includes `litellm` and `elasticsearch` checks in addition to postgres and redis.

## Always-On Local Service (systemd)
- User-level service (no sudo):
   - `bash scripts/install_user_service.sh`
   - `systemctl --user status openedai-gateway.service`
   - Optional machine-boot autostart (one-time root action): `sudo loginctl enable-linger $USER`
- System-wide service (requires sudo):
  - `bash scripts/install_service.sh`
  - `systemctl status openedai-gateway.service`
