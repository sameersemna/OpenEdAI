package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"openedai-gateway/internal/config"

	"github.com/gin-gonic/gin"
)

func benchmarkHealthHandler(b *testing.B, cfg config.Settings) {
	b.Helper()

	server := &Server{
		Cfg: cfg,
		healthProbesOverride: map[string]healthProbe{
			"postgres":      func(context.Context) error { return nil },
			"redis":         func(context.Context) error { return nil },
			"litellm":       func(context.Context) error { return nil },
			"elasticsearch": func(context.Context) error { return nil },
		},
		hostMetricsOverride: func(context.Context) HostMetrics {
			return HostMetrics{Hostname: "bench-host"}
		},
	}

	router := server.Router()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			b.Fatalf("unexpected status code %d", w.Code)
		}
	}
}

func BenchmarkHealthHandlerCacheEnabled(b *testing.B) {
	gin.SetMode(gin.ReleaseMode)
	benchmarkHealthHandler(b, config.Settings{HealthCacheTTLMS: 5000})
}

func BenchmarkHealthHandlerCacheDisabled(b *testing.B) {
	gin.SetMode(gin.ReleaseMode)
	benchmarkHealthHandler(b, config.Settings{HealthCacheDisabled: true})
}
