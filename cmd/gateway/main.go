package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"openedai-gateway/internal/api"
	"openedai-gateway/internal/config"
	"openedai-gateway/internal/middleware"
	"openedai-gateway/internal/services"
	"openedai-gateway/internal/storage"

	"github.com/redis/go-redis/v9"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed loading config: %v", err)
	}

	ctx := context.Background()
	store, err := storage.NewPostgresStore(ctx, cfg.PostgresDSN(), storage.PoolOptions{
		MinConns:        int32(cfg.PostgresMinConns),
		MaxConns:        int32(cfg.PostgresMaxConns),
		MaxConnLifetime: time.Duration(cfg.PostgresMaxConnLifetimeSeconds) * time.Second,
	})
	if err != nil {
		log.Fatalf("failed connecting postgres: %v", err)
	}
	defer store.Close()

	requestLifecycle := middleware.NewRequestLifecycle()

	redisClient := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr(),
		Username: cfg.RedisUsername,
		Password: cfg.RedisPassword,
		DB:       cfg.RedisDB,
		PoolSize: 50,
	})
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("failed connecting redis: %v", err)
	}
	defer redisClient.Close()

	srv := &api.Server{
		Cfg:         cfg,
		Store:       store,
		RedisClient: redisClient,
		LiteLLM:     services.NewLiteLLMClient(cfg.LiteLLMBaseURL, cfg.LiteLLMTimeoutSeconds),
		Elasticsearch: services.NewElasticsearchClient(
			cfg.ElasticsearchURL,
			cfg.ElasticsearchTimeoutSeconds,
			cfg.ElasticsearchUsername,
			cfg.ElasticsearchPassword,
			cfg.ElasticsearchAPIKey,
			cfg.ElasticsearchInsecureTLS,
		),
		Qdrant:    services.NewQdrantClient(cfg.QdrantURL, cfg.QdrantTimeoutSeconds),
		Lifecycle: requestLifecycle,
	}

	router := srv.Router()
	httpServer := &http.Server{
		Addr:              fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf(
			"health policy: degraded_latency_ms=%d critical_dependencies=%v",
			cfg.ResolvedHealthDegradedLatencyMS(),
			cfg.ResolvedHealthCriticalDependencies(),
		)
		log.Printf("gateway listening on %s", httpServer.Addr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	requestLifecycle.StartShutdown()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown error: %v", err)
	}

	drainCtx, drainCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer drainCancel()
	if err := requestLifecycle.Wait(drainCtx); err != nil {
		log.Printf("request drain incomplete: %v", err)
	}
}
