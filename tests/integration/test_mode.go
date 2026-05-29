package integration

import (
	"os"
	"strings"
	"testing"
)

func integrationStrictBackends() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv("INTEGRATION_STRICT_BACKENDS")))
	switch v {
	case "1", "true", "yes", "y", "on":
		return true
	default:
		return false
	}
}

func backendUnavailable(t *testing.T, message string, args ...any) {
	t.Helper()
	if integrationStrictBackends() {
		t.Fatalf("backend unavailable in strict mode: "+message, args...)
	}
	t.Skipf("backend unavailable (expected in test environment): "+message, args...)
}
