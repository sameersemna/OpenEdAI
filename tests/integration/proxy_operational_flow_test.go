package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"openedai-gateway/internal/api"
	"openedai-gateway/internal/config"
	"openedai-gateway/internal/security"
	"openedai-gateway/internal/services"
	"openedai-gateway/internal/storage"

	"github.com/alicebob/miniredis/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

func TestProxyOperationalFlow(t *testing.T) {
	pepper := os.Getenv("API_KEY_HASH_PEPPER")
	if pepper == "" {
		t.Skip("API_KEY_HASH_PEPPER is required")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, postgresDSN())
	if err != nil {
		t.Fatalf("pgxpool new: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("pg ping: %v", err)
	}

	store, err := storage.NewPostgresStore(ctx, postgresDSN())
	if err != nil {
		t.Fatalf("new postgres store: %v", err)
	}
	defer store.Close()

	miniRedis, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer miniRedis.Close()

	redisClient := redis.NewClient(&redis.Options{Addr: miniRedis.Addr()})
	defer redisClient.Close()

	if err := redisClient.Ping(ctx).Err(); err != nil {
		t.Fatalf("redis ping: %v", err)
	}

	const (
		expectedPromptTokens     = 13
		expectedCompletionTokens = 8
		expectedTotalTokens      = 21
		expectedModel            = "gpt-3.5-turbo"
	)

	var (
		mockMu             sync.Mutex
		mockCallCount      int
		lastMockPayload    map[string]any
		lastUpstreamReqID  string
		mockResponseStatus = http.StatusOK
		mockIncludeUsage   = true
	)

	liteLLMMock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/health", "/v1/models":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"ok":true}`))
			return
		case "/v1/chat/completions":
		default:
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"message":"not found"}}`))
			return
		}

		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()

		parsed := map[string]any{}
		_ = json.Unmarshal(body, &parsed)

		mockMu.Lock()
		mockCallCount++
		lastMockPayload = parsed
		lastUpstreamReqID = r.Header.Get("X-Request-ID")
		responseStatus := mockResponseStatus
		includeUsage := mockIncludeUsage
		mockMu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(responseStatus)
		if responseStatus < 200 || responseStatus >= 300 {
			_, _ = w.Write([]byte(`{"error":{"message":"mocked upstream error"}}`))
			return
		}
		if includeUsage {
			_, _ = w.Write([]byte(`{
				"id":"chatcmpl-mock",
				"object":"chat.completion",
				"created":1717000000,
				"model":"gpt-3.5-turbo",
				"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"mocked response"}}],
				"usage":{"prompt_tokens":13,"completion_tokens":8,"total_tokens":21}
			}`))
			return
		}
		_, _ = w.Write([]byte(`{
			"id":"chatcmpl-mock-estimate",
			"object":"chat.completion",
			"created":1717000001,
			"model":"gpt-3.5-turbo",
			"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"mocked response without usage"}}]
		}`))
	}))
	defer liteLLMMock.Close()

	cfg := config.Settings{
		LiteLLMBaseURL:            liteLLMMock.URL,
		APIKeyHashPepper:          pepper,
		RequestTimeoutSeconds:     5,
		DefaultRateLimitPerMinute: 120,
		RedisKeyPrefix:            "it-operational-" + uuid.NewString(),
	}

	gateway := httptest.NewServer((&api.Server{
		Cfg:         cfg,
		Store:       store,
		RedisClient: redisClient,
		LiteLLM:     services.NewLiteLLMClient(cfg.LiteLLMBaseURL, cfg.RequestTimeoutSeconds),
	}).Router())
	defer gateway.Close()

	_, bootstrapKey := createTempSplitKeyWithOptions(t, ctx, pool, pepper, "it-operational-bootstrap", true, 180)

	createdKeyID := ""
	createdKeyValue := ""
	extraKeyIDs := make([]string, 0)
	t.Cleanup(func() {
		for _, id := range extraKeyIDs {
			_, _ = pool.Exec(context.Background(), `DELETE FROM usage_logs WHERE api_key_id = $1`, id)
			_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, id)
		}
		if createdKeyID != "" {
			_, _ = pool.Exec(context.Background(), `DELETE FROM usage_logs WHERE api_key_id = $1`, createdKeyID)
			_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, createdKeyID)
		}
	})

	t.Run("1_setup_dependencies", func(t *testing.T) {
		if err := pool.Ping(ctx); err != nil {
			t.Fatalf("postgres unavailable: %v", err)
		}
		if err := redisClient.Ping(ctx).Err(); err != nil {
			t.Fatalf("redis unavailable: %v", err)
		}
		resp, err := http.Get(liteLLMMock.URL + "/health")
		if err != nil {
			t.Fatalf("mock litellm unavailable: %v", err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("mock litellm health status = %d", resp.StatusCode)
		}
	})

	t.Run("2_auth_creation", func(t *testing.T) {
		createBody := []byte(`{"name":"it-operational-created","rate_limit_per_minute":120}`)
		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/management/api-keys", bootstrapKey, createBody)
		if status != http.StatusCreated {
			t.Fatalf("create key status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode create key response: %v", err)
		}

		id, _ := resp["id"].(string)
		plaintext, _ := resp["api_key"].(string)
		if id == "" || plaintext == "" {
			t.Fatalf("create key response missing id or api_key: %s", string(raw))
		}

		parsedID, parsedSecret, err := security.ParseSplitAPIKey(plaintext)
		if err != nil {
			t.Fatalf("created plaintext key format invalid: %v", err)
		}
		if parsedID != id {
			t.Fatalf("created plaintext key id = %s, want %s", parsedID, id)
		}
		if parsedSecret == "" {
			t.Fatal("created plaintext key secret is empty")
		}

		createdKeyID = id
		createdKeyValue = plaintext
	})

	t.Run("3_negative_auth_path", func(t *testing.T) {
		invalid := "sk_ed_" + uuid.NewString() + ".invalid"
		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", invalid, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"hello"}]
		}`))
		if status != http.StatusUnauthorized {
			t.Fatalf("invalid token status = %d, body = %s", status, string(raw))
		}
	})

	t.Run("4_positive_proxy_path", func(t *testing.T) {
		if createdKeyValue == "" {
			t.Fatal("created key must be set by auth creation subtest")
		}

		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"Say hi"}],
			"max_tokens":10
		}`))
		if status != http.StatusOK {
			t.Fatalf("proxy status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode proxy response: %v", err)
		}
		if model, _ := resp["model"].(string); model != expectedModel {
			t.Fatalf("proxy model = %q, want %q", model, expectedModel)
		}
		usage, _ := resp["usage"].(map[string]any)
		if usage == nil {
			t.Fatalf("proxy response missing usage: %s", string(raw))
		}
		if int(usage["prompt_tokens"].(float64)) != expectedPromptTokens || int(usage["completion_tokens"].(float64)) != expectedCompletionTokens || int(usage["total_tokens"].(float64)) != expectedTotalTokens {
			t.Fatalf("proxy usage mismatch: %+v", usage)
		}

		mockMu.Lock()
		defer mockMu.Unlock()
		if mockCallCount != 1 {
			t.Fatalf("mock call count = %d, want 1", mockCallCount)
		}
		if gotModel, _ := lastMockPayload["model"].(string); gotModel != expectedModel {
			t.Fatalf("forwarded model = %q, want %q", gotModel, expectedModel)
		}
	})

	t.Run("5_usage_accounting_assertion", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		usageResp := waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage", createdKeyValue, 1, 5*time.Second)
		if usageResp["api_key_id"] != createdKeyID {
			t.Fatalf("usage api_key_id = %v, want %s", usageResp["api_key_id"], createdKeyID)
		}

		summary, _ := usageResp["summary"].(map[string]any)
		if summary == nil {
			t.Fatalf("usage response missing summary")
		}
		if int(summary["request_count"].(float64)) != 1 {
			t.Fatalf("summary request_count = %v, want 1", summary["request_count"])
		}
		if int(summary["prompt_tokens"].(float64)) != expectedPromptTokens || int(summary["completion_tokens"].(float64)) != expectedCompletionTokens || int(summary["total_tokens"].(float64)) != expectedTotalTokens {
			t.Fatalf("summary token totals mismatch: %+v", summary)
		}

		var (
			apiKeyID         string
			endpoint         string
			model            string
			promptTokens     int
			completionTokens int
			totalTokens      int
			estimatedTokens  bool
			statusCode       int
		)
		err := pool.QueryRow(ctx, `
			SELECT api_key_id, endpoint, model, prompt_tokens, completion_tokens, total_tokens, estimated_tokens, status_code
			FROM usage_logs
			WHERE api_key_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, createdKeyID).Scan(
			&apiKeyID,
			&endpoint,
			&model,
			&promptTokens,
			&completionTokens,
			&totalTokens,
			&estimatedTokens,
			&statusCode,
		)
		if err != nil {
			t.Fatalf("query usage_logs: %v", err)
		}

		if apiKeyID != createdKeyID {
			t.Fatalf("usage log api_key_id = %s, want %s", apiKeyID, createdKeyID)
		}
		if endpoint != "/v1/chat/completions" {
			t.Fatalf("usage log endpoint = %q, want /v1/chat/completions", endpoint)
		}
		if model != expectedModel {
			t.Fatalf("usage log model = %q, want %q", model, expectedModel)
		}
		if promptTokens != expectedPromptTokens || completionTokens != expectedCompletionTokens || totalTokens != expectedTotalTokens {
			t.Fatalf("usage log token totals mismatch: prompt=%d completion=%d total=%d", promptTokens, completionTokens, totalTokens)
		}
		if estimatedTokens {
			t.Fatal("usage log should not be estimated when upstream usage is present")
		}
		if statusCode != http.StatusOK {
			t.Fatalf("usage log status_code = %d, want 200", statusCode)
		}
	})

	t.Run("6_usage_accumulates_across_requests", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"Second request"}],
			"max_tokens":10
		}`))
		if status != http.StatusOK {
			t.Fatalf("second proxy status = %d, body = %s", status, string(raw))
		}

		usageResp := waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage", createdKeyValue, 2, 5*time.Second)

		summary, _ := usageResp["summary"].(map[string]any)
		if summary == nil {
			t.Fatalf("usage response missing summary after second request: %s", string(raw))
		}
		if int(summary["request_count"].(float64)) != 2 {
			t.Fatalf("summary request_count = %v, want 2", summary["request_count"])
		}
		if int(summary["prompt_tokens"].(float64)) != expectedPromptTokens*2 || int(summary["completion_tokens"].(float64)) != expectedCompletionTokens*2 || int(summary["total_tokens"].(float64)) != expectedTotalTokens*2 {
			t.Fatalf("summary token totals after second request mismatch: %+v", summary)
		}

		mockMu.Lock()
		if mockCallCount != 2 {
			mockMu.Unlock()
			t.Fatalf("mock call count after second request = %d, want 2", mockCallCount)
		}
		mockMu.Unlock()

		var usageRows int
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, createdKeyID).Scan(&usageRows); err != nil {
			t.Fatalf("count usage_logs rows: %v", err)
		}
		if usageRows != 2 {
			t.Fatalf("usage_logs row count = %d, want 2", usageRows)
		}
	})

	t.Run("7_request_id_propagation", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		mockMu.Lock()
		mockResponseStatus = http.StatusOK
		mockIncludeUsage = true
		mockMu.Unlock()

		customReqID := "req-it-custom-123"
		status, raw, headers := doJSONRequestWithHeaders(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"request id pass-through"}]
		}`), map[string]string{"X-Request-ID": customReqID})
		if status != http.StatusOK {
			t.Fatalf("custom request-id status = %d, body = %s", status, string(raw))
		}
		if got := headers.Get("X-Request-ID"); got != customReqID {
			t.Fatalf("response X-Request-ID = %q, want %q", got, customReqID)
		}

		mockMu.Lock()
		if lastUpstreamReqID != customReqID {
			mockMu.Unlock()
			t.Fatalf("upstream X-Request-ID = %q, want %q", lastUpstreamReqID, customReqID)
		}
		mockMu.Unlock()

		var persistedReqID string
		err := pool.QueryRow(ctx, `
			SELECT request_id FROM usage_logs
			WHERE api_key_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, createdKeyID).Scan(&persistedReqID)
		if err != nil {
			t.Fatalf("query usage_logs request_id: %v", err)
		}
		if persistedReqID != customReqID {
			t.Fatalf("persisted request_id = %q, want %q", persistedReqID, customReqID)
		}

		status, raw, headers = doJSONRequestWithHeaders(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"request id auto-gen"}]
		}`), nil)
		if status != http.StatusOK {
			t.Fatalf("auto request-id status = %d, body = %s", status, string(raw))
		}
		autoID := headers.Get("X-Request-ID")
		if autoID == "" {
			t.Fatal("response missing generated X-Request-ID")
		}

		err = pool.QueryRow(ctx, `
			SELECT request_id FROM usage_logs
			WHERE api_key_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, createdKeyID).Scan(&persistedReqID)
		if err != nil {
			t.Fatalf("query generated request_id from usage_logs: %v", err)
		}
		if persistedReqID != autoID {
			t.Fatalf("persisted generated request_id = %q, want %q", persistedReqID, autoID)
		}
	})

	t.Run("8_non_2xx_upstream_does_not_write_usage", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		var (
			beforeCount     int
			beforeEstimated int
		)
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, createdKeyID).Scan(&beforeCount); err != nil {
			t.Fatalf("count usage_logs before non-2xx request: %v", err)
		}
		if err := pool.QueryRow(ctx, `
			SELECT COALESCE(SUM(CASE WHEN estimated_tokens THEN 1 ELSE 0 END), 0)
			FROM usage_logs
			WHERE api_key_id = $1
		`, createdKeyID).Scan(&beforeEstimated); err != nil {
			t.Fatalf("count estimated usage rows before non-2xx request: %v", err)
		}

		mockMu.Lock()
		mockResponseStatus = http.StatusBadRequest
		mockIncludeUsage = true
		mockMu.Unlock()

		customReqID := "req-it-non-2xx"
		status, raw, headers := doJSONRequestWithHeaders(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"should not be accounted"}]
		}`), map[string]string{"X-Request-ID": customReqID})
		if status != http.StatusBadRequest {
			t.Fatalf("non-2xx passthrough status = %d, body = %s", status, string(raw))
		}
		if got := headers.Get("X-Request-ID"); got != customReqID {
			t.Fatalf("non-2xx response X-Request-ID = %q, want %q", got, customReqID)
		}

		var afterCount int
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, createdKeyID).Scan(&afterCount); err != nil {
			t.Fatalf("count usage_logs after non-2xx request: %v", err)
		}
		if afterCount != beforeCount {
			t.Fatalf("usage log count changed on non-2xx response: before=%d after=%d", beforeCount, afterCount)
		}

		var afterEstimated int
		if err := pool.QueryRow(ctx, `
			SELECT COALESCE(SUM(CASE WHEN estimated_tokens THEN 1 ELSE 0 END), 0)
			FROM usage_logs
			WHERE api_key_id = $1
		`, createdKeyID).Scan(&afterEstimated); err != nil {
			t.Fatalf("count estimated usage rows after non-2xx request: %v", err)
		}
		if afterEstimated != beforeEstimated {
			t.Fatalf("estimated row count changed on non-2xx: before=%d after=%d", beforeEstimated, afterEstimated)
		}

		mockMu.Lock()
		mockResponseStatus = http.StatusOK
		mockIncludeUsage = true
		mockMu.Unlock()
	})

	t.Run("9_estimated_tokens_fallback_without_usage", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		var beforeCount int
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, createdKeyID).Scan(&beforeCount); err != nil {
			t.Fatalf("count usage rows before fallback request: %v", err)
		}

		mockMu.Lock()
		mockResponseStatus = http.StatusOK
		mockIncludeUsage = false
		mockMu.Unlock()

		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"estimate these tokens for fallback behavior"}],
			"max_tokens":12
		}`))
		if status != http.StatusOK {
			t.Fatalf("estimated fallback status = %d, body = %s", status, string(raw))
		}

		var (
			estimated bool
			total     int
		)
		err := pool.QueryRow(ctx, `
			SELECT estimated_tokens, total_tokens
			FROM usage_logs
			WHERE api_key_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, createdKeyID).Scan(&estimated, &total)
		if err != nil {
			t.Fatalf("query latest usage fallback row: %v", err)
		}
		if !estimated {
			t.Fatal("expected estimated_tokens=true when upstream omits usage")
		}
		if total <= 0 {
			t.Fatalf("expected estimated total_tokens > 0, got %d", total)
		}

		_ = waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage", createdKeyValue, beforeCount+1, 5*time.Second)

		mockMu.Lock()
		mockIncludeUsage = true
		mockMu.Unlock()
	})

	t.Run("10_concurrent_usage_accounting", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		status, raw := doJSONRequest(t, "GET", gateway.URL+"/v1/management/usage", createdKeyValue, nil)
		if status != http.StatusOK {
			t.Fatalf("usage status before concurrent requests = %d, body = %s", status, string(raw))
		}

		var beforeUsageResp map[string]any
		if err := json.Unmarshal(raw, &beforeUsageResp); err != nil {
			t.Fatalf("decode usage summary before concurrent requests: %v", err)
		}
		beforeSummary, _ := beforeUsageResp["summary"].(map[string]any)
		if beforeSummary == nil {
			t.Fatalf("missing summary before concurrent requests: %s", string(raw))
		}
		beforeRequestCount := int(beforeSummary["request_count"].(float64))
		beforePromptTokens := int(beforeSummary["prompt_tokens"].(float64))
		beforeCompletionTokens := int(beforeSummary["completion_tokens"].(float64))
		beforeTotalTokens := int(beforeSummary["total_tokens"].(float64))

		mockMu.Lock()
		beforeCallCount := mockCallCount
		mockResponseStatus = http.StatusOK
		mockIncludeUsage = true
		mockMu.Unlock()

		const concurrentRequests = 6
		errCh := make(chan error, concurrentRequests)
		var wg sync.WaitGroup

		for i := 0; i < concurrentRequests; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				reqID := "req-it-concurrent-" + uuid.NewString()
				status, raw, headers := doJSONRequestWithHeaders(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
					"model":"gpt-3.5-turbo",
					"messages":[{"role":"user","content":"parallel request"}],
					"max_tokens":6
				}`), map[string]string{"X-Request-ID": reqID})
				if status != http.StatusOK {
					errCh <- errStringf("concurrent request %d status=%d body=%s", i, status, string(raw))
					return
				}
				if got := headers.Get("X-Request-ID"); got != reqID {
					errCh <- errStringf("concurrent request %d response request id=%q want=%q", i, got, reqID)
					return
				}
				errCh <- nil
			}(i)
		}

		wg.Wait()
		close(errCh)
		for err := range errCh {
			if err != nil {
				t.Fatal(err)
			}
		}

		expectedRequestCount := beforeRequestCount + concurrentRequests
		usageResp := waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage", createdKeyValue, expectedRequestCount, 5*time.Second)
		summary, _ := usageResp["summary"].(map[string]any)
		if summary == nil {
			t.Fatalf("missing summary after concurrent requests")
		}
		if int(summary["request_count"].(float64)) != expectedRequestCount {
			t.Fatalf("summary request_count after concurrent requests = %v, want %d", summary["request_count"], expectedRequestCount)
		}
		expectedPromptTotal := beforePromptTokens + expectedPromptTokens*concurrentRequests
		expectedCompletionTotal := beforeCompletionTokens + expectedCompletionTokens*concurrentRequests
		expectedTokenTotal := beforeTotalTokens + expectedTotalTokens*concurrentRequests
		if int(summary["prompt_tokens"].(float64)) != expectedPromptTotal || int(summary["completion_tokens"].(float64)) != expectedCompletionTotal || int(summary["total_tokens"].(float64)) != expectedTokenTotal {
			t.Fatalf("summary token totals after concurrent requests mismatch: got prompt=%v completion=%v total=%v want prompt=%d completion=%d total=%d", summary["prompt_tokens"], summary["completion_tokens"], summary["total_tokens"], expectedPromptTotal, expectedCompletionTotal, expectedTokenTotal)
		}

		mockMu.Lock()
		if mockCallCount != beforeCallCount+concurrentRequests {
			got := mockCallCount
			mockMu.Unlock()
			t.Fatalf("mock call count after concurrent requests = %d, want %d", got, beforeCallCount+concurrentRequests)
		}
		mockMu.Unlock()
	})

	t.Run("11_recent_usage_shape_and_order", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		status, raw := doJSONRequest(t, "GET", gateway.URL+"/v1/management/usage", createdKeyValue, nil)
		if status != http.StatusOK {
			t.Fatalf("usage status for recent assertions = %d, body = %s", status, string(raw))
		}

		usageResp := decodeJSONObject(t, raw, "usage response for recent assertions")
		recent, _ := usageResp["recent"].([]any)
		if len(recent) < 2 {
			t.Fatalf("expected at least 2 recent items, got %d", len(recent))
		}

		first, _ := recent[0].(map[string]any)
		second, _ := recent[1].(map[string]any)
		if first == nil || second == nil {
			t.Fatalf("recent items should be objects: %s", string(raw))
		}
		if first["RequestID"] == nil || first["CreatedAt"] == nil || first["Endpoint"] == nil || first["StatusCode"] == nil {
			t.Fatalf("recent[0] missing required fields: %+v", first)
		}
		if first["Endpoint"] != "/v1/chat/completions" {
			t.Fatalf("recent[0] endpoint = %v, want /v1/chat/completions", first["Endpoint"])
		}

		firstCreated, _ := first["CreatedAt"].(string)
		secondCreated, _ := second["CreatedAt"].(string)
		if firstCreated == "" || secondCreated == "" {
			t.Fatalf("recent created_at fields should be non-empty: first=%q second=%q", firstCreated, secondCreated)
		}

		var latestReqID string
		err := pool.QueryRow(ctx, `
			SELECT request_id FROM usage_logs
			WHERE api_key_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, createdKeyID).Scan(&latestReqID)
		if err != nil {
			t.Fatalf("query latest request_id for recent assertions: %v", err)
		}
		if got, _ := first["RequestID"].(string); got != latestReqID {
			t.Fatalf("recent[0].RequestID = %q, want latest %q", got, latestReqID)
		}
	})

	t.Run("12_recent_token_integrity", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		status, raw := doJSONRequest(t, "GET", gateway.URL+"/v1/management/usage", createdKeyValue, nil)
		if status != http.StatusOK {
			t.Fatalf("usage status for token integrity = %d, body = %s", status, string(raw))
		}

		usageResp := decodeJSONObject(t, raw, "usage response for token integrity")
		recent, _ := usageResp["recent"].([]any)
		if len(recent) == 0 {
			t.Fatalf("recent usage should not be empty: %s", string(raw))
		}

		limit := len(recent)
		if limit > 5 {
			limit = 5
		}
		for i := 0; i < limit; i++ {
			item, _ := recent[i].(map[string]any)
			if item == nil {
				t.Fatalf("recent[%d] is not an object", i)
			}

			estimated, _ := item["EstimatedTokens"].(bool)
			prompt := int(item["PromptTokens"].(float64))
			completion := int(item["CompletionTokens"].(float64))
			total := int(item["TotalTokens"].(float64))

			if !estimated && total != prompt+completion {
				t.Fatalf("recent[%d] token mismatch: total=%d prompt=%d completion=%d", i, total, prompt, completion)
			}
		}

		var brokenRows int
		if err := pool.QueryRow(ctx, `
			SELECT COUNT(*)
			FROM usage_logs
			WHERE api_key_id = $1
			  AND estimated_tokens = FALSE
			  AND total_tokens <> (prompt_tokens + completion_tokens)
		`, createdKeyID).Scan(&brokenRows); err != nil {
			t.Fatalf("query non-estimated token integrity rows: %v", err)
		}
		if brokenRows != 0 {
			t.Fatalf("found %d non-estimated rows with invalid token totals", brokenRows)
		}
	})

	t.Run("15_recent_contains_estimated_and_non_estimated", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		status, raw := doJSONRequest(t, "GET", gateway.URL+"/v1/management/usage", createdKeyValue, nil)
		if status != http.StatusOK {
			t.Fatalf("usage status for estimated/non-estimated recent assertion = %d, body = %s", status, string(raw))
		}

		usageResp := decodeJSONObject(t, raw, "usage response for estimated/non-estimated recent assertion")
		recent, _ := usageResp["recent"].([]any)
		if len(recent) == 0 {
			t.Fatal("recent usage should not be empty")
		}

		seenEstimated := false
		seenNonEstimated := false
		for i, rawItem := range recent {
			item, _ := rawItem.(map[string]any)
			if item == nil {
				t.Fatalf("recent[%d] is not an object", i)
			}
			estimated, ok := item["EstimatedTokens"].(bool)
			if !ok {
				t.Fatalf("recent[%d] missing EstimatedTokens bool field: %+v", i, item)
			}
			if estimated {
				seenEstimated = true
			} else {
				seenNonEstimated = true
			}
		}

		if !seenEstimated || !seenNonEstimated {
			t.Fatalf("recent usage should include both estimated and non-estimated entries: estimated=%t non_estimated=%t", seenEstimated, seenNonEstimated)
		}
	})

	t.Run("13_mock_path_latency_budget", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		const latencyBudget = 500 * time.Millisecond

		mockMu.Lock()
		mockResponseStatus = http.StatusOK
		mockIncludeUsage = true
		mockMu.Unlock()

		start := time.Now()
		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"latency budget check"}],
			"max_tokens":8
		}`))
		elapsed := time.Since(start)

		if status != http.StatusOK {
			t.Fatalf("latency budget request status = %d, body = %s", status, string(raw))
		}
		if elapsed > latencyBudget {
			t.Fatalf("latency budget exceeded: elapsed=%s budget=%s", elapsed, latencyBudget)
		}

		var latestLatencyMS int64
		if err := pool.QueryRow(ctx, `
			SELECT latency_ms
			FROM usage_logs
			WHERE api_key_id = $1
			ORDER BY created_at DESC
			LIMIT 1
		`, createdKeyID).Scan(&latestLatencyMS); err != nil {
			t.Fatalf("query latest latency_ms: %v", err)
		}
		if latestLatencyMS > int64(latencyBudget/time.Millisecond) {
			t.Fatalf("persisted latency_ms exceeded budget: got=%d budget_ms=%d", latestLatencyMS, latencyBudget/time.Millisecond)
		}
	})

	t.Run("14_rate_limit_rejection_not_accounted", func(t *testing.T) {
		createBody := []byte(`{"name":"it-rate-limit","rate_limit_per_minute":2}`)
		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/management/api-keys", bootstrapKey, createBody)
		if status != http.StatusCreated {
			t.Fatalf("create rate-limit key status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		resp = decodeJSONObject(t, raw, "rate-limit key create response")
		rlKeyID, _ := resp["id"].(string)
		rlKeyValue, _ := resp["api_key"].(string)
		if rlKeyID == "" || rlKeyValue == "" {
			t.Fatalf("rate-limit key response missing fields: %s", string(raw))
		}
		extraKeyIDs = append(extraKeyIDs, rlKeyID)

		var beforeCount int
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, rlKeyID).Scan(&beforeCount); err != nil {
			t.Fatalf("count rl usage before requests: %v", err)
		}

		for i := 1; i <= 2; i++ {
			status, raw = doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", rlKeyValue, []byte(`{
				"model":"gpt-3.5-turbo",
				"messages":[{"role":"user","content":"rate limit warmup"}],
				"max_tokens":4
			}`))
			if status != http.StatusOK {
				t.Fatalf("rate-limit warmup request %d status = %d, body = %s", i, status, string(raw))
			}
		}

		status, raw = doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", rlKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"rate limit should trigger"}],
			"max_tokens":4
		}`))
		if status != http.StatusTooManyRequests {
			t.Fatalf("expected 429 on rate-limit request, got status=%d body=%s", status, string(raw))
		}

		var afterCount int
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, rlKeyID).Scan(&afterCount); err != nil {
			t.Fatalf("count rl usage after requests: %v", err)
		}
		if afterCount != beforeCount+2 {
			t.Fatalf("rate-limit accounting mismatch: before=%d after=%d want=%d", beforeCount, afterCount, beforeCount+2)
		}

		usageResp := waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage?api_key_id="+rlKeyID, bootstrapKey, 2, 5*time.Second)
		summary, _ := usageResp["summary"].(map[string]any)
		if summary == nil {
			t.Fatalf("missing rl summary")
		}
		if int(summary["request_count"].(float64)) != 2 {
			t.Fatalf("rl summary request_count = %v, want 2", summary["request_count"])
		}
		if int(summary["estimated_responses"].(float64)) != 0 {
			t.Fatalf("rl summary estimated_responses = %v, want 0", summary["estimated_responses"])
		}
	})

	t.Run("16_usage_filter_requires_admin_for_other_keys", func(t *testing.T) {
		if createdKeyID == "" || createdKeyValue == "" {
			t.Fatal("created key id/value must be set by auth creation subtest")
		}

		createBody := []byte(`{"name":"it-secondary-usage-reader","rate_limit_per_minute":120}`)
		status, raw := doJSONRequest(t, "POST", gateway.URL+"/v1/management/api-keys", bootstrapKey, createBody)
		if status != http.StatusCreated {
			t.Fatalf("create secondary key status = %d, body = %s", status, string(raw))
		}

		resp := decodeJSONObject(t, raw, "secondary key create response")
		secondaryKeyID, _ := resp["id"].(string)
		secondaryKeyValue, _ := resp["api_key"].(string)
		if secondaryKeyID == "" || secondaryKeyValue == "" {
			t.Fatalf("secondary key response missing fields: %s", string(raw))
		}
		extraKeyIDs = append(extraKeyIDs, secondaryKeyID)

		var createdBeforeCount int
		if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM usage_logs WHERE api_key_id = $1`, createdKeyID).Scan(&createdBeforeCount); err != nil {
			t.Fatalf("count created key usage before admin filter assertions: %v", err)
		}

		status, raw = doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", secondaryKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"secondary key usage for admin filter check"}],
			"max_tokens":5
		}`))
		if status != http.StatusOK {
			t.Fatalf("secondary key proxy status = %d, body = %s", status, string(raw))
		}

		status, raw = doJSONRequest(t, "POST", gateway.URL+"/v1/chat/completions", createdKeyValue, []byte(`{
			"model":"gpt-3.5-turbo",
			"messages":[{"role":"user","content":"primary key usage for admin filter check"}],
			"max_tokens":5
		}`))
		if status != http.StatusOK {
			t.Fatalf("created key proxy status for admin filter check = %d, body = %s", status, string(raw))
		}

		status, raw = doJSONRequest(t, "GET", gateway.URL+"/v1/management/usage?api_key_id="+createdKeyID, secondaryKeyValue, nil)
		if status != http.StatusForbidden {
			t.Fatalf("non-admin cross-key usage read status = %d, want 403, body = %s", status, string(raw))
		}

		createdUsageResp := waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage?api_key_id="+createdKeyID, bootstrapKey, createdBeforeCount+1, 5*time.Second)
		createdSummary := requireSummaryMap(t, createdUsageResp, "admin filtered created-key usage")
		if int(createdSummary["request_count"].(float64)) != createdBeforeCount+1 {
			t.Fatalf("created-key filtered request_count = %v, want %d", createdSummary["request_count"], createdBeforeCount+1)
		}

		secondaryUsageResp := waitForUsageSummaryCount(t, gateway.URL+"/v1/management/usage?api_key_id="+secondaryKeyID, bootstrapKey, 1, 5*time.Second)
		if secondaryUsageResp["api_key_id"] != secondaryKeyID {
			t.Fatalf("secondary filtered api_key_id = %v, want %s", secondaryUsageResp["api_key_id"], secondaryKeyID)
		}
		secondarySummary := requireSummaryMap(t, secondaryUsageResp, "admin filtered secondary-key usage")
		if int(secondarySummary["request_count"].(float64)) != 1 {
			t.Fatalf("secondary filtered request_count = %v, want 1", secondarySummary["request_count"])
		}
		if int(secondarySummary["total_tokens"].(float64)) != expectedTotalTokens {
			t.Fatalf("secondary filtered total_tokens = %v, want %d", secondarySummary["total_tokens"], expectedTotalTokens)
		}
	})
}

