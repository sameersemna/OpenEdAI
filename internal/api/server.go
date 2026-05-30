package api

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"openedai-gateway/internal/config"
	"openedai-gateway/internal/middleware"
	"openedai-gateway/internal/models"
	"openedai-gateway/internal/security"
	"openedai-gateway/internal/services"
	"openedai-gateway/internal/storage"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type Server struct {
	Cfg           config.Settings
	Store         *storage.PostgresStore
	RedisClient   *redis.Client
	LiteLLM       *services.LiteLLMClient
	Elasticsearch *services.ElasticsearchClient
	Qdrant        *services.QdrantClient
	Lifecycle     *middleware.RequestLifecycle
	healthCacheMu sync.RWMutex
	healthCache   *cachedHealth

	healthProbesOverride map[string]healthProbe
	hostMetricsOverride  func(context.Context) HostMetrics
}

func (s *Server) Router() *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(middleware.RequestIDMiddleware())

	r.GET("/healthz", s.health)
	r.GET("/livez", s.live)
	r.GET("/discovery", s.discovery)

	v1 := r.Group("/v1")
	if s.Lifecycle != nil {
		v1.Use(middleware.InFlightRequestMiddleware(s.Lifecycle))
	}
	v1.Use(middleware.JournaldRequestLogMiddleware())
	v1.Use(middleware.AuthMiddleware(s.Store, s.Cfg.APIKeyHashPepper))
	v1.Use(middleware.RateLimitMiddlewareWithPrefix(s.RedisClient, s.Cfg.DefaultRateLimitPerMinute, s.Cfg.RedisKeyPrefix))

	v1.POST("/chat/completions", func(c *gin.Context) {
		s.proxyOpenAI(c, "/v1/chat/completions")
	})
	v1.POST("/completions", func(c *gin.Context) {
		s.proxyOpenAI(c, "/v1/completions")
	})

	v1.POST("/rag/index", s.ragIndex)
	v1.POST("/rag/search", s.ragSearch)

	// Management endpoints
	mgmt := v1.Group("/management")
	{
		// Read-only endpoints (any authenticated key)
		mgmt.GET("/api-keys", s.listAPIKeys)
		mgmt.GET("/usage", s.usageSummary)

		// Mutation endpoints (admin keys only)
		admin := mgmt.Group("", middleware.AdminMiddleware())
		{
			admin.POST("/api-keys", s.createAPIKey)
			admin.POST("/api-keys/:id/revoke", s.revokeAPIKey)
			admin.POST("/api-keys/:id/rotate", s.rotateAPIKey)
		}
	}

	return r
}

func (s *Server) discovery(c *gin.Context) {
	c.JSON(http.StatusOK, s.Cfg.ServiceDiscovery())
}

