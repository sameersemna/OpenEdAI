-- Migration 002: API Key Performance Indexes
-- Optimizes lookups for split-key authentication and lifecycle operations

-- Index for active key lookup by ID (primary auth path)
CREATE INDEX IF NOT EXISTS idx_api_keys_active_id ON api_keys(is_active, id) WHERE is_active = TRUE;

-- Index for expired key cleanup and grace-period queries
CREATE INDEX IF NOT EXISTS idx_api_keys_expires_at ON api_keys(expires_at) WHERE expires_at IS NOT NULL;

-- Composite index for active keys with expiration checks
CREATE INDEX IF NOT EXISTS idx_api_keys_active_expires ON api_keys(is_active, expires_at) WHERE is_active = TRUE AND expires_at IS NOT NULL;

-- Index for name-based key management queries
CREATE INDEX IF NOT EXISTS idx_api_keys_name ON api_keys(name);
