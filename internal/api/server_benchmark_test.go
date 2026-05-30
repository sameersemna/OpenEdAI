package api

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func BenchmarkRenderAPIError(b *testing.B) {
	gin.SetMode(gin.TestMode)

	for i := 0; i < b.N; i++ {
		w := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(w)

		renderAPIError(c, http.StatusBadGateway, "Upstream LiteLLM unavailable", errorTypeServiceUnavailable, errorCodeLiteLLMUnavailable)
		if w.Code != http.StatusBadGateway {
			b.Fatalf("unexpected status code %d", w.Code)
		}
	}
}

func BenchmarkRAGBackendErrorElasticsearch(b *testing.B) {
	err := errors.New("upstream timeout")
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		payload := ragBackendError("elasticsearch", err)
		if payload == nil {
			b.Fatal("expected non-nil payload")
		}
	}
}

func BenchmarkRAGBackendErrorQdrant(b *testing.B) {
	err := errors.New("upstream timeout")
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		payload := ragBackendError("qdrant", err)
		if payload == nil {
			b.Fatal("expected non-nil payload")
		}
	}
}
