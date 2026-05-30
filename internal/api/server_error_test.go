package api

import (
	"errors"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRAGBackendError(t *testing.T) {
	t.Run("returns nil when no error", func(t *testing.T) {
		if got := ragBackendError("elasticsearch", nil); got != nil {
			t.Fatalf("expected nil backend error, got %#v", got)
		}
	})

	t.Run("returns standardized error envelope", func(t *testing.T) {
		got := ragBackendError("qdrant", errors.New("internal detail"))
		payload, ok := got.(gin.H)
		if !ok {
			t.Fatalf("expected gin.H payload, got %T", got)
		}

		if payload["message"] != "qdrant backend unavailable" {
			t.Fatalf("unexpected message: %#v", payload["message"])
		}
		if payload["type"] != "service_unavailable" {
			t.Fatalf("unexpected type: %#v", payload["type"])
		}
		if payload["code"] != "qdrant_unavailable" {
			t.Fatalf("unexpected code: %#v", payload["code"])
		}
	})
}
