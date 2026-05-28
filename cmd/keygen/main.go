package main

import (
	"flag"
	"fmt"
	"log"

	"openedai-gateway/internal/config"
	"openedai-gateway/internal/security"

	"github.com/google/uuid"
)

func main() {
	name := flag.String("name", "default-key", "API key name")
	isAdmin := flag.Bool("admin", false, "Create admin key with management privileges")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	rawKey, err := generateToken(32)
	if err != nil {
		log.Fatal(err)
	}

	id := uuid.NewString()
	hashHex := security.HashSecretToken(rawKey, cfg.APIKeyHashPepper)
	formatted := security.FormatSplitAPIKey(id, rawKey)

	fmt.Println("Provide this key to clients (shown once):")
	fmt.Printf("  %s\n", formatted)
	fmt.Println("Insert this hash into api_keys.key_hash:")
	fmt.Printf("  %s\n", hashHex)
	fmt.Println("Example SQL:")
	fmt.Printf("  INSERT INTO api_keys(id, name, key_hash, is_active, is_admin, rate_limit_per_minute) VALUES('%s', '%s', '%s', TRUE, %t, 120);\n", id, *name, hashHex, *isAdmin)
}

func generateToken(n int) (string, error) {
	return security.GenerateSecretToken(n)
}
