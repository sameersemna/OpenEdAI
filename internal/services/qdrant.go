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

type QdrantClient struct {
	BaseURL string
	Client  *http.Client
}

func NewQdrantClient(baseURL string, timeoutSeconds int) *QdrantClient {
	return &QdrantClient{
		BaseURL: baseURL,
		Client:  &http.Client{Timeout: time.Duration(timeoutSeconds) * time.Second},
	}
}

func (c *QdrantClient) UpsertPoint(ctx context.Context, collection, id string, vector []float64, payload map[string]any) error {
	if len(vector) == 0 {
		return nil
	}

	body, _ := json.Marshal(map[string]any{
		"points": []map[string]any{{
			"id":      id,
			"vector":  vector,
			"payload": payload,
		}},
	})

	url := fmt.Sprintf("%s/collections/%s/points?wait=true", c.BaseURL, collection)
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, url, bytes.NewReader(body))
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
		return fmt.Errorf("qdrant upsert failed: %s", string(raw))
	}
	return nil
}

func (c *QdrantClient) Search(ctx context.Context, collection string, vector []float64, limit int) ([]map[string]any, error) {
	if len(vector) == 0 {
		return []map[string]any{}, nil
	}

	body, _ := json.Marshal(map[string]any{
		"vector":       vector,
		"limit":        limit,
		"with_payload": true,
	})

	url := fmt.Sprintf("%s/collections/%s/points/search", c.BaseURL, collection)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("qdrant search failed: %s", string(raw))
	}

	parsed := map[string]any{}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, err
	}

	results := []map[string]any{}
	arr, ok := parsed["result"].([]any)
	if !ok {
		return results, nil
	}
	for _, item := range arr {
		if row, ok := item.(map[string]any); ok {
			results = append(results, row)
		}
	}
	return results, nil
}
