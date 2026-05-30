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

func TestManagementRouteReadOnlyStoreErrorContractList(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}
	router := buildManagementReadOnlyStoreErrorHarness(s)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/management/api-keys", nil)
	req.Header.Set("X-Test-Role", "user")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d body=%s", w.Code, w.Body.String())
	}
	assertManagementReadOnlyErrorEnvelope(t, w.Body.Bytes(), "Failed to list API keys", errorTypeServerError, errorCodeAPIKeyListFailed)
}

func TestManagementRouteReadOnlyStoreErrorContractUsage(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}
	router := buildManagementReadOnlyStoreErrorHarness(s)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/management/usage", nil)
	req.Header.Set("X-Test-Role", "user")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d body=%s", w.Code, w.Body.String())
	}
	assertManagementReadOnlyErrorEnvelope(t, w.Body.Bytes(), "Failed to fetch usage summary", errorTypeServerError, errorCodeUsageSummaryFailed)
}

func buildManagementReadOnlyStoreErrorHarness(s *Server) *gin.Engine {
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

	mgmt.GET("/api-keys", s.listAPIKeys)
	mgmt.GET("/usage", s.usageSummary)

	return r
}

func assertManagementReadOnlyErrorEnvelope(t *testing.T, raw []byte, expectedMessage, expectedType, expectedCode string) {
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
	if code, _ := errObj["code"].(string); code != expectedCode {
		t.Fatalf("error code = %q, want %q", code, expectedCode)
	}
}
