package api

import (
	"context"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/mem"
)

const (
	healthStatusHealthy   = "healthy"
	healthStatusDegraded  = "degraded"
	healthStatusUnhealthy = "unhealthy"

	healthProbeTimeout        = 3 * time.Second
	degradedLatencyThreshold  = 2 * time.Second
	defaultHealthCacheTTL     = 5 * time.Second
	cpuSamplingWindow         = 200 * time.Millisecond
	hostMetricCollectionLimit = 500 * time.Millisecond
)

type cachedHealth struct {
	response   HealthResponse
	httpStatus int
	expiresAt  time.Time
}

type HealthResponse struct {
	Status               string                      `json:"status"`
	HealthPolicy         HealthPolicy                `json:"health_policy"`
	CriticalDependencies []string                    `json:"critical_dependencies"`
	Dependencies         map[string]DependencyHealth `json:"dependencies"`
	HostMetrics          HostMetrics                 `json:"host_metrics"`
}

type HealthPolicy struct {
	DegradedLatencyMS    int      `json:"degraded_latency_ms"`
	CriticalDependencies []string `json:"critical_dependencies"`
}

type DependencyHealth struct {
	Status    string `json:"status"`
	Reachable bool   `json:"reachable"`
	LatencyMS int64  `json:"latency_ms"`
	Error     string `json:"error,omitempty"`
}

type HostMetrics struct {
	Hostname              string   `json:"hostname"`
	DiskUsagePercent      float64  `json:"disk_usage_percent"`
	MemoryUsedMB          uint64   `json:"memory_used_mb"`
	MemoryTotalMB         uint64   `json:"memory_total_mb"`
	CPUUtilizationPercent float64  `json:"cpu_utilization_percent"`
	CollectionErrors      []string `json:"collection_errors,omitempty"`
}

type healthProbe func(context.Context) error

type LivenessResponse struct {
	Status string `json:"status"`
}

func (s *Server) live(c *gin.Context) {
	c.JSON(http.StatusOK, LivenessResponse{Status: healthStatusHealthy})
}

func (s *Server) health(c *gin.Context) {
	if s.healthCacheEnabled() {
		if cached, ok := s.cachedHealthResponse(); ok {
			c.JSON(cached.httpStatus, cached.response)
			return
		}
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), healthProbeTimeout)
	defer cancel()

	probes := s.healthProbes()

	dependencies := make(map[string]DependencyHealth, len(probes))
	var mu sync.Mutex
	var wg sync.WaitGroup

	for name, probe := range probes {
		wg.Add(1)
		go func(name string, probe healthProbe) {
			defer wg.Done()
			result := runHealthProbe(ctx, probe, s.degradedLatencyThreshold())

			mu.Lock()
			dependencies[name] = result
			mu.Unlock()
		}(name, probe)
	}

	hostMetrics := s.collectHostMetrics(ctx)
	wg.Wait()

	status := deriveOverallHealth(dependencies, hostMetrics, s.criticalDependencies())
	httpStatus := http.StatusOK
	if status == healthStatusUnhealthy {
		httpStatus = http.StatusServiceUnavailable
	}
	resolvedCritical := s.criticalDependencyList()

	response := HealthResponse{
		Status: status,
		HealthPolicy: HealthPolicy{
			DegradedLatencyMS:    s.Cfg.ResolvedHealthDegradedLatencyMS(),
			CriticalDependencies: resolvedCritical,
		},
		CriticalDependencies: resolvedCritical,
		Dependencies:         dependencies,
		HostMetrics:          hostMetrics,
	}

	if s.healthCacheEnabled() {
		s.setCachedHealthResponse(response, httpStatus)
	}
	c.JSON(httpStatus, response)
}

func (s *Server) healthCacheEnabled() bool {
	if s.Cfg.HealthCacheDisabled {
		return false
	}
	return s.healthCacheTTL() > 0
}

func (s *Server) healthCacheTTL() time.Duration {
	if s.Cfg.HealthCacheTTLMS <= 0 {
		return defaultHealthCacheTTL
	}
	return time.Duration(s.Cfg.HealthCacheTTLMS) * time.Millisecond
}

func (s *Server) cachedHealthResponse() (cachedHealth, bool) {
	s.healthCacheMu.RLock()
	defer s.healthCacheMu.RUnlock()

	if s.healthCache == nil {
		return cachedHealth{}, false
	}
	if time.Now().After(s.healthCache.expiresAt) {
		return cachedHealth{}, false
	}

	return *s.healthCache, true
}

func (s *Server) setCachedHealthResponse(response HealthResponse, httpStatus int) {
	s.healthCacheMu.Lock()
	defer s.healthCacheMu.Unlock()

	s.healthCache = &cachedHealth{
		response:   response,
		httpStatus: httpStatus,
		expiresAt:  time.Now().Add(s.healthCacheTTL()),
	}
}

