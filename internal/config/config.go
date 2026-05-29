package config

import (
	"fmt"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type ServiceEndpoint struct {
	Name   string `json:"name"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
	Scheme string `json:"scheme"`
}

const defaultCriticalDependencies = "postgres,redis,litellm,elasticsearch"
const defaultHealthDegradedLatencyMS = 2000

func DefaultCriticalDependencies() string {
	return defaultCriticalDependencies
}

func (s Settings) ResolvedHealthDegradedLatencyMS() int {
	if s.HealthDegradedLatencyMS <= 0 {
		return defaultHealthDegradedLatencyMS
	}
	return s.HealthDegradedLatencyMS
}

func (s Settings) ResolvedHealthCriticalDependencies() []string {
	policy := strings.TrimSpace(s.HealthCriticalDependencies)
	if policy == "" {
		policy = defaultCriticalDependencies
	}

	set := map[string]struct{}{}
	for _, name := range strings.Split(policy, ",") {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		set[name] = struct{}{}
	}

	list := make([]string, 0, len(set))
	for name := range set {
		list = append(list, name)
	}
	sort.Strings(list)
	return list
}

func (s ServiceEndpoint) BaseURL() string {
	if s.Scheme == "tcp" {
		return fmt.Sprintf("%s:%d", s.Host, s.Port)
	}
	return fmt.Sprintf("%s://%s:%d", s.Scheme, s.Host, s.Port)
}

type Settings struct {
	Host                       string
	Port                       int
	HealthDegradedLatencyMS    int
	HealthCriticalDependencies string
	LiteLLMBaseURL             string
	OllamaBaseURL              string
	PostgresHost               string
	PostgresPort               int
	PostgresDB                 string
	PostgresUser               string
	PostgresPassword           string
	RedisHost                  string
	RedisPort                  int
	RedisDB                    int
	RedisUsername              string
	RedisPassword              string
	RedisKeyPrefix             string
	ElasticsearchURL           string
	ElasticsearchUsername      string
	ElasticsearchPassword      string
	ElasticsearchAPIKey        string
	ElasticsearchInsecureTLS   bool
	QdrantURL                  string
	APIKeyHashPepper           string
	RequestTimeoutSeconds      int
	DefaultRateLimitPerMinute  int
}

func Load() (Settings, error) {
	_ = godotenv.Load()

	cfg := Settings{
		Host:                       getEnv("GATEWAY_HOST", "0.0.0.0"),
		Port:                       getEnvInt("GATEWAY_PORT", 8080),
		HealthDegradedLatencyMS:    getEnvInt("HEALTH_DEGRADED_LATENCY_MS", defaultHealthDegradedLatencyMS),
		HealthCriticalDependencies: getEnv("HEALTH_CRITICAL_DEPENDENCIES", defaultCriticalDependencies),
		LiteLLMBaseURL:             getEnv("LITELLM_BASE_URL", "http://latitude:11435"),
		OllamaBaseURL:              getEnv("OLLAMA_BASE_URL", "http://promaxgb10-6116:11434"),
		PostgresHost:               getEnv("POSTGRES_HOST", "latitude"),
		PostgresPort:               getEnvInt("POSTGRES_PORT", 5432),
		PostgresDB:                 getEnv("POSTGRES_DB", "openedai_gateway"),
		PostgresUser:               getEnv("POSTGRES_USER", "openedai"),
		PostgresPassword:           getEnv("POSTGRES_PASSWORD", "change-me"),
		RedisHost:                  getEnv("REDIS_HOST", "latitude"),
		RedisPort:                  getEnvInt("REDIS_PORT", 6379),
		RedisDB:                    getEnvInt("REDIS_DB", 0),
		RedisUsername:              getEnv("REDIS_USERNAME", ""),
		RedisPassword:              getEnv("REDIS_PASSWORD", ""),
		RedisKeyPrefix:             getEnv("REDIS_KEY_PREFIX", "openedai"),
		ElasticsearchURL:           getEnv("ELASTICSEARCH_URL", "http://latitude:9200"),
		ElasticsearchUsername:      getEnv("ELASTICSEARCH_USERNAME", ""),
		ElasticsearchPassword:      getEnv("ELASTICSEARCH_PASSWORD", ""),
		ElasticsearchAPIKey:        getEnv("ELASTICSEARCH_API_KEY", ""),
		ElasticsearchInsecureTLS:   getEnvBool("ELASTICSEARCH_INSECURE_SKIP_VERIFY", false),
		QdrantURL:                  getEnv("QDRANT_URL", "http://promaxgb10-6116:6333"),
		APIKeyHashPepper:           getEnv("API_KEY_HASH_PEPPER", "change-this-pepper"),
		RequestTimeoutSeconds:      getEnvInt("REQUEST_TIMEOUT_SECONDS", 120),
		DefaultRateLimitPerMinute:  getEnvInt("DEFAULT_RATE_LIMIT_PER_MINUTE", 120),
	}

	if cfg.APIKeyHashPepper == "" {
		return Settings{}, fmt.Errorf("API_KEY_HASH_PEPPER is required")
	}
	if cfg.HealthDegradedLatencyMS < 0 {
		return Settings{}, fmt.Errorf("HEALTH_DEGRADED_LATENCY_MS must be >= 0")
	}

	if cfg.ElasticsearchUsername == "" {
		cfg.ElasticsearchUsername = getEnv("KIBANA_USERNAME", "")
	}
	if cfg.ElasticsearchPassword == "" {
		cfg.ElasticsearchPassword = getEnv("KIBANA_PASSWORD", "")
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
	litellmHost, litellmPort, litellmScheme := parseBaseURL(s.LiteLLMBaseURL, "latitude", 11435, "http")
	ollamaHost, ollamaPort, ollamaScheme := parseBaseURL(s.OllamaBaseURL, "promaxgb10-6116", 11434, "http")
	elasticHost, elasticPort, elasticScheme := parseBaseURL(s.ElasticsearchURL, "latitude", 9200, "http")
	qdrantHost, qdrantPort, qdrantScheme := parseBaseURL(s.QdrantURL, "promaxgb10-6116", 6333, "http")

	return map[string]ServiceEndpoint{
		"ollama":        {Name: "ollama", Host: ollamaHost, Port: ollamaPort, Scheme: ollamaScheme},
		"litellm":       {Name: "litellm", Host: litellmHost, Port: litellmPort, Scheme: litellmScheme},
		"postgres":      {Name: "postgres", Host: "latitude", Port: 5432, Scheme: "tcp"},
		"redis":         {Name: "redis", Host: "latitude", Port: 6379, Scheme: "tcp"},
		"elasticsearch": {Name: "elasticsearch", Host: elasticHost, Port: elasticPort, Scheme: elasticScheme},
		"qdrant":        {Name: "qdrant", Host: qdrantHost, Port: qdrantPort, Scheme: qdrantScheme},
	}
}

func parseBaseURL(raw string, fallbackHost string, fallbackPort int, fallbackScheme string) (string, int, string) {
	if raw == "" {
		return fallbackHost, fallbackPort, fallbackScheme
	}

	u, err := url.Parse(raw)
	if err != nil {
		return fallbackHost, fallbackPort, fallbackScheme
	}

	host := u.Hostname()
	if host == "" {
		host = fallbackHost
	}

	scheme := strings.ToLower(u.Scheme)
	if scheme == "" {
		scheme = fallbackScheme
	}

	port := fallbackPort
	if p := u.Port(); p != "" {
		if n, err := strconv.Atoi(p); err == nil {
			port = n
		}
	}

	return host, port, scheme
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

func getEnvBool(key string, fallback bool) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	switch v {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}
