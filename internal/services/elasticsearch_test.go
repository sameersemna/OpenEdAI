package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestElasticsearchSearchAppliesAPIKeyAuth(t *testing.T) {
	var authHeader string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"hits":{"hits":[{"_id":"1"}]}}`))
	}))
	defer upstream.Close()

	client := NewElasticsearchClient(upstream.URL, 2, "", "", "abc123", false)
	hits, err := client.Search(context.Background(), "idx", "hello", 3)
	if err != nil {
		t.Fatalf("search returned error: %v", err)
	}
	if len(hits) != 1 {
		t.Fatalf("expected 1 hit, got %d", len(hits))
	}
	if authHeader != "ApiKey abc123" {
		t.Fatalf("expected API key auth header, got %q", authHeader)
	}
}

func TestElasticsearchHealthTreatsAuthResponsesAsReachable(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer upstream.Close()

	client := NewElasticsearchClient(upstream.URL, 2, "", "", "", false)
	if err := client.Health(context.Background()); err != nil {
		t.Fatalf("expected unauthorized status to be treated as reachable, got %v", err)
	}
}

func TestElasticsearchIndexReturnsBodyErrorOnFailure(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"bad mapping"}`))
	}))
	defer upstream.Close()

	client := NewElasticsearchClient(upstream.URL, 2, "", "", "", false)
	err := client.Index(context.Background(), "idx", "id-1", "text", map[string]any{"k": "v"})
	if err == nil {
		t.Fatal("expected index error")
	}
	if !strings.Contains(err.Error(), "bad mapping") {
		t.Fatalf("expected raw backend error in message, got %v", err)
	}
}
