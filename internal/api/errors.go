package api

import "github.com/gin-gonic/gin"

const (
	errorTypeServiceUnavailable = "service_unavailable"
	errorTypeInvalidRequest     = "invalid_request_error"
	errorTypeServerError        = "server_error"

	errorCodeElasticsearchUnavailable = "elasticsearch_unavailable"
	errorCodeQdrantUnavailable        = "qdrant_unavailable"
	errorCodeLiteLLMUnavailable       = "litellm_unavailable"
	errorCodeInvalidRequestBody       = "invalid_request_body"
	errorCodeMissingAPIKeyID          = "missing_api_key_id"
	errorCodeAPIKeyNotFound           = "api_key_not_found"
	errorCodeInvalidGracePeriod       = "invalid_grace_period"
	errorCodeAPIKeyCreateFailed       = "api_key_create_failed"
	errorCodeAPIKeyRotateFailed       = "api_key_rotate_failed"
	errorCodeAPIKeyGenerateFailed     = "api_key_generate_failed"
	errorCodeAPIKeyListFailed         = "api_key_list_failed"
	errorCodeUsageSummaryFailed       = "usage_summary_failed"
	errorCodeUsageRecentFailed        = "usage_recent_failed"
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
