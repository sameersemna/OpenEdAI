package api

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"time"

	"openedai-gateway/internal/config"
	"openedai-gateway/internal/middleware"
	"openedai-gateway/internal/models"
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
}

func (s *Server) Router() *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	r.GET("/healthz", s.health)
	r.GET("/discovery", s.discovery)

	v1 := r.Group("/v1")
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
	v1.GET("/management/api-keys", s.listAPIKeys)
	v1.GET("/management/usage", s.usageSummary)

	return r
}

func (s *Server) health(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	dbStatus := "ok"
	if err := s.Store.Pool.Ping(ctx); err != nil {
		dbStatus = "down"
	}

	redisStatus := "ok"
	if err := s.RedisClient.Ping(ctx).Err(); err != nil {
		redisStatus = "down"
	}

	litellmStatus := "ok"
	if err := s.LiteLLM.Health(ctx); err != nil {
		litellmStatus = "down"
	}

	elasticsearchStatus := "ok"
	if err := s.Elasticsearch.Health(ctx); err != nil {
		elasticsearchStatus = "down"
	}

	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
		"checks": gin.H{
			"postgres":      dbStatus,
			"redis":         redisStatus,
			"litellm":       litellmStatus,
			"elasticsearch": elasticsearchStatus,
		},
	})
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
		c.JSON(http.StatusBadGateway, gin.H{"error": gin.H{"message": "Upstream LiteLLM unavailable"}})
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

		_ = s.Store.TouchAPIKeyLastUsed(c.Request.Context(), apiKey.ID)
		_ = s.Store.InsertUsageLog(c.Request.Context(), models.UsageLog{
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
		})
	}

	c.Header("Content-Type", "application/json")
	c.Header("X-Request-ID", requestID)
	c.Data(statusCode, "application/json", respBody)
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
		c.JSON(http.StatusBadGateway, gin.H{"error": gin.H{"message": err.Error()}})
		return
	}

	if err := s.Qdrant.UpsertPoint(c.Request.Context(), req.Collection, req.ID, req.Vector, map[string]any{
		"text":     req.Text,
		"metadata": req.Metadata,
	}); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": gin.H{"message": err.Error()}})
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

	c.JSON(http.StatusOK, gin.H{
		"query": req.Query,
		"results": gin.H{
			"elasticsearch": esHits,
			"qdrant":        qdrantHits,
		},
		"errors": gin.H{
			"elasticsearch": errString(esErr),
			"qdrant":        errString(qErr),
		},
	})
}

func errString(err error) any {
	if err == nil {
		return nil
	}
	return err.Error()
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
