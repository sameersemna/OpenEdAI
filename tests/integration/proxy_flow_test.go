package integration

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"

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

	keyID, splitKey := createTempSplitKey(t, ctx, pool, pepper, "it-proxy-test")

	t.Run("chat_completions", func(t *testing.T) {
		body := []byte(`{
			"model": "gpt-3.5-turbo",
			"messages": [{"role": "user", "content": "Hello"}],
			"max_tokens": 5
		}`)
		status, raw := doJSONRequest(t, "POST", baseURL+"/v1/chat/completions", splitKey, body)
		if status == http.StatusBadGateway {
			backendUnavailable(t, "LiteLLM upstream unavailable")
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
			backendUnavailable(t, "LiteLLM upstream unavailable")
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

	t.Run("usage_summary_other_key_requires_admin", func(t *testing.T) {
		_, adminKey := createTempSplitKeyWithOptions(t, ctx, pool, pepper, "it-usage-admin", true, 180)
		otherID, _ := createTempSplitKey(t, ctx, pool, pepper, "it-usage-other")

		seedUsageLog(t, ctx, pool, otherID, "req-it-usage-filter", 7, 5, http.StatusOK, 44)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?api_key_id="+otherID, splitKey, nil)
		if status != http.StatusForbidden {
			t.Fatalf("non-admin cross-key usage status = %d, want 403, body = %s", status, string(raw))
		}

		status, raw = doJSONRequest(t, "GET", baseURL+"/v1/management/usage?api_key_id="+otherID, adminKey, nil)
		if status != http.StatusOK {
			t.Fatalf("admin filtered usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode admin filtered usage response: %v", err)
		}
		if resp["api_key_id"] != otherID {
			t.Fatalf("admin filtered api_key_id = %v, want %s", resp["api_key_id"], otherID)
		}

		summary, ok := resp["summary"].(map[string]any)
		if !ok {
			t.Fatalf("admin filtered usage response missing summary: %s", string(raw))
		}
		if int(summary["request_count"].(float64)) != 1 {
			t.Fatalf("admin filtered request_count = %v, want 1", summary["request_count"])
		}
		if int(summary["total_tokens"].(float64)) != 12 {
			t.Fatalf("admin filtered total_tokens = %v, want 12", summary["total_tokens"])
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 1 {
			t.Fatalf("admin filtered recent length = %d, want 1", len(recent))
		}
	})

	t.Run("usage_summary_malformed_hours_and_limit_fallback", func(t *testing.T) {
		seedUsageLogs(t, ctx, pool, keyID, 25, "req-it-usage-param-", 3, 2, http.StatusOK, 12)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=not-a-number&limit=-9", splitKey, nil)
		if status != http.StatusOK {
			t.Fatalf("malformed hours/limit usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode malformed hours/limit usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing window: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 24 {
			t.Fatalf("window.hours fallback = %v, want 24", window["hours"])
		}

		summary, ok := resp["summary"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing summary for malformed param fallback: %s", string(raw))
		}
		if summary["request_count"] == nil {
			t.Fatalf("summary request_count missing for malformed param fallback: %+v", summary)
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 20 {
			t.Fatalf("recent fallback limit length = %d, want 20", len(recent))
		}
	})

	t.Run("usage_summary_out_of_range_hours_and_limit_fallback", func(t *testing.T) {
		seedUsageLogs(t, ctx, pool, keyID, 30, "req-it-usage-param-range-", 4, 1, http.StatusOK, 16)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=999999&limit=999999", splitKey, nil)
		if status != http.StatusOK {
			t.Fatalf("out-of-range hours/limit usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode out-of-range hours/limit usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing window for out-of-range params: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 24 {
			t.Fatalf("window.hours out-of-range fallback = %v, want 24", window["hours"])
		}

		summary, ok := resp["summary"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing summary for out-of-range param fallback: %s", string(raw))
		}
		if summary["request_count"] == nil {
			t.Fatalf("summary request_count missing for out-of-range param fallback: %+v", summary)
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 20 {
			t.Fatalf("recent out-of-range fallback limit length = %d, want 20", len(recent))
		}
	})

	t.Run("usage_summary_zero_hours_and_limit_fallback", func(t *testing.T) {
		seedUsageLogs(t, ctx, pool, keyID, 28, "req-it-usage-param-zero-", 2, 3, http.StatusOK, 14)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=0&limit=0", splitKey, nil)
		if status != http.StatusOK {
			t.Fatalf("zero hours/limit usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode zero hours/limit usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing window for zero-value params: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 24 {
			t.Fatalf("window.hours zero-value fallback = %v, want 24", window["hours"])
		}

		summary, ok := resp["summary"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing summary for zero-value param fallback: %s", string(raw))
		}
		if summary["request_count"] == nil {
			t.Fatalf("summary request_count missing for zero-value param fallback: %+v", summary)
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 20 {
			t.Fatalf("recent zero-value fallback limit length = %d, want 20", len(recent))
		}
	})

	t.Run("usage_summary_partial_fallback_valid_hours_zero_limit", func(t *testing.T) {
		seedUsageLogs(t, ctx, pool, keyID, 25, "req-it-usage-partial-", 3, 2, http.StatusOK, 11)

		// hours=12 is valid and should be accepted; limit=0 is invalid and should fall back to default 20
		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=12&limit=0", splitKey, nil)
		if status != http.StatusOK {
			t.Fatalf("partial fallback usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode partial fallback usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing window for partial fallback: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 12 {
			t.Fatalf("window.hours partial fallback = %v, want 12 (valid param accepted)", window["hours"])
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 20 {
			t.Fatalf("recent partial fallback limit length = %d, want 20 (invalid limit=0 falls back)", len(recent))
		}
	})

	t.Run("usage_summary_partial_fallback_zero_hours_valid_limit", func(t *testing.T) {
		seedUsageLogs(t, ctx, pool, keyID, 26, "req-it-usage-partial-mirror-", 4, 1, http.StatusOK, 9)

		// hours=0 is invalid and should fall back to default 24; limit=12 is valid and should be respected
		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=0&limit=12", splitKey, nil)
		if status != http.StatusOK {
			t.Fatalf("partial fallback mirror usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode partial fallback mirror usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("usage response missing window for partial fallback mirror: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 24 {
			t.Fatalf("window.hours partial fallback mirror = %v, want 24 (invalid hours=0 falls back)", window["hours"])
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 12 {
			t.Fatalf("recent partial fallback mirror limit length = %d, want 12 (valid limit respected)", len(recent))
		}
	})

	t.Run("usage_summary_limit_boundary_validation", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-limit-boundary")

		seedUsageLogs(t, ctx, pool, boundaryID, 40, "req-it-usage-limit-boundary-", 2, 2, http.StatusOK, 10)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?limit=500", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("limit=500 usage status = %d, body = %s", status, string(raw))
		}

		var acceptedResp map[string]any
		if err := json.Unmarshal(raw, &acceptedResp); err != nil {
			t.Fatalf("decode limit=500 usage response: %v", err)
		}

		acceptedRecent, _ := acceptedResp["recent"].([]any)
		if len(acceptedRecent) != 40 {
			t.Fatalf("recent length for accepted limit=500 = %d, want 40", len(acceptedRecent))
		}

		status, raw = doJSONRequest(t, "GET", baseURL+"/v1/management/usage?limit=501", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("limit=501 usage status = %d, body = %s", status, string(raw))
		}

		var fallbackResp map[string]any
		if err := json.Unmarshal(raw, &fallbackResp); err != nil {
			t.Fatalf("decode limit=501 usage response: %v", err)
		}

		fallbackRecent, _ := fallbackResp["recent"].([]any)
		if len(fallbackRecent) != 20 {
			t.Fatalf("recent length for out-of-range limit=501 = %d, want 20 fallback", len(fallbackRecent))
		}
	})

	t.Run("usage_summary_hours_boundary_validation", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-hours-boundary")

		seedUsageLogs(t, ctx, pool, boundaryID, 35, "req-it-usage-hours-boundary-", 2, 2, http.StatusOK, 10)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=720&limit=15", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=720 usage status = %d, body = %s", status, string(raw))
		}

		var acceptedResp map[string]any
		if err := json.Unmarshal(raw, &acceptedResp); err != nil {
			t.Fatalf("decode hours=720 usage response: %v", err)
		}

		acceptedWindow, ok := acceptedResp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=720 usage response missing window: %s", string(raw))
		}
		if int(acceptedWindow["hours"].(float64)) != 720 {
			t.Fatalf("window.hours for accepted hours=720 = %v, want 720", acceptedWindow["hours"])
		}

		acceptedRecent, _ := acceptedResp["recent"].([]any)
		if len(acceptedRecent) != 15 {
			t.Fatalf("recent length for accepted hours=720&limit=15 = %d, want 15", len(acceptedRecent))
		}

		status, raw = doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=721&limit=15", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=721 usage status = %d, body = %s", status, string(raw))
		}

		var fallbackResp map[string]any
		if err := json.Unmarshal(raw, &fallbackResp); err != nil {
			t.Fatalf("decode hours=721 usage response: %v", err)
		}

		fallbackWindow, ok := fallbackResp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=721 usage response missing window: %s", string(raw))
		}
		if int(fallbackWindow["hours"].(float64)) != 24 {
			t.Fatalf("window.hours for out-of-range hours=721 = %v, want 24 fallback", fallbackWindow["hours"])
		}

		fallbackRecent, _ := fallbackResp["recent"].([]any)
		if len(fallbackRecent) != 15 {
			t.Fatalf("recent length for out-of-range hours=721&limit=15 = %d, want 15 (valid limit preserved)", len(fallbackRecent))
		}
	})

	t.Run("usage_summary_combined_boundary_validation", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-combined-boundary")

		seedUsageLogs(t, ctx, pool, boundaryID, 35, "req-it-usage-combined-boundary-", 2, 2, http.StatusOK, 10)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=720&limit=500", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=720&limit=500 usage status = %d, body = %s", status, string(raw))
		}

		var acceptedResp map[string]any
		if err := json.Unmarshal(raw, &acceptedResp); err != nil {
			t.Fatalf("decode hours=720&limit=500 usage response: %v", err)
		}

		acceptedWindow, ok := acceptedResp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=720&limit=500 response missing window: %s", string(raw))
		}
		if int(acceptedWindow["hours"].(float64)) != 720 {
			t.Fatalf("window.hours for accepted pair hours=720&limit=500 = %v, want 720", acceptedWindow["hours"])
		}

		acceptedRecent, _ := acceptedResp["recent"].([]any)
		if len(acceptedRecent) != 35 {
			t.Fatalf("recent length for accepted pair hours=720&limit=500 = %d, want 35", len(acceptedRecent))
		}

		status, raw = doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=721&limit=501", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=721&limit=501 usage status = %d, body = %s", status, string(raw))
		}

		var fallbackResp map[string]any
		if err := json.Unmarshal(raw, &fallbackResp); err != nil {
			t.Fatalf("decode hours=721&limit=501 usage response: %v", err)
		}

		fallbackWindow, ok := fallbackResp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=721&limit=501 response missing window: %s", string(raw))
		}
		if int(fallbackWindow["hours"].(float64)) != 24 {
			t.Fatalf("window.hours for fallback pair hours=721&limit=501 = %v, want 24", fallbackWindow["hours"])
		}

		fallbackRecent, _ := fallbackResp["recent"].([]any)
		if len(fallbackRecent) != 20 {
			t.Fatalf("recent length for fallback pair hours=721&limit=501 = %d, want 20", len(fallbackRecent))
		}
	})

	t.Run("usage_summary_lower_boundary_validation", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-lower-boundary")

		seedUsageLogs(t, ctx, pool, boundaryID, 8, "req-it-usage-lower-boundary-", 1, 1, http.StatusOK, 8)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=1&limit=1", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=1&limit=1 usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode hours=1&limit=1 usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=1&limit=1 response missing window: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 1 {
			t.Fatalf("window.hours for lower boundary hours=1 = %v, want 1", window["hours"])
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 1 {
			t.Fatalf("recent length for lower boundary limit=1 = %d, want 1", len(recent))
		}
	})

	t.Run("usage_summary_low_value_mixed_fallback", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-low-mixed")

		seedUsageLogs(t, ctx, pool, boundaryID, 8, "req-it-usage-low-mixed-", 1, 1, http.StatusOK, 8)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=0&limit=1", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=0&limit=1 usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode hours=0&limit=1 usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=0&limit=1 response missing window: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 24 {
			t.Fatalf("window.hours for mixed low fallback hours=0 = %v, want 24", window["hours"])
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 1 {
			t.Fatalf("recent length for mixed low fallback limit=1 = %d, want 1", len(recent))
		}
	})

	t.Run("usage_summary_low_value_mixed_fallback_hours_valid_limit_zero", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-low-mixed-mirror")

		seedUsageLogs(t, ctx, pool, boundaryID, 8, "req-it-usage-low-mixed-mirror-", 1, 1, http.StatusOK, 8)

		status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?hours=1&limit=0", boundaryKey, nil)
		if status != http.StatusOK {
			t.Fatalf("hours=1&limit=0 usage status = %d, body = %s", status, string(raw))
		}

		var resp map[string]any
		if err := json.Unmarshal(raw, &resp); err != nil {
			t.Fatalf("decode hours=1&limit=0 usage response: %v", err)
		}

		window, ok := resp["window"].(map[string]any)
		if !ok {
			t.Fatalf("hours=1&limit=0 response missing window: %s", string(raw))
		}
		if int(window["hours"].(float64)) != 1 {
			t.Fatalf("window.hours for mixed low mirror hours=1 = %v, want 1", window["hours"])
		}

		recent, _ := resp["recent"].([]any)
		if len(recent) != 8 {
			t.Fatalf("recent length for mixed low mirror limit=0 = %d, want 8 (default limit applies but seed count is 8)", len(recent))
		}
	})

	t.Run("usage_summary_malformed_hours_valid_limit_fallback", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-malformed-hours-valid-limit")

		seedUsageLogs(t, ctx, pool, boundaryID, 8, "req-it-usage-malformed-hours-valid-limit-", 1, 1, http.StatusOK, 8)

		_, window, recent := doUsageRequestAndDecodeForProxyFlow(t, baseURL, boundaryKey, "hours=not-a-number&limit=1")
		assertUsageWindowHoursForProxyFlow(t, window, 24, "malformed-hours fallback")
		assertUsageRecentLenForProxyFlow(t, recent, 1, "malformed-hours valid limit=1")
	})

	t.Run("usage_summary_malformed_hours_upper_valid_limit_fallback", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-malformed-hours-upper-valid-limit")

		seedUsageLogs(t, ctx, pool, boundaryID, 40, "req-it-usage-malformed-hours-upper-valid-limit-", 1, 1, http.StatusOK, 8)

		_, window, recent := doUsageRequestAndDecodeForProxyFlow(t, baseURL, boundaryKey, "hours=not-a-number&limit=500")
		assertUsageWindowHoursForProxyFlow(t, window, 24, "malformed-hours upper-valid-limit fallback")
		assertUsageRecentLenForProxyFlow(t, recent, 40, "malformed-hours upper-valid-limit respects limit")
	})

	t.Run("usage_summary_valid_hours_malformed_limit_fallback", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-valid-hours-malformed-limit")

		seedUsageLogs(t, ctx, pool, boundaryID, 8, "req-it-usage-valid-hours-malformed-limit-", 1, 1, http.StatusOK, 8)

		_, window, recent := doUsageRequestAndDecodeForProxyFlow(t, baseURL, boundaryKey, "hours=1&limit=not-a-number")
		assertUsageWindowHoursForProxyFlow(t, window, 1, "valid-hours malformed-limit")
		assertUsageRecentLenForProxyFlow(t, recent, 8, "valid-hours malformed-limit default limit with seed count")
	})

	t.Run("usage_summary_high_hours_malformed_limit_fallback", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-high-hours-malformed-limit")

		seedUsageLogs(t, ctx, pool, boundaryID, 25, "req-it-usage-high-hours-malformed-limit-", 1, 1, http.StatusOK, 8)

		_, window, recent := doUsageRequestAndDecodeForProxyFlow(t, baseURL, boundaryKey, "hours=720&limit=not-a-number")
		assertUsageWindowHoursForProxyFlow(t, window, 720, "high-hours malformed-limit")
		assertUsageRecentLenForProxyFlow(t, recent, 20, "high-hours malformed-limit default limit fallback")
	})

	t.Run("usage_summary_high_hours_malformed_limit_text_variant_fallback", func(t *testing.T) {
		boundaryID, boundaryKey := createTempSplitKey(t, ctx, pool, pepper, "it-usage-high-hours-malformed-limit-text")

		seedUsageLogs(t, ctx, pool, boundaryID, 25, "req-it-usage-high-hours-malformed-limit-text-", 1, 1, http.StatusOK, 8)

		_, window, recent := doUsageRequestAndDecodeForProxyFlow(t, baseURL, boundaryKey, "hours=720&limit=abc123")
		assertUsageWindowHoursForProxyFlow(t, window, 720, "high-hours malformed-limit text variant")
		assertUsageRecentLenForProxyFlow(t, recent, 20, "high-hours malformed-limit text variant default limit fallback")
	})

	t.Run("invalid_key_rejected", func(t *testing.T) {
		invalidKey := "sk_ed_" + uuid.NewString() + ".invalid"
		status, _ := doJSONRequest(t, "GET", baseURL+"/v1/management/usage", invalidKey, nil)
		if status != http.StatusUnauthorized {
			t.Fatalf("invalid key should be rejected with 401, got %d", status)
		}
	})

	t.Run("expired_key_rejected", func(t *testing.T) {
		pastTime := time.Now().UTC().Add(-1 * time.Hour)
		_, expiredKey := createTempSplitKeyWithAdvancedOptions(t, ctx, pool, pepper, "it-expired-test", false, 180, &pastTime)

		status, _ := doJSONRequest(t, "GET", baseURL+"/v1/management/usage", expiredKey, nil)
		if status != http.StatusUnauthorized {
			t.Fatalf("expired key should be rejected with 401, got %d", status)
		}
	})
}