func (s *Server) proxyOpenAI(c *gin.Context, path string) {
	apiKey := middleware.GetAPIKeyFromContext(c)
	if apiKey == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": gin.H{"message": "Unauthorized"}})
		return
	}

	requestID := c.GetHeader("X-Request-ID")
	if requestID == "" {
		requestID = uuid.NewString()
	}

	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Invalid body"}})
		return
	}

	payload := map[string]any{}
	if err := json.Unmarshal(body, &payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Invalid JSON payload"}})
		return
	}

	start := time.Now()
	statusCode, respBody, usage, model, err := s.LiteLLM.Proxy(c.Request.Context(), path, body, c.Request.Header)
	latencyMS := time.Since(start).Milliseconds()
	if err != nil {
		middleware.SetRequestLogMetrics(c, middleware.RequestLogMetrics{
			UpstreamLatencyMS: latencyMS,
		})
		renderAPIError(c, http.StatusBadGateway, "Upstream LiteLLM unavailable", errorTypeServiceUnavailable, errorCodeLiteLLMUnavailable)
		return
	}

	if model == "" {
		if mv, ok := payload["model"].(string); ok {
			model = mv
		}
	}

	if statusCode >= 200 && statusCode < 300 {
		estimated := false
		if usage == nil {
			p, cmpl, total := services.EstimateTokens(payload)
			usage = &models.OpenAIUsage{PromptTokens: p, CompletionTokens: cmpl, TotalTokens: total}
			estimated = true
		}

		middleware.SetRequestLogMetrics(c, middleware.RequestLogMetrics{
			UpstreamLatencyMS: latencyMS,
			TokensUsed:        usage.TotalTokens,
		})

		if err := s.Store.TouchAPIKeyLastUsed(c.Request.Context(), apiKey.ID); err != nil {
			log.Printf("warn: failed touching api key last_used_at key_id=%s request_id=%s err=%v", apiKey.ID, requestID, err)
		}
		if err := s.Store.InsertUsageLog(c.Request.Context(), models.UsageLog{
			ID:               uuid.NewString(),
			APIKeyID:         apiKey.ID,
			RequestID:        requestID,
			Endpoint:         path,
			Model:            model,
			PromptTokens:     usage.PromptTokens,
			CompletionTokens: usage.CompletionTokens,
			TotalTokens:      usage.TotalTokens,
			EstimatedTokens:  estimated,
			StatusCode:       statusCode,
			LatencyMS:        latencyMS,
		}); err != nil {
			log.Printf("warn: failed inserting usage log key_id=%s request_id=%s endpoint=%s err=%v", apiKey.ID, requestID, path, err)
		}
	}

	if statusCode < 200 || statusCode >= 300 {
		middleware.SetRequestLogMetrics(c, middleware.RequestLogMetrics{
			UpstreamLatencyMS: latencyMS,
			TokensUsed:        totalTokens(usage),
		})
	}

	c.Header("Content-Type", "application/json")
	c.Header("X-Request-ID", requestID)
	c.Data(statusCode, "application/json", respBody)
}

func totalTokens(usage *models.OpenAIUsage) int {
	if usage == nil {
		return 0
	}
	return usage.TotalTokens
}

type ragIndexRequest struct {
	ID         string         `json:"id"`
	Index      string         `json:"index"`
	Collection string         `json:"collection"`
	Text       string         `json:"text"`
	Metadata   map[string]any `json:"metadata"`
	Vector     []float64      `json:"vector"`
}

func (s *Server) ragIndex(c *gin.Context) {
	var req ragIndexRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Invalid request body"}})
		return
	}
	if req.ID == "" {
		req.ID = uuid.NewString()
	}
	if req.Index == "" {
		req.Index = "gateway-rag"
	}
	if req.Collection == "" {
		req.Collection = "gateway-rag"
	}

	if err := s.Elasticsearch.Index(c.Request.Context(), req.Index, req.ID, req.Text, req.Metadata); err != nil {
		log.Printf("warn: rag index elasticsearch failed request_id=%s index=%s err=%v", c.GetHeader("X-Request-ID"), req.Index, err)
		renderAPIError(c, http.StatusBadGateway, "RAG indexing backend unavailable", errorTypeServiceUnavailable, errorCodeElasticsearchUnavailable)
		return
	}

	if err := s.Qdrant.UpsertPoint(c.Request.Context(), req.Collection, req.ID, req.Vector, map[string]any{
		"text":     req.Text,
		"metadata": req.Metadata,
	}); err != nil {
		log.Printf("warn: rag index qdrant failed request_id=%s collection=%s err=%v", c.GetHeader("X-Request-ID"), req.Collection, err)
		renderAPIError(c, http.StatusBadGateway, "RAG indexing backend unavailable", errorTypeServiceUnavailable, errorCodeQdrantUnavailable)
		return
	}

	c.JSON(http.StatusOK, gin.H{"id": req.ID, "status": "indexed"})
}

type ragSearchRequest struct {
	Index      string    `json:"index"`
	Collection string    `json:"collection"`
	Query      string    `json:"query"`
	Vector     []float64 `json:"vector"`
	Limit      int       `json:"limit"`
}

