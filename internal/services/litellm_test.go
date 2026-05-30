package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLiteLLMProxyParsesUsageAndModel(t *testing.T) {
	var gotRequestID string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotRequestID = r.Header.Get("X-Request-ID")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"gpt-test","usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}`))
	}))
	defer upstream.Close()

	client := NewLiteLLMClient(upstream.URL, 2)
	headers := make(http.Header)
	headers.Set("X-Request-ID", "req-123")

	status, body, usage, model, err := client.Proxy(context.Background(), "/v1/chat/completions", []byte(`{"model":"gpt-test"}`), headers)
	if err != nil {
		t.Fatalf("proxy returned error: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("expected status 200, got %d", status)
	}
	if !strings.Contains(string(body), "gpt-test") {
		t.Fatalf("unexpected body: %s", string(body))
	}
	if model != "gpt-test" {
		t.Fatalf("expected model gpt-test, got %q", model)
	}
	if usage == nil || usage.TotalTokens != 5 || usage.PromptTokens != 2 || usage.CompletionTokens != 3 {
		t.Fatalf("unexpected usage parsed: %+v", usage)
	}
	if gotRequestID != "req-123" {
		t.Fatalf("expected request id header propagation, got %q", gotRequestID)
	}
}

func TestLiteLLMHealthUsesFallbackPath(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		if r.URL.Path == "/v1/models" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer upstream.Close()

	client := NewLiteLLMClient(upstream.URL, 2)
	if err := client.Health(context.Background()); err != nil {
		t.Fatalf("expected health fallback success, got %v", err)
	}
}
