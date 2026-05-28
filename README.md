# OpenEdAI Gateway (Go)

OpenAI-compatible API gateway for LAN-hosted LiteLLM/Ollama with:
- Bearer API key validation from PostgreSQL
- Per-key token usage logging to PostgreSQL
- Redis-backed rate limiting
- RAG endpoints over Elasticsearch + Qdrant

## LAN Topology
- Ollama: http://promaxgb10-6116:11434
- LiteLLM: http://latitude:4000
- PostgreSQL: latitude:5432
- Redis: latitude:6379
- Elasticsearch: http://latitude:9200
- Qdrant: http://promaxgb10-6116:6333

## Quick Start
1. Copy `.env.example` to `.env` and fill credentials.
2. Run connectivity checks:
   - `bash scripts/setup.sh`
3. Apply schema:
   - `psql "$DATABASE_URL" -f migrations/001_init.sql`
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
- `GET /healthz`
- `GET /discovery`

## Always-On Local Service (systemd)
- Build/install service:
  - `bash scripts/install_service.sh`
- Check status:
  - `systemctl status openedai-gateway.service`