func (s *Server) ragSearch(c *gin.Context) {
	var req ragSearchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Invalid request body"}})
		return
	}
	if req.Index == "" {
		req.Index = "gateway-rag"
	}
	if req.Collection == "" {
		req.Collection = "gateway-rag"
	}
	if req.Limit <= 0 {
		req.Limit = 5
	}

	esHits, esErr := s.Elasticsearch.Search(c.Request.Context(), req.Index, req.Query, req.Limit)
	qdrantHits, qErr := s.Qdrant.Search(c.Request.Context(), req.Collection, req.Vector, req.Limit)
	if esErr != nil {
		log.Printf("warn: rag search elasticsearch failed request_id=%s index=%s err=%v", c.GetHeader("X-Request-ID"), req.Index, esErr)
	}
	if qErr != nil {
		log.Printf("warn: rag search qdrant failed request_id=%s collection=%s err=%v", c.GetHeader("X-Request-ID"), req.Collection, qErr)
	}

	c.JSON(http.StatusOK, gin.H{
		"query": req.Query,
		"results": gin.H{
			"elasticsearch": esHits,
			"qdrant":        qdrantHits,
		},
		"errors": gin.H{
			"elasticsearch": ragBackendError("elasticsearch", esErr),
			"qdrant":        ragBackendError("qdrant", qErr),
		},
	})
}

func ragBackendError(backend string, err error) any {
	if err == nil {
		return nil
	}
	if backend == "elasticsearch" {
		return backendUnavailableError(backend, errorCodeElasticsearchUnavailable)
	}
	if backend == "qdrant" {
		return backendUnavailableError(backend, errorCodeQdrantUnavailable)
	}
	return backendUnavailableError(backend, backend+"_unavailable")
}

func renderAPIError(c *gin.Context, statusCode int, message string, errType string, code string) {
	middleware.SetRequestLogError(c, middleware.RequestLogError{Type: errType, Code: code})
	errBody := gin.H{"message": message}
	if errType != "" {
		errBody["type"] = errType
	}
	if code != "" {
		errBody["code"] = code
	}
	c.JSON(statusCode, gin.H{"error": errBody})
}

func (s *Server) listAPIKeys(c *gin.Context) {
	limit := 50
	if raw := c.Query("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}

	keys, err := s.Store.ListAPIKeys(c.Request.Context(), limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to list API keys"}})
		return
	}

	masked := make([]gin.H, 0, len(keys))
	for _, k := range keys {
		h := k.KeyHash
		if len(h) > 12 {
			h = h[:12] + "..."
		}
		masked = append(masked, gin.H{
			"id":                    k.ID,
			"name":                  k.Name,
			"key_hash_prefix":       h,
			"is_active":             k.IsActive,
			"rate_limit_per_minute": k.RateLimitPerMinute,
			"expires_at":            k.ExpiresAt,
			"last_used_at":          k.LastUsedAt,
			"created_at":            k.CreatedAt,
			"updated_at":            k.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"items": masked, "count": len(masked)})
}

func (s *Server) usageSummary(c *gin.Context) {
	apiKey := middleware.GetAPIKeyFromContext(c)
	if apiKey == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": gin.H{"message": "Unauthorized"}})
		return
	}

	apiKeyID := c.Query("api_key_id")
	if apiKeyID == "" {
		apiKeyID = apiKey.ID
	} else if apiKeyID != apiKey.ID && !apiKey.IsAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": gin.H{"message": "Admin privileges required"}})
		return
	}

	hours := 24
	if raw := c.Query("hours"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 24*30 {
			hours = n
		}
	}

	limit := 20
	if raw := c.Query("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}

	to := time.Now().UTC()
	from := to.Add(-time.Duration(hours) * time.Hour)

	summary, err := s.Store.GetUsageSummary(c.Request.Context(), apiKeyID, from, to)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to fetch usage summary"}})
		return
	}

	recent, err := s.Store.ListRecentUsage(c.Request.Context(), apiKeyID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to fetch recent usage"}})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"api_key_id": apiKeyID,
		"window": gin.H{
			"from":  from,
			"to":    to,
			"hours": hours,
		},
		"summary": gin.H{
			"request_count":       summary.RequestCount,
			"prompt_tokens":       summary.PromptTokens,
			"completion_tokens":   summary.CompletionTokens,
			"total_tokens":        summary.TotalTokens,
			"estimated_responses": summary.EstimatedCount,
		},
		"recent": recent,
	})
}