func decodeUsageEnvelopeForProxyFlow(t *testing.T, raw []byte, description string) (map[string]any, map[string]any, []any) {
	t.Helper()

	var resp map[string]any
	if err := json.Unmarshal(raw, &resp); err != nil {
		t.Fatalf("decode %s usage response: %v", description, err)
	}

	window, ok := resp["window"].(map[string]any)
	if !ok {
		t.Fatalf("%s response missing window: %s", description, string(raw))
	}

	recent, _ := resp["recent"].([]any)
	return resp, window, recent
}

func doUsageRequestAndDecodeForProxyFlow(t *testing.T, baseURL, splitKey, query string) (map[string]any, map[string]any, []any) {
	t.Helper()

	description := query
	status, raw := doJSONRequest(t, "GET", baseURL+"/v1/management/usage?"+query, splitKey, nil)
	if status != http.StatusOK {
		t.Fatalf("%s usage status = %d, body = %s", description, status, string(raw))
	}

	return decodeUsageEnvelopeForProxyFlow(t, raw, description)
}

func assertUsageWindowHoursForProxyFlow(t *testing.T, window map[string]any, expected int, context string) {
	t.Helper()

	if int(window["hours"].(float64)) != expected {
		t.Fatalf("window.hours for %s = %v, want %d", context, window["hours"], expected)
	}
}

func assertUsageRecentLenForProxyFlow(t *testing.T, recent []any, expected int, context string) {
	t.Helper()

	if len(recent) != expected {
		t.Fatalf("recent length for %s = %d, want %d", context, len(recent), expected)
	}
}
