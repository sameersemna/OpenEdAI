package middleware

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func RateLimitMiddleware(redisClient *redis.Client, defaultLimit int) gin.HandlerFunc {
	return func(c *gin.Context) {
		apiKey := GetAPIKeyFromContext(c)
		if apiKey == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": gin.H{"message": "Unauthorized"}})
			return
		}

		limit := apiKey.RateLimitPerMinute
		if limit <= 0 {
			limit = defaultLimit
		}

		window := time.Now().UTC().Format("200601021504")
		redisKey := fmt.Sprintf("rate_limit:%s:%s", apiKey.ID, window)

		count, err := redisClient.Incr(c.Request.Context(), redisKey).Result()
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"error": gin.H{"message": "Rate limit backend error", "type": "server_error"},
			})
			return
		}
		if count == 1 {
			_ = redisClient.Expire(c.Request.Context(), redisKey, time.Minute).Err()
		}

		if int(count) > limit {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": gin.H{"message": "Rate limit exceeded", "type": "rate_limit_error"},
			})
			return
		}

		c.Next()
	}
}
