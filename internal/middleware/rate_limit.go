package middleware

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

var rateLimitWindowScript = redis.NewScript(`
local current = redis.call("INCR", KEYS[1])
if current == 1 then
  redis.call("EXPIRE", KEYS[1], ARGV[1])
end
return current
`)

func RateLimitMiddleware(redisClient *redis.Client, defaultLimit int) gin.HandlerFunc {
	return RateLimitMiddlewareWithPrefix(redisClient, defaultLimit, "openedai")
}

func RateLimitMiddlewareWithPrefix(redisClient *redis.Client, defaultLimit int, keyPrefix string) gin.HandlerFunc {
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
		redisKey := fmt.Sprintf("%s:rate_limit:%s:%s", keyPrefix, apiKey.ID, window)

		count, err := rateLimitWindowScript.Run(
			c.Request.Context(),
			redisClient,
			[]string{redisKey},
			int(time.Minute.Seconds()),
		).Int64()
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"error": gin.H{"message": "Rate limit backend error", "type": "server_error"},
			})
			return
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
