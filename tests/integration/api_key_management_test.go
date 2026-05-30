package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"openedai-gateway/internal/security"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestAPIKeyManagementLifecycle(t *testing.T) {
	pepper := os.Getenv("API_KEY_HASH_PEPPER")
	if pepper == "" {
		t.Skip("API_KEY_HASH_PEPPER is required")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, postgresDSN())
	if err != nil {
		t.Fatalf("pgxpool new: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("pg ping: %v", err)
	}

	baseURL := gatewayBaseURL()
	if err := waitForGateway(baseURL, 10*time.Second); err != nil {
		t.Fatalf("gateway not ready: %v", err)
	}

	bootstrapID := uuid.NewString()
	bootstrapSecret, err := security.GenerateSecretToken(32)
	if err != nil {
		t.Fatalf("generate bootstrap secret: %v", err)
	}
	bootstrapHash := security.HashSecretToken(bootstrapSecret, pepper)
	bootstrapKey := security.FormatSplitAPIKey(bootstrapID, bootstrapSecret)

	if _, err := pool.Exec(ctx, `
		INSERT INTO api_keys(id, name, key_hash, is_active, is_admin, rate_limit_per_minute)
		VALUES($1, $2, $3, TRUE, TRUE, 120)
	`, bootstrapID, "it-bootstrap", bootstrapHash); err != nil {
		t.Fatalf("insert bootstrap key: %v", err)
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, bootstrapID)
	}()

	type createResp struct {
		ID     string `json:"id"`
		APIKey string `json:"api_key"`
	}
	createBody := []byte(`{"name":"it-created","rate_limit_per_minute":150}`)
	createStatus, createRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys", bootstrapKey, createBody)
	if createStatus != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", createStatus, string(createRaw))
	}
	assertCreateAPIKeyResponseContract(t, createRaw, "it-created", 150)
	var created createResp
	if err := json.Unmarshal(createRaw, &created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}
	if created.ID == "" || created.APIKey == "" {
		t.Fatalf("unexpected create response: %s", string(createRaw))
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, created.ID)
	}()

	negativeRotateStatus, negativeRotateRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+bootstrapID+"/rotate", bootstrapKey, []byte(`{"grace_period_sec":-1}`))
	if negativeRotateStatus != http.StatusBadRequest {
		t.Fatalf("negative rotate status = %d, body = %s", negativeRotateStatus, string(negativeRotateRaw))
	}
	assertErrorEnvelope(t, negativeRotateRaw, "grace_period_sec must be >= 0", "invalid_request_error", "invalid_grace_period")

	type rotateResp struct {
		RotatedFrom struct {
			ID string `json:"id"`
		} `json:"rotated_from"`
		NewKey struct {
			ID     string `json:"id"`
			APIKey string `json:"api_key"`
		} `json:"new_key"`
	}
	rotateBody := []byte(`{"grace_period_sec":60}`)
	rotateStatus, rotateRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+created.ID+"/rotate", bootstrapKey, rotateBody)
	if rotateStatus != http.StatusOK {
		t.Fatalf("rotate status = %d, body = %s", rotateStatus, string(rotateRaw))
	}
	var rotated rotateResp
	if err := json.Unmarshal(rotateRaw, &rotated); err != nil {
		t.Fatalf("decode rotate response: %v", err)
	}
	if rotated.RotatedFrom.ID != created.ID || rotated.NewKey.ID == "" || rotated.NewKey.APIKey == "" {
		t.Fatalf("unexpected rotate response: %s", string(rotateRaw))
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, rotated.NewKey.ID)
	}()

	missingRotateStatus, missingRotateRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+uuid.NewString()+"/rotate", bootstrapKey, []byte(`{"grace_period_sec":10}`))
	if missingRotateStatus != http.StatusNotFound {
		t.Fatalf("missing rotate should return 404, status = %d, body = %s", missingRotateStatus, string(missingRotateRaw))
	}
	assertErrorEnvelope(t, missingRotateRaw, "API key not found or inactive", "invalid_request_error", "api_key_not_found")

	missingRevokeStatus, missingRevokeRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+uuid.NewString()+"/revoke", bootstrapKey, []byte(`{}`))
	if missingRevokeStatus != http.StatusNotFound {
		t.Fatalf("missing revoke should return 404, status = %d, body = %s", missingRevokeStatus, string(missingRevokeRaw))
	}
	assertErrorEnvelope(t, missingRevokeRaw, "API key not found or already inactive", "invalid_request_error", "api_key_not_found")

	oldKeyStatus, oldKeyRaw := doJSONRequest(t, "GET", baseURL+"/v1/management/api-keys", created.APIKey, nil)
	if oldKeyStatus != http.StatusOK {
		t.Fatalf("old key should remain valid during grace period, status = %d, body = %s", oldKeyStatus, string(oldKeyRaw))
	}

	zeroGraceCreateStatus, zeroGraceCreateRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys", bootstrapKey, []byte(`{"name":"it-zero-grace","rate_limit_per_minute":120}`))
	if zeroGraceCreateStatus != http.StatusCreated {
		t.Fatalf("zero-grace setup create status = %d, body = %s", zeroGraceCreateStatus, string(zeroGraceCreateRaw))
	}
	assertCreateAPIKeyResponseContract(t, zeroGraceCreateRaw, "it-zero-grace", 120)
	var zeroGraceCreated createResp
	if err := json.Unmarshal(zeroGraceCreateRaw, &zeroGraceCreated); err != nil {
		t.Fatalf("decode zero-grace create response: %v", err)
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, zeroGraceCreated.ID)
	}()

	zeroGraceRotateStatus, zeroGraceRotateRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+zeroGraceCreated.ID+"/rotate", bootstrapKey, []byte(`{"grace_period_sec":0}`))
	if zeroGraceRotateStatus != http.StatusOK {
		t.Fatalf("zero-grace rotate status = %d, body = %s", zeroGraceRotateStatus, string(zeroGraceRotateRaw))
	}
	var zeroGraceRotated rotateResp
	if err := json.Unmarshal(zeroGraceRotateRaw, &zeroGraceRotated); err != nil {
		t.Fatalf("decode zero-grace rotate response: %v", err)
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, zeroGraceRotated.NewKey.ID)
	}()

	zeroGraceOldStatus, zeroGraceOldRaw := doJSONRequest(t, "GET", baseURL+"/v1/management/api-keys", zeroGraceCreated.APIKey, nil)
	if zeroGraceOldStatus != http.StatusUnauthorized {
		t.Fatalf("old key after zero-grace rotate should be unauthorized, status = %d, body = %s", zeroGraceOldStatus, string(zeroGraceOldRaw))
	}
	assertErrorEnvelope(t, zeroGraceOldRaw, "Invalid API key", "invalid_request_error", "")

	var zeroGraceOldActive bool
	if err := pool.QueryRow(ctx, `SELECT is_active FROM api_keys WHERE id = $1`, zeroGraceCreated.ID).Scan(&zeroGraceOldActive); err != nil {
		t.Fatalf("query zero-grace old key active flag: %v", err)
	}
	if zeroGraceOldActive {
		t.Fatal("expected zero-grace rotated old key to become inactive")
	}

	revokeStatus, revokeRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+rotated.NewKey.ID+"/revoke", bootstrapKey, []byte(`{}`))
	if revokeStatus != http.StatusOK {
		t.Fatalf("revoke status = %d, body = %s", revokeStatus, string(revokeRaw))
	}

	revokedKeyStatus, revokedKeyRaw := doJSONRequest(t, "GET", baseURL+"/v1/management/api-keys", rotated.NewKey.APIKey, nil)
	if revokedKeyStatus != http.StatusUnauthorized {
		t.Fatalf("revoked key should be rejected, status = %d, body = %s", revokedKeyStatus, string(revokedKeyRaw))
	}
	assertErrorEnvelope(t, revokedKeyRaw, "Invalid API key", "invalid_request_error", "")

	invalidKeyStatus, invalidKeyRaw := doJSONRequest(t, "GET", baseURL+"/v1/management/api-keys", "sk_ed_invalid.invalid", nil)
	if invalidKeyStatus != http.StatusUnauthorized {
		t.Fatalf("invalid key should be rejected, status = %d, body = %s", invalidKeyStatus, string(invalidKeyRaw))
	}
	assertErrorEnvelope(t, invalidKeyRaw, "Invalid API key", "invalid_request_error", "")

	var active bool
	if err := pool.QueryRow(ctx, `SELECT is_active FROM api_keys WHERE id = $1`, rotated.NewKey.ID).Scan(&active); err != nil {
		t.Fatalf("query revoked key: %v", err)
	}
	if active {
		t.Fatal("expected revoked key to be inactive")
	}

	// Test non-admin key rejection for management mutations
	nonAdminID := uuid.NewString()
	nonAdminSecret, err := security.GenerateSecretToken(32)
	if err != nil {
		t.Fatalf("generate non-admin secret: %v", err)
	}
	nonAdminHash := security.HashSecretToken(nonAdminSecret, pepper)
	nonAdminKey := security.FormatSplitAPIKey(nonAdminID, nonAdminSecret)

	if _, err := pool.Exec(ctx, `
		INSERT INTO api_keys(id, name, key_hash, is_active, is_admin, rate_limit_per_minute)
		VALUES($1, $2, $3, TRUE, FALSE, 120)
	`, nonAdminID, "it-non-admin", nonAdminHash); err != nil {
		t.Fatalf("insert non-admin key: %v", err)
	}
	defer func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM api_keys WHERE id = $1`, nonAdminID)
	}()

	// Non-admin key should be able to read (list keys, usage)
	listStatus, _ := doJSONRequest(t, "GET", baseURL+"/v1/management/api-keys", nonAdminKey, nil)
	if listStatus != http.StatusOK {
		t.Fatalf("non-admin key should be able to list keys, status = %d", listStatus)
	}

	// Non-admin key should NOT be able to create
	createNonAdminStatus, createNonAdminRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys", nonAdminKey, []byte(`{"name":"forbidden"}`))
	if createNonAdminStatus != http.StatusForbidden {
		t.Fatalf("non-admin create should be forbidden, status = %d, body = %s", createNonAdminStatus, string(createNonAdminRaw))
	}
	assertErrorEnvelope(t, createNonAdminRaw, "Admin privileges required", "forbidden_error", "")

	// Non-admin key should NOT be able to revoke
	revokeNonAdminStatus, revokeNonAdminRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+created.ID+"/revoke", nonAdminKey, []byte(`{}`))
	if revokeNonAdminStatus != http.StatusForbidden {
		t.Fatalf("non-admin revoke should be forbidden, status = %d, body = %s", revokeNonAdminStatus, string(revokeNonAdminRaw))
	}
	assertErrorEnvelope(t, revokeNonAdminRaw, "Admin privileges required", "forbidden_error", "")

	// Non-admin key should NOT be able to rotate
	rotateNonAdminStatus, rotateNonAdminRaw := doJSONRequest(t, "POST", baseURL+"/v1/management/api-keys/"+created.ID+"/rotate", nonAdminKey, []byte(`{"grace_period_sec":60}`))
	if rotateNonAdminStatus != http.StatusForbidden {
		t.Fatalf("non-admin rotate should be forbidden, status = %d, body = %s", rotateNonAdminStatus, string(rotateNonAdminRaw))
	}
	assertErrorEnvelope(t, rotateNonAdminRaw, "Admin privileges required", "forbidden_error", "")
}

func doJSONRequest(t *testing.T, method string, url string, bearerKey string, body []byte) (int, []byte) {
	t.Helper()

	req, err := http.NewRequest(method, url, bytes.NewReader(body))
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+bearerKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("http request failed: %v", err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read response body: %v", err)
	}
	return resp.StatusCode, raw
}

func waitForGateway(baseURL string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	client := &http.Client{Timeout: 3 * time.Second}
	for time.Now().Before(deadline) {
		resp, err := client.Get(baseURL + "/livez")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("livez did not return 200 within %s", timeout)
}

func gatewayBaseURL() string {
	port := os.Getenv("GATEWAY_PORT")
	if port == "" {
		port = "8380"
	}
	return "http://127.0.0.1:" + port
}

func postgresDSN() string {
	host := envOrDefault("POSTGRES_HOST", "127.0.0.1")
	port := envOrDefault("POSTGRES_PORT", "5432")
	db := envOrDefault("POSTGRES_DB", "openedai_gateway")
	user := envOrDefault("POSTGRES_USER", "postgres")
	pass := os.Getenv("POSTGRES_PASSWORD")
	sslmode := envOrDefault("POSTGRES_SSLMODE", "prefer")

	return fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=%s", host, port, db, user, pass, sslmode)
}

func envOrDefault(key string, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}

func assertCreateAPIKeyResponseContract(t *testing.T, raw []byte, expectedName string, expectedRateLimit int) {
	t.Helper()

	var resp map[string]any
	if err := json.Unmarshal(raw, &resp); err != nil {
		t.Fatalf("decode create api key response: %v; body=%s", err, string(raw))
	}

	id, _ := resp["id"].(string)
	if id == "" {
		t.Fatalf("create response missing id: %s", string(raw))
	}
	if name, _ := resp["name"].(string); name != expectedName {
		t.Fatalf("create response name = %q, want %q", name, expectedName)
	}
	apiKey, _ := resp["api_key"].(string)
	if !strings.HasPrefix(apiKey, "sk_ed_") || !strings.Contains(apiKey, ".") {
		t.Fatalf("create response api_key format invalid: %q", apiKey)
	}
	isActive, ok := resp["is_active"].(bool)
	if !ok || !isActive {
		t.Fatalf("create response is_active = %#v, want true", resp["is_active"])
	}
	rateLimit, ok := resp["rate_limit_per_minute"].(float64)
	if !ok || int(rateLimit) != expectedRateLimit {
		t.Fatalf("create response rate_limit_per_minute = %#v, want %d", resp["rate_limit_per_minute"], expectedRateLimit)
	}
	if _, ok := resp["created_at"]; !ok {
		t.Fatalf("create response missing created_at: %s", string(raw))
	}
	if _, ok := resp["updated_at"]; !ok {
		t.Fatalf("create response missing updated_at: %s", string(raw))
	}
}
