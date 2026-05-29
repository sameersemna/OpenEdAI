package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"openedai-gateway/internal/config"
)

func TestHealthHandlerResponse(t *testing.T) {
	server := &Server{
		Cfg: config.Settings{HealthDegradedLatencyMS: 25},
		healthProbesOverride: map[string]healthProbe{
			"postgres": func(context.Context) error { return nil },
			"redis":    func(context.Context) error { return nil },
			"litellm": func(context.Context) error {
				time.Sleep(40 * time.Millisecond)
				return nil
			},
			"elasticsearch": func(context.Context) error { return nil },
		},
		hostMetricsOverride: func(context.Context) HostMetrics {
			return HostMetrics{
				Hostname:              "promaxgb10-6116",
				DiskUsagePercent:      42.5,
				MemoryUsedMB:          512,
				MemoryTotalMB:         1024,
				CPUUtilizationPercent: 12.5,
			}
		},
	}

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	server.Router().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200 response, got %d", response.Code)
	}

	var payload HealthResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	if payload.Status != healthStatusDegraded {
		t.Fatalf("expected degraded overall status, got %q", payload.Status)
	}

	if payload.HealthPolicy.DegradedLatencyMS != 25 {
		t.Fatalf("expected health policy threshold 25ms, got %d", payload.HealthPolicy.DegradedLatencyMS)
	}
	if len(payload.HealthPolicy.CriticalDependencies) != 4 || payload.HealthPolicy.CriticalDependencies[0] != "elasticsearch" || payload.HealthPolicy.CriticalDependencies[1] != "litellm" || payload.HealthPolicy.CriticalDependencies[2] != "postgres" || payload.HealthPolicy.CriticalDependencies[3] != "redis" {
		t.Fatalf("expected health policy critical dependencies to be returned and sorted, got %+v", payload.HealthPolicy.CriticalDependencies)
	}

	if len(payload.CriticalDependencies) != 4 || payload.CriticalDependencies[0] != "elasticsearch" || payload.CriticalDependencies[1] != "litellm" || payload.CriticalDependencies[2] != "postgres" || payload.CriticalDependencies[3] != "redis" {
		t.Fatalf("expected critical dependencies to be returned and sorted, got %+v", payload.CriticalDependencies)
	}

	if payload.HostMetrics.Hostname != "promaxgb10-6116" {
		t.Fatalf("expected hostname to round-trip, got %q", payload.HostMetrics.Hostname)
	}

	if got := payload.Dependencies["litellm"]; got.Status != healthStatusDegraded || !got.Reachable {
		t.Fatalf("expected degraded reachable litellm dependency, got %+v", got)
	}

	if got := payload.Dependencies["postgres"]; got.Status != healthStatusHealthy || !got.Reachable {
		t.Fatalf("expected healthy reachable postgres dependency, got %+v", got)
	}
}

func TestHealthHandlerUnhealthyResponse(t *testing.T) {
	server := &Server{
		healthProbesOverride: map[string]healthProbe{
			"postgres":      func(context.Context) error { return nil },
			"redis":         func(context.Context) error { return nil },
			"litellm":       func(context.Context) error { return nil },
			"elasticsearch": func(context.Context) error { return context.DeadlineExceeded },
		},
		hostMetricsOverride: func(context.Context) HostMetrics {
			return HostMetrics{Hostname: "promaxgb10-6116"}
		},
	}

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	server.Router().ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 response, got %d", response.Code)
	}

	var payload HealthResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	if payload.Status != healthStatusUnhealthy {
		t.Fatalf("expected unhealthy status, got %q", payload.Status)
	}

	if payload.HealthPolicy.DegradedLatencyMS != 2000 {
		t.Fatalf("expected default health policy threshold 2000ms, got %d", payload.HealthPolicy.DegradedLatencyMS)
	}

	if len(payload.CriticalDependencies) != 4 {
		t.Fatalf("expected default critical dependencies to be returned, got %+v", payload.CriticalDependencies)
	}

	if got := payload.Dependencies["elasticsearch"]; got.Status != healthStatusUnhealthy || got.Reachable || got.Error == "" {
		t.Fatalf("expected unhealthy unreachable elasticsearch dependency, got %+v", got)
	}
}

func TestLivenessHandlerResponse(t *testing.T) {
	server := &Server{}

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/livez", nil)

	server.Router().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200 response, got %d", response.Code)
	}

	var payload LivenessResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	if payload.Status != healthStatusHealthy {
		t.Fatalf("expected healthy liveness status, got %q", payload.Status)
	}
}

