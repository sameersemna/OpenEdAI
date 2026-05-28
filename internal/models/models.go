package models

import "time"

type APIKey struct {
	ID                 string
	Name               string
	KeyHash            string
	IsActive           bool
	IsAdmin            bool
	RateLimitPerMinute int
	ExpiresAt          *time.Time
	LastUsedAt         *time.Time
	CreatedAt          time.Time
	UpdatedAt          time.Time
}

type UsageLog struct {
	ID               string
	APIKeyID         string
	RequestID        string
	Endpoint         string
	Model            string
	PromptTokens     int
	CompletionTokens int
	TotalTokens      int
	EstimatedTokens  bool
	StatusCode       int
	LatencyMS        int64
	CreatedAt        time.Time
}

type OpenAIUsage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

type UsageSummary struct {
	RequestCount     int64
	PromptTokens     int64
	CompletionTokens int64
	TotalTokens      int64
	EstimatedCount   int64
}

type CreateAPIKeyRequest struct {
	Name               string     `json:"name"`
	RateLimitPerMinute int        `json:"rate_limit_per_minute"`
	ExpiresAt          *time.Time `json:"expires_at"`
	IsAdmin            bool       `json:"is_admin"`
}

type RotateAPIKeyRequest struct {
	GracePeriodSec int `json:"grace_period_sec"`
}
