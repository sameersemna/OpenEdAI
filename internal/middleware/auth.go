package middleware

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strings"

	"openedai-gateway/internal/models"
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
		h := sha256.Sum256([]byte(pepper + ":" + rawKey))
		hash := hex.EncodeToString(h[:])

		apiKey, err := store.GetActiveAPIKeyByHash(c.Request.Context(), hash)
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
