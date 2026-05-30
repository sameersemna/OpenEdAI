package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"openedai-gateway/internal/middleware"
	"openedai-gateway/internal/models"
	"openedai-gateway/internal/services"

	"github.com/gin-gonic/gin"
)

func TestProxyOpenAIUpstreamFailureContract(t *testing.T) {
	gin.SetMode(gin.TestMode)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"model":"demo"}`))
	c.Request.Header.Set("Content-Type", "application/json")

	c.Set(middleware.APIKeyContextKey, &models.APIKey{ID: "key-1"})

	s := &Server{
		LiteLLM: services.NewLiteLLMClient("http://127.0.0.1:1", 1),
	}

	s.proxyOpenAI(c, "/v1/chat/completions")

	if w.Code != http.StatusBadGateway {
		t.Fatalf("expected status 502, got %d", w.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to decode body: %v", err)
	}
	errObj, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error object, got %#v", body)
	}
	if errObj["message"] != "Upstream LiteLLM unavailable" {
		t.Fatalf("unexpected message: %#v", errObj["message"])
	}
	if errObj["type"] != errorTypeServiceUnavailable {
		t.Fatalf("unexpected type: %#v", errObj["type"])
	}
	if errObj["code"] != errorCodeLiteLLMUnavailable {
		t.Fatalf("unexpected code: %#v", errObj["code"])
	}

	loggedErr, ok := c.Get("request_log_error")
	if !ok {
		t.Fatal("expected request_log_error metadata")
	}
	typedErr, ok := loggedErr.(middleware.RequestLogError)
	if !ok {
		t.Fatalf("expected request log error type, got %T", loggedErr)
	}
	if typedErr.Type != errorTypeServiceUnavailable || typedErr.Code != errorCodeLiteLLMUnavailable {
		t.Fatalf("unexpected log metadata: %+v", typedErr)
	}
}

func TestProxyOpenAIMalformedJSONReturnsBadRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"model":`))
	c.Request.Header.Set("Content-Type", "application/json")

	c.Set(middleware.APIKeyContextKey, &models.APIKey{ID: "key-1"})

	s := &Server{
		LiteLLM: services.NewLiteLLMClient("http://127.0.0.1:1", 1),
	}

	s.proxyOpenAI(c, "/v1/chat/completions")

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", w.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to decode body: %v", err)
	}
	errObj, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error object, got %#v", body)
	}
	if errObj["message"] != "Invalid JSON payload" {
		t.Fatalf("unexpected message: %#v", errObj["message"])
	}
	if _, ok := c.Get("request_log_error"); ok {
		t.Fatal("did not expect request_log_error metadata for malformed JSON")
	}
}

func TestProxyOpenAIMissingAuthContextReturnsUnauthorized(t *testing.T) {
	gin.SetMode(gin.TestMode)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"model":"demo"}`))
	c.Request.Header.Set("Content-Type", "application/json")

	s := &Server{
		LiteLLM: services.NewLiteLLMClient("http://127.0.0.1:1", 1),
	}

	s.proxyOpenAI(c, "/v1/chat/completions")

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", w.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to decode body: %v", err)
	}
	errObj, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error object, got %#v", body)
	}
	if errObj["message"] != "Unauthorized" {
		t.Fatalf("unexpected message: %#v", errObj["message"])
	}
}
