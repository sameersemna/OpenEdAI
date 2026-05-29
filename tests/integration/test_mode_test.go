package integration

import "testing"

func TestIntegrationStrictBackends(t *testing.T) {
	t.Run("disabled by default", func(t *testing.T) {
		t.Setenv("INTEGRATION_STRICT_BACKENDS", "")
		if integrationStrictBackends() {
			t.Fatal("expected strict backend mode to be disabled by default")
		}
	})

	for _, value := range []string{"1", "true", "TRUE", "yes", "on", " y "} {
		value := value
		t.Run("enabled:"+value, func(t *testing.T) {
			t.Setenv("INTEGRATION_STRICT_BACKENDS", value)
			if !integrationStrictBackends() {
				t.Fatalf("expected strict backend mode enabled for value %q", value)
			}
		})
	}

	for _, value := range []string{"0", "false", "off", "no", "random"} {
		value := value
		t.Run("disabled:"+value, func(t *testing.T) {
			t.Setenv("INTEGRATION_STRICT_BACKENDS", value)
			if integrationStrictBackends() {
				t.Fatalf("expected strict backend mode disabled for value %q", value)
			}
		})
	}
}
