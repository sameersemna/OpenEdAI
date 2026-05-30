package config

import (
	"reflect"
	"strings"
	"testing"
)

func TestLoadUsesRequestTimeoutAsBackendFallback(t *testing.T) {
	t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
	t.Setenv("REQUEST_TIMEOUT_SECONDS", "42")
	t.Setenv("LITELLM_TIMEOUT_SECONDS", "0")
	t.Setenv("ELASTICSEARCH_TIMEOUT_SECONDS", "-1")
	t.Setenv("QDRANT_TIMEOUT_SECONDS", "0")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("expected successful load, got %v", err)
	}

	if cfg.LiteLLMTimeoutSeconds != 42 {
		t.Fatalf("expected litellm timeout fallback 42, got %d", cfg.LiteLLMTimeoutSeconds)
	}
	if cfg.ElasticsearchTimeoutSeconds != 42 {
		t.Fatalf("expected elasticsearch timeout fallback 42, got %d", cfg.ElasticsearchTimeoutSeconds)
	}
	if cfg.QdrantTimeoutSeconds != 42 {
		t.Fatalf("expected qdrant timeout fallback 42, got %d", cfg.QdrantTimeoutSeconds)
	}
}

func TestLoadRejectsInvalidPostgresPoolConfig(t *testing.T) {
	t.Run("rejects negative min conns", func(t *testing.T) {
		t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
		t.Setenv("POSTGRES_MIN_CONNS", "-1")

		_, err := Load()
		if err == nil || !strings.Contains(err.Error(), "POSTGRES_MIN_CONNS") {
			t.Fatalf("expected POSTGRES_MIN_CONNS validation error, got %v", err)
		}
	})

	t.Run("rejects max lower than min", func(t *testing.T) {
		t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
		t.Setenv("POSTGRES_MIN_CONNS", "5")
		t.Setenv("POSTGRES_MAX_CONNS", "4")

		_, err := Load()
		if err == nil || !strings.Contains(err.Error(), "POSTGRES_MAX_CONNS") {
			t.Fatalf("expected POSTGRES_MAX_CONNS validation error, got %v", err)
		}
	})

	t.Run("rejects non-positive lifetime", func(t *testing.T) {
		t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
		t.Setenv("POSTGRES_MAX_CONN_LIFETIME_SECONDS", "0")

		_, err := Load()
		if err == nil || !strings.Contains(err.Error(), "POSTGRES_MAX_CONN_LIFETIME_SECONDS") {
			t.Fatalf("expected POSTGRES_MAX_CONN_LIFETIME_SECONDS validation error, got %v", err)
		}
	})
}

func TestLoadHealthCacheConfig(t *testing.T) {
	t.Run("loads health cache flags", func(t *testing.T) {
		t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
		t.Setenv("HEALTH_CACHE_DISABLED", "true")
		t.Setenv("HEALTH_CACHE_TTL_MS", "1500")

		cfg, err := Load()
		if err != nil {
			t.Fatalf("expected successful load, got %v", err)
		}
		if !cfg.HealthCacheDisabled {
			t.Fatal("expected health cache to be disabled")
		}
		if cfg.HealthCacheTTLMS != 1500 {
			t.Fatalf("expected health cache ttl 1500, got %d", cfg.HealthCacheTTLMS)
		}
	})

	t.Run("rejects negative cache ttl", func(t *testing.T) {
		t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
		t.Setenv("HEALTH_CACHE_TTL_MS", "-1")

		_, err := Load()
		if err == nil || !strings.Contains(err.Error(), "HEALTH_CACHE_TTL_MS") {
			t.Fatalf("expected HEALTH_CACHE_TTL_MS validation error, got %v", err)
		}
	})
}

func TestLoadRejectsNegativeHealthDegradedLatency(t *testing.T) {
	t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
	t.Setenv("HEALTH_DEGRADED_LATENCY_MS", "-1")

	_, err := Load()
	if err == nil {
		t.Fatal("expected error for negative HEALTH_DEGRADED_LATENCY_MS")
	}
	if !strings.Contains(err.Error(), "HEALTH_DEGRADED_LATENCY_MS") {
		t.Fatalf("expected error mentioning HEALTH_DEGRADED_LATENCY_MS, got %v", err)
	}
}

func TestLoadFallsBackForMalformedHealthDegradedLatency(t *testing.T) {
	t.Setenv("API_KEY_HASH_PEPPER", "test-pepper")
	t.Setenv("HEALTH_DEGRADED_LATENCY_MS", "not-a-number")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("expected successful load with malformed threshold, got %v", err)
	}
	if cfg.HealthDegradedLatencyMS != defaultHealthDegradedLatencyMS {
		t.Fatalf("expected malformed value fallback to %d, got %d", defaultHealthDegradedLatencyMS, cfg.HealthDegradedLatencyMS)
	}
}

func TestResolvedHealthDegradedLatencyMS(t *testing.T) {
	t.Run("returns configured value", func(t *testing.T) {
		cfg := Settings{HealthDegradedLatencyMS: 3500}
		if got := cfg.ResolvedHealthDegradedLatencyMS(); got != 3500 {
			t.Fatalf("expected 3500, got %d", got)
		}
	})

	t.Run("falls back to default when unset", func(t *testing.T) {
		cfg := Settings{}
		if got := cfg.ResolvedHealthDegradedLatencyMS(); got != defaultHealthDegradedLatencyMS {
			t.Fatalf("expected default %d, got %d", defaultHealthDegradedLatencyMS, got)
		}
	})
}

func TestResolvedHealthCriticalDependencies(t *testing.T) {
	t.Run("returns sorted deduplicated configured list", func(t *testing.T) {
		cfg := Settings{HealthCriticalDependencies: "redis, postgres,redis, litellm"}
		got := cfg.ResolvedHealthCriticalDependencies()
		want := []string{"litellm", "postgres", "redis"}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("expected %v, got %v", want, got)
		}
	})

	t.Run("falls back to defaults when empty", func(t *testing.T) {
		cfg := Settings{}
		got := cfg.ResolvedHealthCriticalDependencies()
		want := []string{"elasticsearch", "litellm", "postgres", "redis"}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("expected %v, got %v", want, got)
		}
	})
}
