package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

type fakeElasticsearchService struct {
	hits []map[string]any
	err  error
}

func (f *fakeElasticsearchService) Health(_ context.Context) error {
	return nil
}

func (f *fakeElasticsearchService) Index(_ context.Context, _, _, _ string, _ map[string]any) error {
	return nil
}

func (f *fakeElasticsearchService) Search(_ context.Context, _, _ string, _ int) ([]map[string]any, error) {
	return f.hits, f.err
}

type fakeQdrantService struct {
	hits []map[string]any
	err  error
}

func (f *fakeQdrantService) UpsertPoint(_ context.Context, _, _ string, _ []float64, _ map[string]any) error {
	return nil
}

func (f *fakeQdrantService) Search(_ context.Context, _ string, _ []float64, _ int) ([]map[string]any, error) {
	return f.hits, f.err
}

func TestRAGSearchHandlerStatusContract(t *testing.T) {
	gin.SetMode(gin.TestMode)

	makeRequest := func(s *Server) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		body := `{"index":"i","collection":"c","query":"hello","vector":[0.1,0.2],"limit":3}`
		req := httptest.NewRequest(http.MethodPost, "/v1/rag/search", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		c, _ := gin.CreateTestContext(w)
		c.Request = req
		s.ragSearch(c)
		return w
	}

	t.Run("200 when both backends succeed", func(t *testing.T) {
		s := &Server{
			Elasticsearch: &fakeElasticsearchService{hits: []map[string]any{{"id": "es-1"}}},
			Qdrant:        &fakeQdrantService{hits: []map[string]any{{"id": "qd-1"}}},
		}
		w := makeRequest(s)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
		}
	})

	t.Run("206 when one backend fails", func(t *testing.T) {
		s := &Server{
			Elasticsearch: &fakeElasticsearchService{hits: []map[string]any{{"id": "es-1"}}, err: errors.New("es down")},
			Qdrant:        &fakeQdrantService{hits: []map[string]any{{"id": "qd-1"}}},
		}
		w := makeRequest(s)
		if w.Code != http.StatusPartialContent {
			t.Fatalf("expected 206, got %d body=%s", w.Code, w.Body.String())
		}

		var payload map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		errorsObj, ok := payload["errors"].(map[string]any)
		if !ok {
			t.Fatalf("expected errors object in partial response: %s", w.Body.String())
		}
		if errorsObj["elasticsearch"] == nil {
			t.Fatalf("expected elasticsearch error payload in partial response: %s", w.Body.String())
		}
		esErr, ok := errorsObj["elasticsearch"].(map[string]any)
		if !ok {
			t.Fatalf("expected elasticsearch error envelope object, got %T", errorsObj["elasticsearch"])
		}
		if esErr["type"] != errorTypeServiceUnavailable {
			t.Fatalf("expected error type %q, got %#v", errorTypeServiceUnavailable, esErr["type"])
		}
		if esErr["code"] != errorCodeElasticsearchUnavailable {
			t.Fatalf("expected error code %q, got %#v", errorCodeElasticsearchUnavailable, esErr["code"])
		}
		if errorsObj["qdrant"] != nil {
			t.Fatalf("expected qdrant error to be nil on single-backend failure, got %#v", errorsObj["qdrant"])
		}
	})

	t.Run("502 when both backends fail", func(t *testing.T) {
		s := &Server{
			Elasticsearch: &fakeElasticsearchService{err: errors.New("es down")},
			Qdrant:        &fakeQdrantService{err: errors.New("qdrant down")},
		}
		w := makeRequest(s)
		if w.Code != http.StatusBadGateway {
			t.Fatalf("expected 502, got %d body=%s", w.Code, w.Body.String())
		}

		var payload map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		errorsObj, ok := payload["errors"].(map[string]any)
		if !ok {
			t.Fatalf("expected errors object in full failure response: %s", w.Body.String())
		}
		if errorsObj["elasticsearch"] == nil || errorsObj["qdrant"] == nil {
			t.Fatalf("expected both backend errors in full failure response: %s", w.Body.String())
		}
	})
}