type errString string

func (e errString) Error() string { return string(e) }

func errStringf(format string, args ...any) error {
	return errString(fmt.Sprintf(format, args...))
}

func decodeJSONObject(t *testing.T, raw []byte, description string) map[string]any {
	t.Helper()

	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("decode %s: %v", description, err)
	}
	return payload
}

func requireSummaryMap(t *testing.T, response map[string]any, description string) map[string]any {
	t.Helper()

	summary, _ := response["summary"].(map[string]any)
	if summary == nil {
		t.Fatalf("missing summary for %s", description)
	}
	return summary
}

func waitForUsageSummaryCount(t *testing.T, usageURL, bearerKey string, expectedCount int, timeout time.Duration) map[string]any {
	t.Helper()

	deadline := time.Now().Add(timeout)
	var lastRaw []byte
	var lastStatus int

	for time.Now().Before(deadline) {
		status, raw := doJSONRequest(t, "GET", usageURL, bearerKey, nil)
		lastStatus = status
		lastRaw = raw
		if status == http.StatusOK {
			usageResp := map[string]any{}
			if err := json.Unmarshal(raw, &usageResp); err == nil {
				summary, _ := usageResp["summary"].(map[string]any)
				if summary != nil {
					if int(summary["request_count"].(float64)) == expectedCount {
						return usageResp
					}
				}
			}
		}
		time.Sleep(120 * time.Millisecond)
	}

	t.Fatalf("usage summary did not reach request_count=%d within %s (last status=%d body=%s)", expectedCount, timeout, lastStatus, string(lastRaw))
	return nil
}

func doJSONRequestWithHeaders(t *testing.T, method, url, bearerKey string, body []byte, extraHeaders map[string]string) (int, []byte, http.Header) {
	t.Helper()

	req, err := http.NewRequest(method, url, bytes.NewReader(body))
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+bearerKey)
	req.Header.Set("Content-Type", "application/json")
	for k, v := range extraHeaders {
		req.Header.Set(k, v)
	}

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("http request failed: %v", err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read response body: %v", err)
	}

	headers := resp.Header.Clone()
	return resp.StatusCode, raw, headers
}
