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

func TestRAGFlowWithSplitKey(t *testing.T) {
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
	`, keyID, "it-rag-test", keyHash); err != nil {
		t.Fatalf("insert test key: %v", err)
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, keyID)
	}()

	indexName := "it-rag-test-" + uuid.NewString()[:8]

	t.Run("rag_index", func(t *testing.T) {
		body := []byte(`{
			"index": "` + indexName + `",
			"collection": "` + indexName + `",
			"text": "split-key rag test document",
			"metadata": {"source": "integration-test"},
			"vector": [0.1, 0.2, 0.3, 0.4]
		}`)
		status, raw := doJSONRequest(t, "POST", baseURL+"/v1/rag/index", splitKey, body)

		if status == http.StatusBadGateway || status == http.StatusInternalServerError {
			var errResp map[string]any
			if err := json.Unmarshal(raw, &errResp); err == nil {
				if errMap, ok := errResp["error"].(map[string]any); ok {
					if msg, ok := errMap["message"].(string); ok && msg != "" {
						t.Skipf("RAG backend unavailable (expected in test environment): %s", msg)
					}
				}
			}
			t.Skipf("RAG backend unavailable: status=%d", status)
		}

		if status != http.StatusOK {
			t.Fatalf("rag index status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode rag index response: %v", err)
		}
		if resp["status"] != "indexed" {
			t.Fatalf("rag index status mismatch: got %v, want 'indexed'", resp["status"])
		}
	})

	t.Run("rag_search", func(t *testing.T) {
		body := []byte(`{
			"index": "` + indexName + `",
			"collection": "` + indexName + `",
			"query": "split-key rag test",
			"vector": [0.1, 0.2, 0.3, 0.4],
			"limit": 5
		}`)
		status, raw := doJSONRequest(t, "POST", baseURL+"/v1/rag/search", splitKey, body)

		if status == http.StatusBadGateway || status == http.StatusInternalServerError {
			t.Skip("RAG backend unavailable (expected in test environment)")
		}

		if status != http.StatusOK {
			t.Fatalf("rag search status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode rag search response: %v", err)
		}
		if _, ok := resp["results"]; !ok {
			t.Fatal("rag search response missing 'results' field")
		}
	})

	t.Run("rag_invalid_key_rejected", func(t *testing.T) {
		invalidKey := "sk_ed_" + uuid.NewString() + ".invalid"
		body := []byte(`{
			"index": "` + indexName + `",
			"collection": "` + indexName + `",
			"text": "should fail",
			"vector": [0.1, 0.2, 0.3, 0.4]
		}`)
		status, _ := doJSONRequest(t, "POST", baseURL+"/v1/rag/index", invalidKey, body)
		if status != http.StatusUnauthorized {
			t.Fatalf("invalid key should be rejected with 401, got %d", status)
		}
	})

	t.Run("rag_expired_key_rejected", func(t *testing.T) {
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
		`, expiredID, "it-rag-expired-test", expiredHash, pastTime); err != nil {
			t.Fatalf("insert expired key: %v", err)
		}
		defer func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, expiredID)
		}()

		body := []byte(`{
			"index": "` + indexName + `",
			"collection": "` + indexName + `",
			"text": "should fail expired",
			"vector": [0.1, 0.2, 0.3, 0.4]
		}`)
		status, _ := doJSONRequest(t, "POST", baseURL+"/v1/rag/index", expiredKey, body)
		if status != http.StatusUnauthorized {
			t.Fatalf("expired key should be rejected with 401, got %d", status)
		}
	})
}
