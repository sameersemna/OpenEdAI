package security

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
)

const SplitKeyPrefix = "sk_ed_"

func GenerateSecretToken(nBytes int) (string, error) {
	if nBytes <= 0 {
		return "", errors.New("token size must be positive")
	}
	b := make([]byte, nBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func FormatSplitAPIKey(id string, secret string) string {
	return SplitKeyPrefix + id + "." + secret
}

func ParseSplitAPIKey(token string) (string, string, error) {
	t := strings.TrimSpace(token)
	if !strings.HasPrefix(strings.ToLower(t), SplitKeyPrefix) {
		return "", "", errors.New("invalid key prefix")
	}
	rest := t[len(SplitKeyPrefix):]
	parts := strings.SplitN(rest, ".", 2)
	if len(parts) != 2 {
		return "", "", errors.New("invalid key format")
	}
	id := strings.TrimSpace(parts[0])
	secret := strings.TrimSpace(parts[1])
	if id == "" || secret == "" {
		return "", "", errors.New("missing key id or secret")
	}
	return id, secret, nil
}

func HashSecretToken(secret string, pepper string) string {
	h := sha256.Sum256([]byte(pepper + ":" + strings.TrimSpace(secret)))
	return hex.EncodeToString(h[:])
}
