package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"openedai-gateway/internal/middleware"

	"github.com/gin-gonic/gin"
)

func TestBackendUnavailableErrorContract(t *testing.T) {
	testCases := []struct {
		name    string
		backend string
		code    string
	}{
		{name: "elasticsearch", backend: "elasticsearch", code: errorCodeElasticsearchUnavailable},
		{name: "qdrant", backend: "qdrant", code: errorCodeQdrantUnavailable},
		{name: "litellm", backend: "litellm", code: errorCodeLiteLLMUnavailable},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			payload := backendUnavailableError(tc.backend, tc.code)
			if payload["message"] != tc.backend+" backend unavailable" {
				t.Fatalf("unexpected message: %#v", payload["message"])
			}
			if payload["type"] != errorTypeServiceUnavailable {
				t.Fatalf("unexpected type: %#v", payload["type"])
			}
			if payload["code"] != tc.code {
				t.Fatalf("unexpected code: %#v", payload["code"])
			}
		})
	}
}

func TestRenderAPIErrorSetsResponseAndLogMetadata(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	renderAPIError(c, http.StatusBadGateway, "Upstream LiteLLM unavailable", errorTypeServiceUnavailable, errorCodeLiteLLMUnavailable)

	if w.Code != http.StatusBadGateway {
		t.Fatalf("expected status 502, got %d", w.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to decode json body: %v", err)
	}

	errObj, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("expected error object in body, got %#v", body)
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

	requestErr, ok := c.Get("request_log_error")
	if !ok {
		t.Fatal("expected request_log_error metadata to be set")
	}
	typed, ok := requestErr.(middleware.RequestLogError)
	if !ok {
		t.Fatalf("expected RequestLogError type, got %T", requestErr)
	}
	if typed.Type != errorTypeServiceUnavailable || typed.Code != errorCodeLiteLLMUnavailable {
		t.Fatalf("unexpected request log error metadata: %+v", typed)
	}
}
