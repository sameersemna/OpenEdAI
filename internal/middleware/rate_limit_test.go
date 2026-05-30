package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"openedai-gateway/internal/models"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func TestRateLimitMiddlewareRejectsMissingAPIKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	mini, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer mini.Close()

	redisClient := redis.NewClient(&redis.Options{Addr: mini.Addr()})
	defer redisClient.Close()

	router := gin.New()
	router.Use(RateLimitMiddlewareWithPrefix(redisClient, 2, "it"))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestRateLimitMiddlewareEnforcesDefaultLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	mini, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer mini.Close()

	redisClient := redis.NewClient(&redis.Options{Addr: mini.Addr()})
	defer redisClient.Close()

	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "key-default", RateLimitPerMinute: 0})
		c.Next()
	})
	router.Use(RateLimitMiddlewareWithPrefix(redisClient, 2, "it"))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	for i := 0; i < 2; i++ {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))
		if w.Code != http.StatusOK {
			t.Fatalf("request %d expected 200, got %d", i+1, w.Code)
		}
	}

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 after limit exceeded, got %d", w.Code)
	}
}

func TestRateLimitMiddlewareHonorsAPIKeySpecificLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	mini, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer mini.Close()

	redisClient := redis.NewClient(&redis.Options{Addr: mini.Addr()})
	defer redisClient.Close()

	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "key-specific", RateLimitPerMinute: 1})
		c.Next()
	})
	router.Use(RateLimitMiddlewareWithPrefix(redisClient, 100, "it"))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("first request expected 200, got %d", w.Code)
	}

	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("second request expected 429, got %d", w.Code)
	}
}

func TestRateLimitMiddlewareReturns500WhenRedisUnavailable(t *testing.T) {
	gin.SetMode(gin.TestMode)
	redisClient := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1"})
	defer redisClient.Close()

	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(APIKeyContextKey, &models.APIKey{ID: "key-redis-fail", RateLimitPerMinute: 1})
		c.Next()
	})
	router.Use(RateLimitMiddlewareWithPrefix(redisClient, 1, "it"))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/", nil))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 when redis backend fails, got %d", w.Code)
	}
}
