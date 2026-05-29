package integration

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestGatewayStartupRejectsNegativeHealthDegradedLatency(t *testing.T) {
	repoRoot, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "go", "run", "./cmd/gateway")
	cmd.Dir = repoRoot
	cmd.Env = append(os.Environ(),
		"HEALTH_DEGRADED_LATENCY_MS=-1",
		"API_KEY_HASH_PEPPER=test-pepper",
	)

	output, runErr := cmd.CombinedOutput()
	if runErr == nil {
		t.Fatalf("expected startup failure for negative HEALTH_DEGRADED_LATENCY_MS, got success with output: %s", string(output))
	}

	out := string(output)
	if !strings.Contains(out, "failed loading config") {
		t.Fatalf("expected config load failure in output, got: %s", out)
	}
	if !strings.Contains(out, "HEALTH_DEGRADED_LATENCY_MS must be >= 0") {
		t.Fatalf("expected negative threshold validation error in output, got: %s", out)
	}
}
