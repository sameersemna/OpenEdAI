package config

import (
	"reflect"
	"strings"
	"testing"
)

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
