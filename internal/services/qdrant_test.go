package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestQdrantUpsertSkipsWhenVectorMissing(t *testing.T) {
	called := false
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()

	client := NewQdrantClient(upstream.URL, 2)
	if err := client.UpsertPoint(context.Background(), "col", "id", nil, map[string]any{"k": "v"}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if called {
		t.Fatal("expected no upstream calls when vector is empty")
	}
}

func TestQdrantUpsertCreatesCollectionThenInsertsPoint(t *testing.T) {
	steps := []string{}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		steps = append(steps, r.Method+" "+r.URL.Path)
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/collections/demo":
			w.WriteHeader(http.StatusNotFound)
		case r.Method == http.MethodPut && r.URL.Path == "/collections/demo":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPut && r.URL.Path == "/collections/demo/points":
			w.WriteHeader(http.StatusOK)
		default:
			w.WriteHeader(http.StatusBadRequest)
		}
	}))
	defer upstream.Close()

	client := NewQdrantClient(upstream.URL, 2)
	err := client.UpsertPoint(context.Background(), "demo", "id-1", []float64{0.1, 0.2}, map[string]any{"text": "x"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(steps) != 3 {
		t.Fatalf("expected 3 calls, got %d (%v)", len(steps), steps)
	}
}

func TestQdrantSearchParsesResults(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/collections/demo/points/search" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"result":[{"id":"1"},{"id":"2"}]}`))
	}))
	defer upstream.Close()

	client := NewQdrantClient(upstream.URL, 2)
	results, err := client.Search(context.Background(), "demo", []float64{0.1, 0.2}, 3)
	if err != nil {
		t.Fatalf("unexpected search error: %v", err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
}

func TestQdrantSearchReturnsBackendErrorBody(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"status":"bad request"}`))
	}))
	defer upstream.Close()

	client := NewQdrantClient(upstream.URL, 2)
	_, err := client.Search(context.Background(), "demo", []float64{0.1, 0.2}, 3)
	if err == nil {
		t.Fatal("expected search error")
	}
	if !strings.Contains(err.Error(), "bad request") {
		t.Fatalf("expected backend error body in message, got %v", err)
	}
}
