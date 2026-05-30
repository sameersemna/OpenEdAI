package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func TestRequestIDMiddlewareGeneratesAndEchoesHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(RequestIDMiddleware())
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 response, got %d", w.Code)
	}

	requestID := w.Header().Get("X-Request-ID")
	if requestID == "" {
		t.Fatal("expected generated X-Request-ID header")
	}
	if _, err := uuid.Parse(requestID); err != nil {
		t.Fatalf("expected generated request id to be valid uuid, got %q", requestID)
	}
}

func TestRequestIDMiddlewarePreservesIncomingHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(RequestIDMiddleware())
	router.GET("/", func(c *gin.Context) {
		if got := c.GetHeader("X-Request-ID"); got != "req-custom-1" {
			c.JSON(http.StatusInternalServerError, gin.H{"error": got})
			return
		}
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Request-ID", "req-custom-1")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 response, got %d", w.Code)
	}
	if got := w.Header().Get("X-Request-ID"); got != "req-custom-1" {
		t.Fatalf("expected response request id to match input, got %q", got)
	}
}
