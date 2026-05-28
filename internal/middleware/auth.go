package middleware

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"openedai-gateway/internal/models"
	"openedai-gateway/internal/security"
	"openedai-gateway/internal/storage"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

const APIKeyContextKey = "api_key"

func AuthMiddleware(store *storage.PostgresStore, pepper string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authz := c.GetHeader("Authorization")
		if authz == "" || !strings.HasPrefix(strings.ToLower(authz), "bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": gin.H{
					"message": "Missing Bearer token",
					"type":    "invalid_request_error",
				},
			})
			return
		}

		rawKey := strings.TrimSpace(authz[7:])
		keyID, secret, err := security.ParseSplitAPIKey(rawKey)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": gin.H{
					"message": "Invalid API key",
					"type":    "invalid_request_error",
				},
			})
			return
		}

		apiKey, err := store.GetActiveAPIKeyByID(c.Request.Context(), keyID)
		if err != nil {
			status := http.StatusUnauthorized
			if err != pgx.ErrNoRows {
				status = http.StatusUnauthorized
			}
			c.AbortWithStatusJSON(status, gin.H{
				"error": gin.H{
					"message": "Invalid API key",
					"type":    "invalid_request_error",
				},
			})
			return
		}

		expectedHash := security.HashSecretToken(secret, pepper)
		if subtle.ConstantTimeCompare([]byte(apiKey.KeyHash), []byte(expectedHash)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": gin.H{
					"message": "Invalid API key",
					"type":    "invalid_request_error",
				},
			})
			return
		}

		c.Set(APIKeyContextKey, apiKey)
		c.Next()
	}
}

func GetAPIKeyFromContext(c *gin.Context) *models.APIKey {
	v, ok := c.Get(APIKeyContextKey)
	if !ok {
		return nil
	}
	apiKey, ok := v.(*models.APIKey)
	if !ok {
		return nil
	}
	return apiKey
}

// AdminMiddleware checks if the authenticated API key has admin privileges.
// Must be applied after AuthMiddleware.
func AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		apiKey := GetAPIKeyFromContext(c)
		if apiKey == nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": gin.H{
					"message": "Authentication required",
					"type":    "invalid_request_error",
				},
			})
			return
		}

		if !apiKey.IsAdmin {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": gin.H{
					"message": "Admin privileges required",
					"type":    "forbidden_error",
				},
			})
			return
		}

		c.Next()
	}
}
