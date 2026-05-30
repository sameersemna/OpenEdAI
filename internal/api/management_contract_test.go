package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"openedai-gateway/internal/middleware"
	"openedai-gateway/internal/models"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRevokeAPIKeyMissingIDErrorContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/management/api-keys//revoke", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	c.Params = gin.Params{{Key: "id", Value: ""}}

	s.revokeAPIKey(c)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", w.Code, w.Body.String())
	}
	assertAPIErrorEnvelope(t, w.Body.Bytes(), "Missing API key id", errorTypeInvalidRequest, errorCodeMissingAPIKeyID)
}

func TestCreateAPIKeyInvalidBodyErrorContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/management/api-keys", strings.NewReader(`{"name":`))
	req.Header.Set("Content-Type", "application/json")
	c, _ := gin.CreateTestContext(w)
	c.Request = req

	s.createAPIKey(c)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", w.Code, w.Body.String())
	}
	assertAPIErrorEnvelope(t, w.Body.Bytes(), "Invalid request body", errorTypeInvalidRequest, errorCodeInvalidRequestBody)
}

func TestListAPIKeysStoreUnavailableErrorContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/management/api-keys", nil)
	c, _ := gin.CreateTestContext(w)
	c.Request = req

	s.listAPIKeys(c)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d body=%s", w.Code, w.Body.String())
	}
	assertAPIErrorEnvelope(t, w.Body.Bytes(), "Failed to list API keys", errorTypeServerError, errorCodeAPIKeyListFailed)
}

func TestUsageSummaryStoreUnavailableErrorContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/management/usage", nil)
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	c.Set(middleware.APIKeyContextKey, &models.APIKey{ID: "k1", IsActive: true})

	s.usageSummary(c)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d body=%s", w.Code, w.Body.String())
	}
	assertAPIErrorEnvelope(t, w.Body.Bytes(), "Failed to fetch usage summary", errorTypeServerError, errorCodeUsageSummaryFailed)
}

func TestRotateAPIKeyMissingIDErrorContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/management/api-keys//rotate", strings.NewReader(`{"grace_period_sec":10}`))
	req.Header.Set("Content-Type", "application/json")
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	c.Params = gin.Params{{Key: "id", Value: ""}}

	s.rotateAPIKey(c)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", w.Code, w.Body.String())
	}
	assertAPIErrorEnvelope(t, w.Body.Bytes(), "Missing API key id", errorTypeInvalidRequest, errorCodeMissingAPIKeyID)
}

func TestRotateAPIKeyInvalidBodyErrorContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	s := &Server{}

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/management/api-keys/key-1/rotate", strings.NewReader(`{"grace_period_sec":`))
	req.Header.Set("Content-Type", "application/json")
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	c.Params = gin.Params{{Key: "id", Value: "key-1"}}

	s.rotateAPIKey(c)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", w.Code, w.Body.String())
	}
	assertAPIErrorEnvelope(t, w.Body.Bytes(), "Invalid request body", errorTypeInvalidRequest, errorCodeInvalidRequestBody)
}

func assertAPIErrorEnvelope(t *testing.T, raw []byte, expectedMessage, expectedType, expectedCode string) {
	t.Helper()

	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("decode error envelope: %v; body=%s", err, string(raw))
	}
	errObj, ok := payload["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error object in response, body=%s", string(raw))
	}
	if expectedMessage != "" && errObj["message"] != expectedMessage {
		t.Fatalf("expected message %q, got %#v", expectedMessage, errObj["message"])
	}
	if expectedType != "" && errObj["type"] != expectedType {
		t.Fatalf("expected type %q, got %#v", expectedType, errObj["type"])
	}
	if expectedCode != "" && errObj["code"] != expectedCode {
		t.Fatalf("expected code %q, got %#v", expectedCode, errObj["code"])
	}
}
