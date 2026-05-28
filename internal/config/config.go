package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type ServiceEndpoint struct {
	Name   string `json:"name"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
	Scheme string `json:"scheme"`
}

func (s ServiceEndpoint) BaseURL() string {
	if s.Scheme == "tcp" {
		return fmt.Sprintf("%s:%d", s.Host, s.Port)
	}
	return fmt.Sprintf("%s://%s:%d", s.Scheme, s.Host, s.Port)
}

type Settings struct {
	Host                      string
	Port                      int
	LiteLLMBaseURL            string
	OllamaBaseURL             string
	PostgresHost              string
	PostgresPort              int
	PostgresDB                string
	PostgresUser              string
	PostgresPassword          string
	RedisHost                 string
	RedisPort                 int
	RedisDB                   int
	ElasticsearchURL          string
	QdrantURL                 string
	APIKeyHashPepper          string
	RequestTimeoutSeconds     int
	DefaultRateLimitPerMinute int
}

func Load() (Settings, error) {
	_ = godotenv.Load()

	cfg := Settings{
		Host:                      getEnv("GATEWAY_HOST", "0.0.0.0"),
		Port:                      getEnvInt("GATEWAY_PORT", 8080),
		LiteLLMBaseURL:            getEnv("LITELLM_BASE_URL", "http://latitude:4000"),
		OllamaBaseURL:             getEnv("OLLAMA_BASE_URL", "http://promaxgb10-6116:11434"),
		PostgresHost:              getEnv("POSTGRES_HOST", "latitude"),
		PostgresPort:              getEnvInt("POSTGRES_PORT", 5432),
		PostgresDB:                getEnv("POSTGRES_DB", "openedai_gateway"),
		PostgresUser:              getEnv("POSTGRES_USER", "openedai"),
		PostgresPassword:          getEnv("POSTGRES_PASSWORD", "change-me"),
		RedisHost:                 getEnv("REDIS_HOST", "latitude"),
		RedisPort:                 getEnvInt("REDIS_PORT", 6379),
		RedisDB:                   getEnvInt("REDIS_DB", 0),
		ElasticsearchURL:          getEnv("ELASTICSEARCH_URL", "http://latitude:9200"),
		QdrantURL:                 getEnv("QDRANT_URL", "http://promaxgb10-6116:6333"),
		APIKeyHashPepper:          getEnv("API_KEY_HASH_PEPPER", "change-this-pepper"),
		RequestTimeoutSeconds:     getEnvInt("REQUEST_TIMEOUT_SECONDS", 120),
		DefaultRateLimitPerMinute: getEnvInt("DEFAULT_RATE_LIMIT_PER_MINUTE", 120),
	}

	if cfg.APIKeyHashPepper == "" {
		return Settings{}, fmt.Errorf("API_KEY_HASH_PEPPER is required")
	}

	return cfg, nil
}

func (s Settings) PostgresDSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s?sslmode=disable",
		s.PostgresUser,
		s.PostgresPassword,
		s.PostgresHost,
		s.PostgresPort,
		s.PostgresDB,
	)
}

func (s Settings) RedisAddr() string {
	return fmt.Sprintf("%s:%d", s.RedisHost, s.RedisPort)
}

func (s Settings) ServiceDiscovery() map[string]ServiceEndpoint {
	return map[string]ServiceEndpoint{
		"ollama":        {Name: "ollama", Host: "promaxgb10-6116", Port: 11434, Scheme: "http"},
		"litellm":       {Name: "litellm", Host: "latitude", Port: 4000, Scheme: "http"},
		"postgres":      {Name: "postgres", Host: "latitude", Port: 5432, Scheme: "tcp"},
		"redis":         {Name: "redis", Host: "latitude", Port: 6379, Scheme: "tcp"},
		"elasticsearch": {Name: "elasticsearch", Host: "latitude", Port: 9200, Scheme: "http"},
		"qdrant":        {Name: "qdrant", Host: "promaxgb10-6116", Port: 6333, Scheme: "http"},
	}
}

func getEnv(key, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}

func getEnvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}
