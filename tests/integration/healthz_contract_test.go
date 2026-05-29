package integration

import (
	"encoding/json"
	"io"
	"net/http"
	"reflect"
	"testing"
	"time"
)

type healthzContractResponse struct {
	Status       string `json:"status"`
	HealthPolicy struct {
		DegradedLatencyMS    int      `json:"degraded_latency_ms"`
		CriticalDependencies []string `json:"critical_dependencies"`
	} `json:"health_policy"`
	CriticalDependencies []string                  `json:"critical_dependencies"`
	Dependencies         map[string]map[string]any `json:"dependencies"`
}

func TestHealthzContract(t *testing.T) {
	baseURL := gatewayBaseURL()
	if err := waitForGateway(baseURL, 10*time.Second); err != nil {
		t.Fatalf("gateway not ready: %v", err)
	}

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(baseURL + "/healthz")
	if err != nil {
		t.Fatalf("healthz request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("unexpected healthz status code %d", resp.StatusCode)
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read healthz body: %v", err)
	}

	var payload healthzContractResponse
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("decode healthz response: %v (body=%s)", err, string(raw))
	}

	if payload.Status != "healthy" && payload.Status != "degraded" && payload.Status != "unhealthy" {
		t.Fatalf("unexpected healthz status field %q", payload.Status)
	}

	if payload.HealthPolicy.DegradedLatencyMS <= 0 {
		t.Fatalf("health_policy.degraded_latency_ms must be > 0, got %d", payload.HealthPolicy.DegradedLatencyMS)
	}

	if !reflect.DeepEqual(payload.CriticalDependencies, payload.HealthPolicy.CriticalDependencies) {
		t.Fatalf("critical dependency mismatch: top-level=%v health_policy=%v", payload.CriticalDependencies, payload.HealthPolicy.CriticalDependencies)
	}

	if len(payload.Dependencies) == 0 {
		t.Fatal("dependencies map should not be empty")
	}

	for _, dep := range []string{"postgres", "redis", "litellm", "elasticsearch"} {
		if _, ok := payload.Dependencies[dep]; !ok {
			t.Fatalf("missing dependency entry: %s", dep)
		}
	}

	if payload.Status == "unhealthy" && resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("unhealthy status must map to 503, got %d", resp.StatusCode)
	}
	if (payload.Status == "healthy" || payload.Status == "degraded") && resp.StatusCode != http.StatusOK {
		t.Fatalf("healthy/degraded status must map to 200, got %d", resp.StatusCode)
	}

	t.Logf("healthz contract validated: status=%s http=%d threshold=%dms critical=%v", payload.Status, resp.StatusCode, payload.HealthPolicy.DegradedLatencyMS, payload.CriticalDependencies)
}
