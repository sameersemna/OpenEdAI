package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"openedai-gateway/internal/models"

	"github.com/coreos/go-systemd/v22/journal"
	"github.com/gin-gonic/gin"
)

func TestJournaldRequestLogMiddlewareCapturesProxyMetadata(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var gotMessage string
	var gotPriority journal.Priority
	var gotFields map[string]string
	originalSender := sendJournalEntry
	sendJournalEntry = func(message string, priority journal.Priority, fields map[string]string) error {
		gotMessage = message
		gotPriority = priority
		gotFields = fields
		return nil
	}
	defer func() {
		sendJournalEntry = originalSender
	}()

	router := gin.New()
	router.Use(JournaldRequestLogMiddleware())
	router.GET("/v1/chat/completions", func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "key-123"})
		SetRequestLogMetrics(c, RequestLogMetrics{UpstreamLatencyMS: 42, TokensUsed: 17})
		c.Header("X-Request-ID", "req-1")
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/v1/chat/completions", nil)
	req.RemoteAddr = "203.0.113.10:4321"
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", w.Code)
	}
	if gotPriority != journal.PriInfo {
		t.Fatalf("expected info priority, got %v", gotPriority)
	}
	if gotMessage != "GET /v1/chat/completions -> 200" {
		t.Fatalf("unexpected journal message %q", gotMessage)
	}
	if gotFields["OPENEDAI_KEY_ID"] != "key-123" {
		t.Fatalf("unexpected key id %q", gotFields["OPENEDAI_KEY_ID"])
	}
	if gotFields["OPENEDAI_HTTP_METHOD"] != http.MethodGet {
		t.Fatalf("unexpected method %q", gotFields["OPENEDAI_HTTP_METHOD"])
	}
	if gotFields["OPENEDAI_REQUEST_PATH"] != "/v1/chat/completions" {
		t.Fatalf("unexpected request path %q", gotFields["OPENEDAI_REQUEST_PATH"])
	}
	if gotFields["OPENEDAI_REMOTE_IP"] != "203.0.113.10" {
		t.Fatalf("unexpected remote ip %q", gotFields["OPENEDAI_REMOTE_IP"])
	}
	if gotFields["OPENEDAI_STATUS_CODE"] != "200" {
		t.Fatalf("unexpected status code %q", gotFields["OPENEDAI_STATUS_CODE"])
	}
	if gotFields["OPENEDAI_UPSTREAM_LATENCY_MS"] != "42" {
		t.Fatalf("unexpected latency %q", gotFields["OPENEDAI_UPSTREAM_LATENCY_MS"])
	}
	if gotFields["OPENEDAI_TOKENS_USED"] != "17" {
		t.Fatalf("unexpected tokens %q", gotFields["OPENEDAI_TOKENS_USED"])
	}
	if gotFields["OPENEDAI_TOKENS"] != "17" {
		t.Fatalf("unexpected token alias %q", gotFields["OPENEDAI_TOKENS"])
	}
	if gotFields["OPENEDAI_REQUEST_ID"] != "req-1" {
		t.Fatalf("unexpected request id %q", gotFields["OPENEDAI_REQUEST_ID"])
	}
}

func TestJournaldRequestLogMiddlewareCapturesAuthFailureWithoutKeyID(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var gotPriority journal.Priority
	var gotFields map[string]string
	originalSender := sendJournalEntry
	sendJournalEntry = func(_ string, priority journal.Priority, fields map[string]string) error {
		gotPriority = priority
		gotFields = fields
		return nil
	}
	defer func() {
		sendJournalEntry = originalSender
	}()

	router := gin.New()
	router.Use(JournaldRequestLogMiddleware())
	router.GET("/v1/management/usage", func(c *gin.Context) {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing bearer token"})
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/management/usage", nil))

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", w.Code)
	}
	if gotPriority != journal.PriWarning {
		t.Fatalf("expected warning priority, got %v", gotPriority)
	}
	if _, ok := gotFields["OPENEDAI_KEY_ID"]; ok {
		t.Fatalf("expected no key id field for auth failure, got %q", gotFields["OPENEDAI_KEY_ID"])
	}
	if gotFields["OPENEDAI_STATUS_CODE"] != "401" {
		t.Fatalf("unexpected status code %q", gotFields["OPENEDAI_STATUS_CODE"])
	}
}

func TestJournaldRequestLogMiddlewareCapturesRateLimitRejection(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var gotPriority journal.Priority
	var gotFields map[string]string
	originalSender := sendJournalEntry
	sendJournalEntry = func(_ string, priority journal.Priority, fields map[string]string) error {
		gotPriority = priority
		gotFields = fields
		return nil
	}
	defer func() {
		sendJournalEntry = originalSender
	}()

	router := gin.New()
	router.Use(JournaldRequestLogMiddleware())
	router.GET("/v1/chat/completions", func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "key-429"})
		c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "rate limit exceeded"})
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/chat/completions", nil))

	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected status 429, got %d", w.Code)
	}
	if gotPriority != journal.PriWarning {
		t.Fatalf("expected warning priority, got %v", gotPriority)
	}
	if gotFields["OPENEDAI_KEY_ID"] != "key-429" {
		t.Fatalf("unexpected key id %q", gotFields["OPENEDAI_KEY_ID"])
	}
	if gotFields["OPENEDAI_STATUS_CODE"] != "429" {
		t.Fatalf("unexpected status code %q", gotFields["OPENEDAI_STATUS_CODE"])
	}
}

func TestJournaldRequestLogMiddlewareOmitsProxyOnlyFieldsForNonProxyRoutes(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var gotFields map[string]string
	originalSender := sendJournalEntry
	sendJournalEntry = func(_ string, _ journal.Priority, fields map[string]string) error {
		gotFields = fields
		return nil
	}
	defer func() {
		sendJournalEntry = originalSender
	}()

	router := gin.New()
	router.Use(JournaldRequestLogMiddleware())
	router.GET("/v1/management/usage", func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "key-mgmt"})
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/management/usage", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", w.Code)
	}
	if _, ok := gotFields["OPENEDAI_UPSTREAM_LATENCY_MS"]; ok {
		t.Fatalf("did not expect latency field for non-proxy route")
	}
	if _, ok := gotFields["OPENEDAI_TOKENS_USED"]; ok {
		t.Fatalf("did not expect tokens field for non-proxy route")
	}
	if gotFields["OPENEDAI_KEY_ID"] != "key-mgmt" {
		t.Fatalf("unexpected key id %q", gotFields["OPENEDAI_KEY_ID"])
	}
}
