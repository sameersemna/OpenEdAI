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

func (s *PostgresStore) ListAPIKeys(ctx context.Context, limit int) ([]models.APIKey, error) {
	if limit <= 0 {
		limit = 50
	}

	const q = `
	SELECT id, name, key_hash, is_active, rate_limit_per_minute, expires_at, last_used_at, created_at, updated_at
	FROM api_keys
	ORDER BY created_at DESC
	LIMIT $1`

	rows, err := s.Pool.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.APIKey, 0, limit)
	for rows.Next() {
		var k models.APIKey
		if err := rows.Scan(
			&k.ID,
			&k.Name,
			&k.KeyHash,
			&k.IsActive,
			&k.RateLimitPerMinute,
			&k.ExpiresAt,
			&k.LastUsedAt,
			&k.CreatedAt,
			&k.UpdatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, k)
	}

	if rows.Err() != nil {
		return nil, rows.Err()
	}

	return items, nil
}

func (s *PostgresStore) GetUsageSummary(ctx context.Context, apiKeyID string, from time.Time, to time.Time) (models.UsageSummary, error) {
	const q = `
	SELECT
		COUNT(*) AS request_count,
		COALESCE(SUM(prompt_tokens), 0) AS prompt_tokens,
		COALESCE(SUM(completion_tokens), 0) AS completion_tokens,
		COALESCE(SUM(total_tokens), 0) AS total_tokens,
		COALESCE(SUM(CASE WHEN estimated_tokens THEN 1 ELSE 0 END), 0) AS estimated_count
	FROM usage_logs
	WHERE api_key_id = $1 AND created_at >= $2 AND created_at <= $3`

	var summary models.UsageSummary
	err := s.Pool.QueryRow(ctx, q, apiKeyID, from, to).Scan(
		&summary.RequestCount,
		&summary.PromptTokens,
		&summary.CompletionTokens,
		&summary.TotalTokens,
		&summary.EstimatedCount,
	)
	if err != nil {
		return models.UsageSummary{}, err
	}

	return summary, nil
}

func (s *PostgresStore) ListRecentUsage(ctx context.Context, apiKeyID string, limit int) ([]models.UsageLog, error) {
	if limit <= 0 {
		limit = 20
	}

	const q = `
	SELECT id, api_key_id, request_id, endpoint, model,
		prompt_tokens, completion_tokens, total_tokens,
		estimated_tokens, status_code, latency_ms, created_at
	FROM usage_logs
	WHERE api_key_id = $1
	ORDER BY created_at DESC
	LIMIT $2`

	rows, err := s.Pool.Query(ctx, q, apiKeyID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.UsageLog, 0, limit)
	for rows.Next() {
		var u models.UsageLog
		if err := rows.Scan(
			&u.ID,
			&u.APIKeyID,
			&u.RequestID,
			&u.Endpoint,
			&u.Model,
			&u.PromptTokens,
			&u.CompletionTokens,
			&u.TotalTokens,
			&u.EstimatedTokens,
			&u.StatusCode,
			&u.LatencyMS,
			&u.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, u)
	}

	if rows.Err() != nil {
		return nil, rows.Err()
	}

	return items, nil
}
