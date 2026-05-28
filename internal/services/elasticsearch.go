package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type ElasticsearchClient struct {
	BaseURL string
	Client  *http.Client
}

func NewElasticsearchClient(baseURL string, timeoutSeconds int) *ElasticsearchClient {
	return &ElasticsearchClient{
		BaseURL: baseURL,
		Client:  &http.Client{Timeout: time.Duration(timeoutSeconds) * time.Second},
	}
}

func (c *ElasticsearchClient) Index(ctx context.Context, index, id, text string, metadata map[string]any) error {
	payload := map[string]any{"text": text, "metadata": metadata}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, fmt.Sprintf("%s/%s/_doc/%s", c.BaseURL, index, id), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("elasticsearch index failed: %s", string(raw))
	}
	return nil
}

func (c *ElasticsearchClient) Search(ctx context.Context, index, query string, limit int) ([]map[string]any, error) {
	payload := map[string]any{
		"size": limit,
		"query": map[string]any{
			"multi_match": map[string]any{
				"query":  query,
				"fields": []string{"text^2", "metadata.*"},
			},
		},
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s/%s/_search", c.BaseURL, index), bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("elasticsearch search failed: %s", string(raw))
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, err
	}

	results := []map[string]any{}
	hits, ok := parsed["hits"].(map[string]any)
	if !ok {
		return results, nil
	}
	items, ok := hits["hits"].([]any)
	if !ok {
		return results, nil
	}
	for _, item := range items {
		if row, ok := item.(map[string]any); ok {
			results = append(results, row)
		}
	}
	return results, nil
}
