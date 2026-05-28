package integration

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"

	"openedai-gateway/internal/security"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestProxyFlowWithSplitKey(t *testing.T) {
	pepper := os.Getenv("API_KEY_HASH_PEPPER")
	if pepper == "" {
		t.Skip("API_KEY_HASH_PEPPER is required")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, postgresDSN())
	if err != nil {
		t.Fatalf("pgxpool new: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("pg ping: %v", err)
	}

	baseURL := gatewayBaseURL()
	if err := waitForGateway(baseURL, 10*time.Second); err != nil {
		t.Fatalf("gateway not ready: %v", err)
	}

	keyID := uuid.NewString()
	keySecret, err := security.GenerateSecretToken(32)
	if err != nil {
		t.Fatalf("generate key secret: %v", err)
	}
	keyHash := security.HashSecretToken(keySecret, pepper)
	splitKey := security.FormatSplitAPIKey(keyID, keySecret)

	if _, err := pool.Exec(ctx, `
		INSERT INTO api_keys(id, name, key_hash, is_active, rate_limit_per_minute)
		VALUES($1, $2, $3, TRUE, 180)
	`, keyID, "it-proxy-test", keyHash); err != nil {
		t.Fatalf("insert test key: %v", err)
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, keyID)
	}()

	t.Run("chat_completions", func(t *testing.T) {
		body := []byte(`{
			"model": "gpt-3.5-turbo",
			"messages": [{"role": "user", "content": "Hello"}],
			"max_tokens": 5
		}`)
		status, raw := doJSONRequest(t, "POST", baseURL+"/v1/chat/completions", splitKey, body)
		if status == http.StatusBadGateway {
			t.Skip("LiteLLM upstream unavailable (expected in test environment)")
		}
		if status == http.StatusBadRequest {
			var errResp map[string]any
			if err := json.Unmarshal(raw, &errResp); err == nil {
				if errMap, ok := errResp["error"].(map[string]any); ok {
					if msg, ok := errMap["message"].(string); ok && msg != "" {
						t.Logf("chat completions reached LiteLLM (model unavailable in test env): %s", msg)
						return
					}
				}
			}
		}
		if status != http.StatusOK && status != http.StatusBadRequest {
			t.Fatalf("chat completions status = %d, body = %s", status, string(raw))
		}
	})

	t.Run("completions", func(t *testing.T) {
		body := []byte(`{
			"model": "text-davinci-003",
			"prompt": "Hello",
			"max_tokens": 5
		}`)
		status, raw := doJSONRequest(t, "POST", baseURL+"/v1/completions", splitKey, body)
		if status == http.StatusBadGateway {
			t.Skip("LiteLLM upstream unavailable (expected in test environment)")
		}
		if status == http.StatusBadRequest {
			var errResp map[string]any
			if err := json.Unmarshal(raw, &errResp); err == nil {
				if errMap, ok := errResp["error"].(map[string]any); ok {
					if msg, ok := errMap["message"].(string); ok && msg != "" {
						t.Logf("completions reached LiteLLM (model unavailable in test env): %s", msg)
						return
					}
				}
			}
		}
		if status != http.StatusOK && status != http.StatusBadRequest {
			t.Fatalf("completions status = %d, body = %s", status, string(raw))
		}
	})

	t.Run("usage_summary", func(t *testing.T) {
		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage", splitKey, nil)
		if status != http.StatusOK {
			t.Fatalf("usage status = %d, body = %s", status, string(raw))
		}
		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode usage response: %v", err)
		}
		if resp["api_key_id"] != keyID {
			t.Fatalf("usage api_key_id mismatch: got %v, want %s", resp["api_key_id"], keyID)
		}
		if summary, ok := resp["summary"].(map[string]any); ok {
			if _, hasCount := summary["request_count"]; !hasCount {
				t.Fatal("usage summary missing request_count")
			}
		} else {
			t.Fatal("usage response missing summary")
		}
	})

	t.Run("invalid_key_rejected", func(t *testing.T) {
		invalidKey := "sk_ed_" + uuid.NewString() + ".invalid"
		status, _ := doJSONRequest(t, "GET", baseURL+"/v1/management/usage", invalidKey, nil)
		if status != http.StatusUnauthorized {
			t.Fatalf("invalid key should be rejected with 401, got %d", status)
		}
	})

	t.Run("expired_key_rejected", func(t *testing.T) {
		expiredID := uuid.NewString()
		expiredSecret, err := security.GenerateSecretToken(32)
		if err != nil {
			t.Fatalf("generate expired key secret: %v", err)
		}
		expiredHash := security.HashSecretToken(expiredSecret, pepper)
		expiredKey := security.FormatSplitAPIKey(expiredID, expiredSecret)

		pastTime := time.Now().UTC().Add(-1 * time.Hour)
		if _, err := pool.Exec(ctx, `
			INSERT INTO api_keys(id, name, key_hash, is_active, rate_limit_per_minute, expires_at)
			VALUES($1, $2, $3, TRUE, 180, $4)
		`, expiredID, "it-expired-test", expiredHash, pastTime); err != nil {
			t.Fatalf("insert expired key: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, expiredID)
		}()

		status, _ := doJSONRequest(t, "GET", baseURL+"/v1/management/usage", expiredKey, nil)
		if status != http.StatusUnauthorized {
			t.Fatalf("expired key should be rejected with 401, got %d", status)
		}
	})
}
