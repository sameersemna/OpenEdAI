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

type fakeElasticsearchIndexService struct {
	err error
}

func (f *fakeElasticsearchIndexService) Health(_ context.Context) error {
	return nil
}

func (f *fakeElasticsearchIndexService) Index(_ context.Context, _, _, _ string, _ map[string]any) error {
	return f.err
}

func (f *fakeElasticsearchIndexService) Search(_ context.Context, _, _ string, _ int) ([]map[string]any, error) {
	return nil, nil
}

type fakeQdrantIndexService struct {
	err error
}

func (f *fakeQdrantIndexService) UpsertPoint(_ context.Context, _, _ string, _ []float64, _ map[string]any) error {
	return f.err
}

func (f *fakeQdrantIndexService) Search(_ context.Context, _ string, _ []float64, _ int) ([]map[string]any, error) {
	return nil, nil
}

func TestRAGIndexHandlerContract(t *testing.T) {
	gin.SetMode(gin.TestMode)

	makeRequest := func(s *Server, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/v1/rag/index", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		c, _ := gin.CreateTestContext(w)
		c.Request = req
		s.ragIndex(c)
		return w
	}

	t.Run("400 for invalid body", func(t *testing.T) {
		s := &Server{}
		w := makeRequest(s, `{"index":`)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d body=%s", w.Code, w.Body.String())
		}
	})

	t.Run("502 with elasticsearch unavailable envelope", func(t *testing.T) {
		s := &Server{
			Elasticsearch: &fakeElasticsearchIndexService{err: errors.New("es down")},
			Qdrant:        &fakeQdrantIndexService{},
		}
		w := makeRequest(s, `{"index":"i","collection":"c","text":"x","vector":[0.1,0.2]}`)
		if w.Code != http.StatusBadGateway {
			t.Fatalf("expected 502, got %d body=%s", w.Code, w.Body.String())
		}

		var payload map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		errObj, ok := payload["error"].(map[string]any)
		if !ok {
			t.Fatalf("expected error object, body=%s", w.Body.String())
		}
		if errObj["type"] != errorTypeServiceUnavailable {
			t.Fatalf("expected type %q, got %#v", errorTypeServiceUnavailable, errObj["type"])
		}
		if errObj["code"] != errorCodeElasticsearchUnavailable {
			t.Fatalf("expected code %q, got %#v", errorCodeElasticsearchUnavailable, errObj["code"])
		}
	})

	t.Run("502 with qdrant unavailable envelope", func(t *testing.T) {
		s := &Server{
			Elasticsearch: &fakeElasticsearchIndexService{},
			Qdrant:        &fakeQdrantIndexService{err: errors.New("qdrant down")},
		}
		w := makeRequest(s, `{"index":"i","collection":"c","text":"x","vector":[0.1,0.2]}`)
		if w.Code != http.StatusBadGateway {
			t.Fatalf("expected 502, got %d body=%s", w.Code, w.Body.String())
		}

		var payload map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		errObj, ok := payload["error"].(map[string]any)
		if !ok {
			t.Fatalf("expected error object, body=%s", w.Body.String())
		}
		if errObj["type"] != errorTypeServiceUnavailable {
			t.Fatalf("expected type %q, got %#v", errorTypeServiceUnavailable, errObj["type"])
		}
		if errObj["code"] != errorCodeQdrantUnavailable {
			t.Fatalf("expected code %q, got %#v", errorCodeQdrantUnavailable, errObj["code"])
		}
	})

	t.Run("200 with indexed status and id", func(t *testing.T) {
		s := &Server{
			Elasticsearch: &fakeElasticsearchIndexService{},
			Qdrant:        &fakeQdrantIndexService{},
		}
		w := makeRequest(s, `{"index":"i","collection":"c","text":"x","vector":[0.1,0.2]}`)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
		}

		var payload map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		if payload["status"] != "indexed" {
			t.Fatalf("expected status indexed, got %#v", payload["status"])
		}
		if id, _ := payload["id"].(string); id == "" {
			t.Fatalf("expected non-empty id, payload=%s", w.Body.String())
		}
	})
}
