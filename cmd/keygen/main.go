package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"log"

	"openedai-gateway/internal/config"
)

func main() {
	name := flag.String("name", "default-key", "API key name")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	rawKey, err := generateToken(32)
	if err != nil {
		log.Fatal(err)
	}

	hash := sha256.Sum256([]byte(cfg.APIKeyHashPepper + ":" + rawKey))
	hashHex := hex.EncodeToString(hash[:])

	fmt.Println("Provide this key to clients (shown once):")
	fmt.Printf("  sk-lan-%s\n", rawKey)
	fmt.Println("Insert this hash into api_keys.key_hash:")
	fmt.Printf("  %s\n", hashHex)
	fmt.Println("Example SQL:")
	fmt.Printf("  INSERT INTO api_keys(name, key_hash, rate_limit_per_minute) VALUES('%s', '%s', 120);\n", *name, hashHex)
}

func generateToken(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