func (s *Server) healthProbes() map[string]healthProbe {
	if s.healthProbesOverride != nil {
		return s.healthProbesOverride
	}

	return map[string]healthProbe{
		"postgres":      s.probePostgres,
		"redis":         s.probeRedis,
		"litellm":       s.probeLiteLLM,
		"elasticsearch": s.probeElasticsearch,
	}
}

func (s *Server) collectHostMetrics(ctx context.Context) HostMetrics {
	if s.hostMetricsOverride != nil {
		return s.hostMetricsOverride(ctx)
	}

	return collectHostMetrics(ctx)
}

func (s *Server) degradedLatencyThreshold() time.Duration {
	return time.Duration(s.Cfg.ResolvedHealthDegradedLatencyMS()) * time.Millisecond
}

func (s *Server) criticalDependencies() map[string]struct{} {
	critical := map[string]struct{}{}
	for _, name := range s.Cfg.ResolvedHealthCriticalDependencies() {
		critical[name] = struct{}{}
	}
	return critical
}

func (s *Server) criticalDependencyList() []string {
	return s.Cfg.ResolvedHealthCriticalDependencies()
}

func runHealthProbe(ctx context.Context, probe healthProbe, degradedThresholds ...time.Duration) DependencyHealth {
	startedAt := time.Now()
	err := probe(ctx)
	latencyMS := time.Since(startedAt).Milliseconds()
	degradedThreshold := degradedLatencyThreshold
	if len(degradedThresholds) > 0 {
		degradedThreshold = degradedThresholds[0]
	}

	if err != nil {
		return DependencyHealth{
			Status:    healthStatusUnhealthy,
			Reachable: false,
			LatencyMS: latencyMS,
			Error:     err.Error(),
		}
	}

	status := healthStatusHealthy
	if latencyMS > degradedThreshold.Milliseconds() {
		status = healthStatusDegraded
	}

	return DependencyHealth{
		Status:    status,
		Reachable: true,
		LatencyMS: latencyMS,
	}
}

func (s *Server) probePostgres(ctx context.Context) error {
	return s.Store.Pool.Ping(ctx)
}

func (s *Server) probeRedis(ctx context.Context) error {
	return s.RedisClient.Ping(ctx).Err()
}

func (s *Server) probeLiteLLM(ctx context.Context) error {
	return s.LiteLLM.Health(ctx)
}

func (s *Server) probeElasticsearch(ctx context.Context) error {
	return s.Elasticsearch.Health(ctx)
}

func deriveOverallHealth(dependencies map[string]DependencyHealth, hostMetrics HostMetrics, criticalSets ...map[string]struct{}) string {
	overall := healthStatusHealthy
	var critical map[string]struct{}
	if len(criticalSets) > 0 {
		critical = criticalSets[0]
	}

	for name, dependency := range dependencies {
		if dependency.Status == healthStatusUnhealthy {
			if len(critical) == 0 {
				return healthStatusUnhealthy
			}
			if _, ok := critical[name]; ok {
				return healthStatusUnhealthy
			}
			overall = healthStatusDegraded
		}
		if dependency.Status == healthStatusDegraded {
			overall = healthStatusDegraded
		}
	}

	if len(hostMetrics.CollectionErrors) > 0 {
		return healthStatusDegraded
	}

	return overall
}

func collectHostMetrics(ctx context.Context) HostMetrics {
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown"
	}

	metrics := HostMetrics{Hostname: hostname}

	if usage, err := disk.Usage("/"); err == nil {
		metrics.DiskUsagePercent = usage.UsedPercent
	} else {
		metrics.CollectionErrors = append(metrics.CollectionErrors, "disk: "+err.Error())
	}

	if virtualMemory, err := mem.VirtualMemory(); err == nil {
		metrics.MemoryUsedMB = bytesToMB(virtualMemory.Used)
		metrics.MemoryTotalMB = bytesToMB(virtualMemory.Total)
	} else {
		metrics.CollectionErrors = append(metrics.CollectionErrors, "memory: "+err.Error())
	}

	cpuCtx, cancel := context.WithTimeout(ctx, hostMetricCollectionLimit)
	defer cancel()

	if percentages, err := cpu.PercentWithContext(cpuCtx, cpuSamplingWindow, false); err == nil && len(percentages) > 0 {
		metrics.CPUUtilizationPercent = percentages[0]
	} else if err != nil {
		metrics.CollectionErrors = append(metrics.CollectionErrors, "cpu: "+err.Error())
	} else {
		metrics.CollectionErrors = append(metrics.CollectionErrors, "cpu: no samples returned")
	}

	return metrics
}

func bytesToMB(value uint64) uint64 {
	return value / (1024 * 1024)
}