func (s *Server) createAPIKey(c *gin.Context) {
	var req models.CreateAPIKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Invalid request body"}})
		return
	}

	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = "managed-key"
	}

	rateLimit := req.RateLimitPerMinute
	if rateLimit <= 0 {
		rateLimit = s.Cfg.DefaultRateLimitPerMinute
	}

	secret, err := security.GenerateSecretToken(32)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to generate API key"}})
		return
	}

	id := uuid.NewString()
	hash := security.HashSecretToken(secret, s.Cfg.APIKeyHashPepper)

	created, err := s.Store.CreateAPIKey(c.Request.Context(), models.APIKey{
		ID:                 id,
		Name:               name,
		KeyHash:            hash,
		IsActive:           true,
		IsAdmin:            req.IsAdmin,
		RateLimitPerMinute: rateLimit,
		ExpiresAt:          req.ExpiresAt,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to create API key"}})
		return
	}

	plaintextKey := security.FormatSplitAPIKey(id, secret)
	c.JSON(http.StatusCreated, gin.H{
		"id":                    created.ID,
		"name":                  created.Name,
		"api_key":               plaintextKey,
		"is_active":             created.IsActive,
		"rate_limit_per_minute": created.RateLimitPerMinute,
		"expires_at":            created.ExpiresAt,
		"last_used_at":          created.LastUsedAt,
		"created_at":            created.CreatedAt,
		"updated_at":            created.UpdatedAt,
	})
}

func (s *Server) revokeAPIKey(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Missing API key id"}})
		return
	}

	if err := s.Store.RevokeAPIKey(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": gin.H{"message": "API key not found or already inactive"}})
		return
	}

	s.evictAPIKeyCaches(c.Request.Context(), id)

	c.JSON(http.StatusOK, gin.H{
		"id":      id,
		"revoked": true,
	})
}

func (s *Server) rotateAPIKey(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Missing API key id"}})
		return
	}

	var req models.RotateAPIKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil && err != io.EOF {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "Invalid request body"}})
		return
	}

	old, err := s.Store.GetActiveAPIKeyByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": gin.H{"message": "API key not found or inactive"}})
		return
	}

	gracePeriod := req.GracePeriodSec
	if gracePeriod < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": gin.H{"message": "grace_period_sec must be >= 0"}})
		return
	}

	expiresAt := time.Now().UTC()
	if gracePeriod > 0 {
		expiresAt = expiresAt.Add(time.Duration(gracePeriod) * time.Second)
	}

	newSecret, err := security.GenerateSecretToken(32)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to generate new API key"}})
		return
	}

	newID := uuid.NewString()
	newHash := security.HashSecretToken(newSecret, s.Cfg.APIKeyHashPepper)
	keepOldActive := gracePeriod > 0
	rotated, err := s.Store.RotateAPIKey(c.Request.Context(), id, expiresAt, keepOldActive, models.APIKey{
		ID:                 newID,
		Name:               old.Name,
		KeyHash:            newHash,
		IsActive:           true,
		RateLimitPerMinute: old.RateLimitPerMinute,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": gin.H{"message": "Failed to rotate API key"}})
		return
	}

	s.evictAPIKeyCaches(c.Request.Context(), id)

	c.JSON(http.StatusOK, gin.H{
		"rotated_from": gin.H{
			"id":         id,
			"expires_at": expiresAt,
		},
		"new_key": gin.H{
			"id":                    rotated.ID,
			"name":                  rotated.Name,
			"api_key":               security.FormatSplitAPIKey(rotated.ID, newSecret),
			"is_active":             rotated.IsActive,
			"rate_limit_per_minute": rotated.RateLimitPerMinute,
			"created_at":            rotated.CreatedAt,
			"updated_at":            rotated.UpdatedAt,
		},
	})
}

func (s *Server) evictAPIKeyCaches(ctx context.Context, id string) {
	_ = s.RedisClient.Del(ctx, "auth:key:"+id).Err()

	rateKeyPattern := s.Cfg.RedisKeyPrefix + ":rate_limit:" + id + ":*"
	var cursor uint64
	for {
		keys, nextCursor, err := s.RedisClient.Scan(ctx, cursor, rateKeyPattern, 100).Result()
		if err != nil {
			return
		}
		if len(keys) > 0 {
			_ = s.RedisClient.Del(ctx, keys...).Err()
		}
		if nextCursor == 0 {
			break
		}
		cursor = nextCursor
	}
}
