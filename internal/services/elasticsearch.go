package services

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type ElasticsearchClient struct {
	BaseURL  string
	Username string
	Password string
	APIKey   string
	Client   *http.Client
}

func NewElasticsearchClient(baseURL string, timeoutSeconds int, username string, password string, apiKey string, insecureTLS bool) *ElasticsearchClient {
	transport := &http.Transport{}
	if strings.HasPrefix(strings.ToLower(baseURL), "https://") {
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: insecureTLS}
	}

	return &ElasticsearchClient{
		BaseURL:  baseURL,
		Username: username,
		Password: password,
		APIKey:   apiKey,
		Client: &http.Client{
			Timeout:   time.Duration(timeoutSeconds) * time.Second,
			Transport: transport,
		},
	}
}

func (c *ElasticsearchClient) applyAuth(req *http.Request) {
	if c.APIKey != "" {
		req.Header.Set("Authorization", "ApiKey "+c.APIKey)
		return
	}
	if c.Username != "" || c.Password != "" {
		req.SetBasicAuth(c.Username, c.Password)
	}
}

func (c *ElasticsearchClient) Health(ctx context.Context) error {
	// Consider 200/401/403 as reachable; secured clusters can return auth-required.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s/_cluster/health", c.BaseURL), nil)
	if err != nil {
		return err
	}
	c.applyAuth(req)

	resp, err := c.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return nil
	}

	raw, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("elasticsearch health failed: status %d body %s", resp.StatusCode, string(raw))
}

func (c *ElasticsearchClient) Index(ctx context.Context, index, id, text string, metadata map[string]any) error {
	payload := map[string]any{"text": text, "metadata": metadata}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, fmt.Sprintf("%s/%s/_doc/%s", c.BaseURL, index, id), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	c.applyAuth(req)

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
	c.applyAuth(req)

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