func TestServerDegradedLatencyThreshold(t *testing.T) {
	t.Run("uses configured threshold", func(t *testing.T) {
		server := &Server{Cfg: config.Settings{HealthDegradedLatencyMS: 3210}}
		if got := server.degradedLatencyThreshold(); got != 3210*time.Millisecond {
			t.Fatalf("expected configured threshold, got %s", got)
		}
	})

	t.Run("falls back to default threshold", func(t *testing.T) {
		server := &Server{}
		if got := server.degradedLatencyThreshold(); got != degradedLatencyThreshold {
			t.Fatalf("expected default threshold, got %s", got)
		}
	})
}

func TestServerCriticalDependencies(t *testing.T) {
	server := &Server{Cfg: config.Settings{HealthCriticalDependencies: "postgres, redis ,elasticsearch"}}
	critical := server.criticalDependencies()

	if _, ok := critical["postgres"]; !ok {
		t.Fatal("expected postgres to be critical")
	}
	if _, ok := critical["redis"]; !ok {
		t.Fatal("expected redis to be critical")
	}
	if _, ok := critical["elasticsearch"]; !ok {
		t.Fatal("expected elasticsearch to be critical")
	}
	if _, ok := critical["litellm"]; ok {
		t.Fatal("did not expect litellm to be critical")
	}
}

func TestHealthHandlerNonCriticalFailureDegrades(t *testing.T) {
	server := &Server{
		Cfg: config.Settings{HealthCriticalDependencies: "postgres,redis"},
		healthProbesOverride: map[string]healthProbe{
			"postgres":      func(context.Context) error { return nil },
			"redis":         func(context.Context) error { return nil },
			"litellm":       func(context.Context) error { return context.DeadlineExceeded },
			"elasticsearch": func(context.Context) error { return nil },
		},
		hostMetricsOverride: func(context.Context) HostMetrics {
			return HostMetrics{Hostname: "promaxgb10-6116"}
		},
	}

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	server.Router().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200 response, got %d", response.Code)
	}

	var payload HealthResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	if payload.Status != healthStatusDegraded {
		t.Fatalf("expected degraded status, got %q", payload.Status)
	}

	if len(payload.CriticalDependencies) != 2 {
		t.Fatalf("expected resolved critical dependency list, got %+v", payload.CriticalDependencies)
	}

	if len(payload.HealthPolicy.CriticalDependencies) != 2 {
		t.Fatalf("expected health policy critical dependency list, got %+v", payload.HealthPolicy.CriticalDependencies)
	}
}

func TestHealthHandlerNonCriticalFailureDegradesUsingEnvPolicy(t *testing.T) {
	t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
	t.Setenv("HEALTH_CRITICAL_DEPENDENCIES", "postgres,redis")
	t.Setenv("HEALTH_DEGRADED_LATENCY_MS", "2000")

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	server := &Server{
		Cfg: cfg,
		healthProbesOverride: map[string]healthProbe{
			"postgres":      func(context.Context) error { return nil },
			"redis":         func(context.Context) error { return nil },
			"litellm":       func(context.Context) error { return context.DeadlineExceeded },
			"elasticsearch": func(context.Context) error { return nil },
		},
		hostMetricsOverride: func(context.Context) HostMetrics {
			return HostMetrics{Hostname: "promaxgb10-6116"}
		},
	}

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	server.Router().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200 response for noncritical failure, got %d", response.Code)
	}

	var payload HealthResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	if payload.Status != healthStatusDegraded {
		t.Fatalf("expected degraded status, got %q", payload.Status)
	}
	if payload.HealthPolicy.DegradedLatencyMS != 2000 {
		t.Fatalf("expected health policy threshold 2000ms, got %d", payload.HealthPolicy.DegradedLatencyMS)
	}
	if len(payload.HealthPolicy.CriticalDependencies) != 2 || payload.HealthPolicy.CriticalDependencies[0] != "postgres" || payload.HealthPolicy.CriticalDependencies[1] != "redis" {
		t.Fatalf("expected reduced env critical dependency policy, got %+v", payload.HealthPolicy.CriticalDependencies)
	}
	if got := payload.Dependencies["litellm"]; got.Status != healthStatusUnhealthy {
		t.Fatalf("expected litellm to be unhealthy while noncritical, got %+v", got)
	}
}
