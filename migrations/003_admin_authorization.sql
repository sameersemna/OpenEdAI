-- Migration 003: Admin Authorization
-- Adds is_admin flag to distinguish admin keys from regular API keys

-- Add is_admin column with default FALSE
ALTER TABLE api_keys ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

-- Create index for efficient admin key filtering
CREATE INDEX IF NOT EXISTS idx_api_keys_admin ON api_keys(is_admin) WHERE is_admin = TRUE;
