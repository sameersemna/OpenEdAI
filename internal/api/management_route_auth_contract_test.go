package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"openedai-gateway/internal/middleware"
	"openedai-gateway/internal/models"

	"github.com/gin-gonic/gin"
)

func TestManagementRouteAuthContractUnauthorizedMutation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := buildManagementRouteAuthHarness()

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/management/api-keys", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", w.Code, w.Body.String())
	}
	assertManagementRouteErrorEnvelope(t, w.Body.Bytes(), "Authentication required", "invalid_request_error")
}

func TestManagementRouteAuthContractForbiddenMutation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := buildManagementRouteAuthHarness()

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/management/api-keys", nil)
	req.Header.Set("X-Test-Role", "user")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", w.Code, w.Body.String())
	}
	assertManagementRouteErrorEnvelope(t, w.Body.Bytes(), "Admin privileges required", "forbidden_error")
}

func TestManagementRouteAuthContractReadOnlyAllowsNonAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := buildManagementRouteAuthHarness()

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/management/usage", nil)
	req.Header.Set("X-Test-Role", "user")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
}

func buildManagementRouteAuthHarness() *gin.Engine {
	r := gin.New()

	mgmt := r.Group("/v1/management")
	mgmt.Use(func(c *gin.Context) {
		switch c.GetHeader("X-Test-Role") {
		case "admin":
			c.Set(middleware.APIKeyContextKey, &models.APIKey{ID: "k-admin", IsAdmin: true})
		case "user":
			c.Set(middleware.APIKeyContextKey, &models.APIKey{ID: "k-user", IsAdmin: false})
		}
		c.Next()
	})

	mgmt.GET("/usage", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	admin := mgmt.Group("")
	admin.Use(middleware.AdminMiddleware())
	admin.POST("/api-keys", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{"ok": true})
	})

	return r
}

func assertManagementRouteErrorEnvelope(t *testing.T, raw []byte, expectedMessage, expectedType string) {
	t.Helper()

	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("decode error envelope: %v body=%s", err, string(raw))
	}
	errObj, ok := payload["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error object in response: %s", string(raw))
	}
	if msg, _ := errObj["message"].(string); msg != expectedMessage {
		t.Fatalf("error message = %q, want %q", msg, expectedMessage)
	}
	if typ, _ := errObj["type"].(string); typ != expectedType {
		t.Fatalf("error type = %q, want %q", typ, expectedType)
	}
}
