CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    rate_limit_per_minute INTEGER NOT NULL DEFAULT 120,
    expires_at TIMESTAMPTZ NULL,
    last_used_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key_id UUID NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    request_id TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    model TEXT,
    prompt_tokens INTEGER NOT NULL,
    completion_tokens INTEGER NOT NULL,
    total_tokens INTEGER NOT NULL,
    estimated_tokens BOOLEAN NOT NULL DEFAULT FALSE,
    status_code INTEGER NOT NULL,
    latency_ms BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_usage_logs_api_key_created_at ON usage_logs(api_key_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_logs_model_created_at ON usage_logs(model, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_logs_request_id ON usage_logs(request_id);
