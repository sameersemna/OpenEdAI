package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"openedai-gateway/internal/models"

	"github.com/gin-gonic/gin"
)

func TestAdminMiddlewareRejectsMissingAPIKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(AdminMiddleware())
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	assertAdminErrorEnvelope(t, w.Body.Bytes(), "Authentication required", "invalid_request_error")
}

func TestAdminMiddlewareRejectsNonAdminAPIKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "non-admin", IsAdmin: false})
		c.Next()
	})
	router.Use(AdminMiddleware())
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", w.Code)
	}
	assertAdminErrorEnvelope(t, w.Body.Bytes(), "Admin privileges required", "forbidden_error")
}

func TestAdminMiddlewareAllowsAdminAPIKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "admin", IsAdmin: true})
		c.Next()
	})
	router.Use(AdminMiddleware())
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func assertAdminErrorEnvelope(t *testing.T, raw []byte, expectedMessage, expectedType string) {
	t.Helper()

	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("decode middleware error payload: %v body=%s", err, string(raw))
	}

	errObj, ok := payload["error"].(map[string]any)
	if !ok {
		t.Fatalf("missing error object: %s", string(raw))
	}

	if msg, _ := errObj["message"].(string); msg != expectedMessage {
		t.Fatalf("error message = %q, want %q", msg, expectedMessage)
	}
	if typ, _ := errObj["type"].(string); typ != expectedType {
		t.Fatalf("error type = %q, want %q", typ, expectedType)
	}
}
