package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func benchmarkRequestIDMiddleware(b *testing.B, incomingRequestID string) {
	b.Helper()
	gin.SetMode(gin.TestMode)

	router := gin.New()
	router.Use(RequestIDMiddleware())
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		if incomingRequestID != "" {
			req.Header.Set("X-Request-ID", incomingRequestID)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			b.Fatalf("unexpected status code %d", w.Code)
		}
	}
}

func BenchmarkRequestIDMiddlewareGenerate(b *testing.B) {
	benchmarkRequestIDMiddleware(b, "")
}

func BenchmarkRequestIDMiddlewarePreserve(b *testing.B) {
	benchmarkRequestIDMiddleware(b, "req-custom-1")
}
