package middleware

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"openedai-gateway/internal/models"
	"openedai-gateway/internal/security"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func TestAuthMiddlewareMissingBearerToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(authMiddlewareWithLookup(func(context.Context, string) (*models.APIKey, error) {
		return nil, pgx.ErrNoRows
	}, "pepper"))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	assertAuthErrorEnvelope(t, w.Body.Bytes(), "Missing Bearer token", "invalid_request_error")
}

func TestAuthMiddlewareRejectsMalformedSplitKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(authMiddlewareWithLookup(func(context.Context, string) (*models.APIKey, error) {
		return nil, pgx.ErrNoRows
	}, "pepper"))
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer bad-token")
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	assertAuthErrorEnvelope(t, w.Body.Bytes(), "Invalid API key", "invalid_request_error")
}

func TestAuthMiddlewareRejectsOnLookupError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(authMiddlewareWithLookup(func(context.Context, string) (*models.APIKey, error) {
		return nil, errors.New("db unavailable")
	}, "pepper"))
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	key := security.FormatSplitAPIKey("id-1", "secret")
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+key)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	assertAuthErrorEnvelope(t, w.Body.Bytes(), "Invalid API key", "invalid_request_error")
}

func TestAuthMiddlewareRejectsHashMismatch(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(authMiddlewareWithLookup(func(context.Context, string) (*models.APIKey, error) {
		return &models.APIKey{ID: "id-1", KeyHash: security.HashSecretToken("different", "pepper")}, nil
	}, "pepper"))
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	key := security.FormatSplitAPIKey("id-1", "secret")
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+key)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	assertAuthErrorEnvelope(t, w.Body.Bytes(), "Invalid API key", "invalid_request_error")
}

func TestAuthMiddlewareRejectsExpiredAPIKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(authMiddlewareWithLookup(func(context.Context, string) (*models.APIKey, error) {
		expired := time.Now().UTC().Add(-time.Hour)
		return &models.APIKey{ID: "id-1", ExpiresAt: &expired, KeyHash: security.HashSecretToken("secret", "pepper")}, nil
	}, "pepper"))
	router.GET("/", func(c *gin.Context) { c.Status(http.StatusOK) })

	key := security.FormatSplitAPIKey("id-1", "secret")
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+key)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	assertAuthErrorEnvelope(t, w.Body.Bytes(), "Invalid API key", "invalid_request_error")
}

func TestAuthMiddlewareSetsAPIKeyInContextOnSuccess(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(authMiddlewareWithLookup(func(context.Context, string) (*models.APIKey, error) {
		return &models.APIKey{ID: "id-1", IsActive: true, KeyHash: security.HashSecretToken("secret", "pepper")}, nil
	}, "pepper"))
	router.GET("/", func(c *gin.Context) {
		if k := GetAPIKeyFromContext(c); k == nil || k.ID != "id-1" {
			c.Status(http.StatusInternalServerError)
			return
		}
		c.Status(http.StatusOK)
	})

	key := security.FormatSplitAPIKey("id-1", "secret")
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer "+key)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func assertAuthErrorEnvelope(t *testing.T, raw []byte, expectedMessage, expectedType string) {
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
