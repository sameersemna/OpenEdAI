package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"openedai-gateway/internal/models"
)

type LiteLLMClient struct {
	BaseURL string
	Client  *http.Client
}

func NewLiteLLMClient(baseURL string, timeoutSeconds int) *LiteLLMClient {
	return &LiteLLMClient{
		BaseURL: baseURL,
		Client:  &http.Client{Timeout: time.Duration(timeoutSeconds) * time.Second},
	}
}

func (c *LiteLLMClient) Proxy(ctx context.Context, path string, body []byte, headers http.Header) (int, []byte, *models.OpenAIUsage, string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("%s%s", c.BaseURL, path), bytes.NewReader(body))
	if err != nil {
		return 0, nil, nil, "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if reqID := headers.Get("X-Request-ID"); reqID != "" {
		req.Header.Set("X-Request-ID", reqID)
	}

	resp, err := c.Client.Do(req)
	if err != nil {
		return 0, nil, nil, "", err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, nil, nil, "", err
	}

	var parsed map[string]any
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return resp.StatusCode, respBody, nil, "", nil
	}

	model := ""
	if mv, ok := parsed["model"].(string); ok {
		model = mv
	}

	usage := parseUsage(parsed)
	return resp.StatusCode, respBody, usage, model, nil
}

func parseUsage(parsed map[string]any) *models.OpenAIUsage {
	raw, ok := parsed["usage"].(map[string]any)
	if !ok {
		return nil
	}

	u := &models.OpenAIUsage{}
	if v, ok := raw["prompt_tokens"].(float64); ok {
		u.PromptTokens = int(v)
	}
	if v, ok := raw["completion_tokens"].(float64); ok {
		u.CompletionTokens = int(v)
	}
	if v, ok := raw["total_tokens"].(float64); ok {
		u.TotalTokens = int(v)
	}

	if u.TotalTokens == 0 && (u.PromptTokens > 0 || u.CompletionTokens > 0) {
		u.TotalTokens = u.PromptTokens + u.CompletionTokens
	}

	if u.TotalTokens == 0 {
		return nil
	}
	return u
}
