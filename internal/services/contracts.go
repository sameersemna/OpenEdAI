package services

import (
	"context"
	"net/http"

	"openedai-gateway/internal/models"
)

// LiteLLMService defines the operations needed by API handlers.
type LiteLLMService interface {
	Health(ctx context.Context) error
	Proxy(ctx context.Context, path string, body []byte, headers http.Header) (int, []byte, *models.OpenAIUsage, string, error)
}

// ElasticsearchService defines Elasticsearch operations used by API handlers.
type ElasticsearchService interface {
	Health(ctx context.Context) error
	Index(ctx context.Context, index, id, text string, metadata map[string]any) error
	Search(ctx context.Context, index, query string, limit int) ([]map[string]any, error)
}

// QdrantService defines Qdrant operations used by API handlers.
type QdrantService interface {
	UpsertPoint(ctx context.Context, collection, id string, vector []float64, payload map[string]any) error
	Search(ctx context.Context, collection string, vector []float64, limit int) ([]map[string]any, error)
}
