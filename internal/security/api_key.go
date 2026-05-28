package security

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

func NormalizeClientAPIKey(token string) string {
	t := strings.TrimSpace(token)
	const prefix = "sk-lan-"
	if strings.HasPrefix(strings.ToLower(t), prefix) {
		return t[len(prefix):]
	}
	return t
}

func HashAPIKey(token string, pepper string) string {
	normalized := NormalizeClientAPIKey(token)
	h := sha256.Sum256([]byte(pepper + ":" + normalized))
	return hex.EncodeToString(h[:])
}
