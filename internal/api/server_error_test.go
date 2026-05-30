package api

import (
	"errors"
	"net/http"
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

func TestRAGSearchResponseStatus(t *testing.T) {
	t.Run("returns 200 when both backends succeed", func(t *testing.T) {
		if got := ragSearchResponseStatus(nil, nil); got != http.StatusOK {
			t.Fatalf("expected %d, got %d", http.StatusOK, got)
		}
	})

	t.Run("returns 206 when one backend fails", func(t *testing.T) {
		err := errors.New("backend failure")
		if got := ragSearchResponseStatus(err, nil); got != http.StatusPartialContent {
			t.Fatalf("expected %d, got %d", http.StatusPartialContent, got)
		}
		if got := ragSearchResponseStatus(nil, err); got != http.StatusPartialContent {
			t.Fatalf("expected %d, got %d", http.StatusPartialContent, got)
		}
	})

	t.Run("returns 502 when both backends fail", func(t *testing.T) {
		err := errors.New("backend failure")
		if got := ragSearchResponseStatus(err, err); got != http.StatusBadGateway {
			t.Fatalf("expected %d, got %d", http.StatusBadGateway, got)
		}
	})
}
