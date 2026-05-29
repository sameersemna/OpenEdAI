package api

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestRunHealthProbe(t *testing.T) {
	t.Run("healthy when reachable and fast", func(t *testing.T) {
		result := runHealthProbe(context.Background(), func(context.Context) error {
			return nil
		}, 2*time.Second)

		if result.Status != healthStatusHealthy {
			t.Fatalf("expected healthy status, got %q", result.Status)
		}
		if !result.Reachable {
			t.Fatal("expected reachable probe")
		}
	})

	t.Run("degraded when reachable but slow", func(t *testing.T) {
		result := runHealthProbe(context.Background(), func(context.Context) error {
			time.Sleep(75 * time.Millisecond)
			return nil
		}, 50*time.Millisecond)

		if result.Status != healthStatusDegraded {
			t.Fatalf("expected degraded status, got %q", result.Status)
		}
		if !result.Reachable {
			t.Fatal("expected reachable probe")
		}
	})

	t.Run("unhealthy when probe returns error", func(t *testing.T) {
		result := runHealthProbe(context.Background(), func(context.Context) error {
			return errors.New("boom")
		}, 2*time.Second)

		if result.Status != healthStatusUnhealthy {
			t.Fatalf("expected unhealthy status, got %q", result.Status)
		}
		if result.Reachable {
			t.Fatal("expected unreachable probe")
		}
		if result.Error == "" {
			t.Fatal("expected error message")
		}
	})
}

func TestDeriveOverallHealth(t *testing.T) {
	t.Run("healthy when all dependencies are healthy", func(t *testing.T) {
		status := deriveOverallHealth(map[string]DependencyHealth{
			"postgres": {Status: healthStatusHealthy},
			"redis":    {Status: healthStatusHealthy},
		}, HostMetrics{})

		if status != healthStatusHealthy {
			t.Fatalf("expected healthy, got %q", status)
		}
	})

	t.Run("degraded when dependency is slow", func(t *testing.T) {
		status := deriveOverallHealth(map[string]DependencyHealth{
			"litellm": {Status: healthStatusDegraded},
		}, HostMetrics{})

		if status != healthStatusDegraded {
			t.Fatalf("expected degraded, got %q", status)
		}
	})

	t.Run("degraded when host metrics are partial", func(t *testing.T) {
		status := deriveOverallHealth(map[string]DependencyHealth{
			"postgres": {Status: healthStatusHealthy},
		}, HostMetrics{CollectionErrors: []string{"cpu: timeout"}})

		if status != healthStatusDegraded {
			t.Fatalf("expected degraded, got %q", status)
		}
	})

	t.Run("unhealthy when any dependency is unreachable", func(t *testing.T) {
		status := deriveOverallHealth(map[string]DependencyHealth{
			"redis": {Status: healthStatusUnhealthy},
		}, HostMetrics{})

		if status != healthStatusUnhealthy {
			t.Fatalf("expected unhealthy, got %q", status)
		}
	})

	t.Run("degraded when only noncritical dependency is unreachable", func(t *testing.T) {
		status := deriveOverallHealth(map[string]DependencyHealth{
			"redis":   {Status: healthStatusHealthy},
			"litellm": {Status: healthStatusUnhealthy},
		}, HostMetrics{}, map[string]struct{}{"redis": {}})

		if status != healthStatusDegraded {
			t.Fatalf("expected degraded, got %q", status)
		}
	})
}
