package api

import "github.com/gin-gonic/gin"

const (
	errorTypeServiceUnavailable = "service_unavailable"

	errorCodeElasticsearchUnavailable = "elasticsearch_unavailable"
	errorCodeQdrantUnavailable        = "qdrant_unavailable"
	errorCodeLiteLLMUnavailable       = "litellm_unavailable"
)

func backendUnavailableMessage(backend string) string {
	return backend + " backend unavailable"
}

func backendUnavailableError(backend string, code string) gin.H {
	return gin.H{
		"message": backendUnavailableMessage(backend),
		"type":    errorTypeServiceUnavailable,
		"code":    code,
	}
}
