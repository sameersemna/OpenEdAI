package storage

import (
	"context"
	"errors"
	"time"

	"openedai-gateway/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresStore struct {
	Pool *pgxpool.Pool
}

func NewPostgresStore(ctx context.Context, dsn string) (*PostgresStore, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return &PostgresStore{Pool: pool}, nil
}

func (s *PostgresStore) Close() {
	s.Pool.Close()
}

func (s *PostgresStore) GetActiveAPIKeyByHash(ctx context.Context, keyHash string) (*models.APIKey, error) {
	const q = `
	SELECT id, name, key_hash, is_active, rate_limit_per_minute, expires_at, last_used_at, created_at, updated_at
	FROM api_keys
	WHERE key_hash = $1 AND is_active = TRUE
	LIMIT 1`

	var k models.APIKey
	err := s.Pool.QueryRow(ctx, q, keyHash).Scan(
		&k.ID,
		&k.Name,
		&k.KeyHash,
		&k.IsActive,
		&k.RateLimitPerMinute,
		&k.ExpiresAt,
		&k.LastUsedAt,
		&k.CreatedAt,
		&k.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}

	if k.ExpiresAt != nil && k.ExpiresAt.Before(time.Now().UTC()) {
		return nil, errors.New("api key expired")
	}

	return &k, nil
}

func (s *PostgresStore) TouchAPIKeyLastUsed(ctx context.Context, apiKeyID string) error {
	const q = `UPDATE api_keys SET last_used_at = NOW(), updated_at = NOW() WHERE id = $1`
	_, err := s.Pool.Exec(ctx, q, apiKeyID)
	return err
}

func (s *PostgresStore) InsertUsageLog(ctx context.Context, log models.UsageLog) error {
	const q = `
	INSERT INTO usage_logs (
		id, api_key_id, request_id, endpoint, model,
		prompt_tokens, completion_tokens, total_tokens,
		estimated_tokens, status_code, latency_ms, created_at
	) VALUES (
		$1, $2, $3, $4, $5,
		$6, $7, $8,
		$9, $10, $11, NOW()
	)`

	_, err := s.Pool.Exec(ctx, q,
		log.ID,
		log.APIKeyID,
		log.RequestID,
		log.Endpoint,
		log.Model,
		log.PromptTokens,
		log.CompletionTokens,
		log.TotalTokens,
		log.EstimatedTokens,
		log.StatusCode,
		log.LatencyMS,
	)
	return err
}
