package integration

import (
	"context"
	"testing"
	"time"

	"openedai-gateway/internal/security"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func createTempSplitKey(t *testing.T, ctx context.Context, pool *pgxpool.Pool, pepper string, name string) (string, string) {
	t.Helper()

	return createTempSplitKeyWithOptions(t, ctx, pool, pepper, name, false, 180)
}

func createTempSplitKeyWithOptions(t *testing.T, ctx context.Context, pool *pgxpool.Pool, pepper string, name string, isAdmin bool, rateLimitPerMinute int) (string, string) {
	t.Helper()

	return createTempSplitKeyWithAdvancedOptions(t, ctx, pool, pepper, name, isAdmin, rateLimitPerMinute, nil)
}

func createTempSplitKeyWithAdvancedOptions(t *testing.T, ctx context.Context, pool *pgxpool.Pool, pepper string, name string, isAdmin bool, rateLimitPerMinute int, expiresAt *time.Time) (string, string) {
	t.Helper()

	keyID := uuid.NewString()
	keySecret, err := security.GenerateSecretToken(32)
	if err != nil {
		t.Fatalf("generate temp split key secret (%s): %v", name, err)
	}
	keyHash := security.HashSecretToken(keySecret, pepper)
	formattedKey := security.FormatSplitAPIKey(keyID, keySecret)

	if expiresAt == nil {
		if _, err := pool.Exec(ctx, `
			INSERT INTO api_keys(id, name, key_hash, is_active, is_admin, rate_limit_per_minute)
			VALUES($1, $2, $3, TRUE, $4, $5)
		`, keyID, name, keyHash, isAdmin, rateLimitPerMinute); err != nil {
			t.Fatalf("insert temp split key (%s): %v", name, err)
		}
	} else {
		if _, err := pool.Exec(ctx, `
			INSERT INTO api_keys(id, name, key_hash, is_active, is_admin, rate_limit_per_minute, expires_at)
			VALUES($1, $2, $3, TRUE, $4, $5, $6)
		`, keyID, name, keyHash, isAdmin, rateLimitPerMinute, *expiresAt); err != nil {
			t.Fatalf("insert temp split key with expiry (%s): %v", name, err)
		}
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM usage_logs WHERE api_key_id = $1`, keyID)
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, keyID)
	})

	return keyID, formattedKey
}

func seedUsageLogs(t *testing.T, ctx context.Context, pool *pgxpool.Pool, apiKeyID string, count int, requestPrefix string, promptTokens int, completionTokens int, statusCode int, latencyMS int) {
	t.Helper()

	for i := 0; i < count; i++ {
		if _, err := pool.Exec(ctx, `
			INSERT INTO usage_logs(id, api_key_id, request_id, endpoint, model, prompt_tokens, completion_tokens, total_tokens, estimated_tokens, status_code, latency_ms)
			VALUES($1, $2, $3, $4, $5, $6, $7, $8, FALSE, $9, $10)
		`, uuid.NewString(), apiKeyID, requestPrefix+uuid.NewString(), "/v1/chat/completions", "gpt-3.5-turbo", promptTokens, completionTokens, promptTokens+completionTokens, statusCode, latencyMS); err != nil {
			t.Fatalf("seed usage logs (%s): %v", requestPrefix, err)
		}
	}
}

func seedUsageLog(t *testing.T, ctx context.Context, pool *pgxpool.Pool, apiKeyID string, requestID string, promptTokens int, completionTokens int, statusCode int, latencyMS int) {
	t.Helper()

	if _, err := pool.Exec(ctx, `
		INSERT INTO usage_logs(id, api_key_id, request_id, endpoint, model, prompt_tokens, completion_tokens, total_tokens, estimated_tokens, status_code, latency_ms)
		VALUES($1, $2, $3, $4, $5, $6, $7, $8, FALSE, $9, $10)
	`, uuid.NewString(), apiKeyID, requestID, "/v1/chat/completions", "gpt-3.5-turbo", promptTokens, completionTokens, promptTokens+completionTokens, statusCode, latencyMS); err != nil {
		t.Fatalf("seed usage log (%s): %v", requestID, err)
	}
}
