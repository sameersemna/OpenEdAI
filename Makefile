.PHONY: tidy build run migrate setup install-service test-integration test-integration-strict test-startup-config test-health-contract test-proxy-flow-contract test-proxy-usage-params-contract test-ci-fast-proxy-usage test-prepush-local test-proxy-operational test-proxy-quick-local test-proxy-gate-local test-proxy-operational-flake test-race test-phase2-unit test-phase2-contract test-phase2-race test-phase2-runtime test-phase2 bench-health bench-api-errors bench-middleware bench-assert bench-assert-stable bench-assert-json bench-compare-json bench-compare-self test-ci-fast test-ci-strict test-ci-all governance-ci-fast ci-check-matrix ci-local-status smoke-gateway-local smoke-gateway-auth report-generate-local-smoke report-generate-local-smoke-auth report-latest-summary report-latest-summary-json report-compare-latest report-compare-latest-json report-trend-last report-trend-last-json report-trend-assert report-guard report-guard-auth report-guard-all report-guard-all-json report-guard-all-assert report-health-dashboard-json report-health-dashboard-json-lean report-policy-overview-json report-policy-selftest report-prune report-prune-assert report-prune-assert-json verify-workflow-conventions verify-governance-artifacts verify-governance-artifacts-selftest install-shellcheck-linux install-prepush-hook install-prepush-hook-dry-run install-prepush-hook-force shellcheck-scripts

tidy:
	go mod tidy

build:
	go build -o openedai-gateway ./cmd/gateway

run:
	go run ./cmd/gateway

migrate:
	psql "$${DATABASE_URL}" -f migrations/001_init.sql

setup:
	bash scripts/setup.sh

install-service:
	bash scripts/install_service.sh

test-integration:
	go test ./tests/integration -count=1

test-integration-strict:
	INTEGRATION_STRICT_BACKENDS=1 go test ./tests/integration -count=1

test-startup-config:
	go test ./tests/integration -run 'TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestGatewayStartupRejectsUnsafeDefaultPepperInStrictMode' -count=1

test-health-contract:
	go test ./internal/config -run 'TestLoadRejectsNegativeHealthDegradedLatency|TestLoadFallsBackForMalformedHealthDegradedLatency|TestLoadStrictValidationRejectsUnsafeDefaultPepper|TestLoadRejectsMalformedServiceURLs|TestLoadRejectsNonPositiveRequestTimeout' -count=1
	go test ./tests/integration -run 'TestHealthzContract|TestGatewayStartupRejectsNegativeHealthDegradedLatency|TestIntegrationStrictBackends' -count=1

test-phase2-unit:
	go test ./internal/config ./internal/api ./internal/middleware ./internal/services -run 'TestLoad|TestRAGSearchResponseStatus|TestRAGSearchHandlerStatusContract|TestRAGIndexHandlerContract|TestRAGBackendError|TestCreateAPIKey|TestListAPIKeys|TestUsageSummary|TestRevokeAPIKey|TestRotateAPIKey|TestRateLimitMiddleware|TestAdminMiddleware|TestAuthMiddleware|TestLiteLLM|TestElasticsearch|TestQdrant' -count=1

test-phase2-contract:
	go test ./tests/integration -run 'TestGatewayStartupRejects|TestRAGFlowWithSplitKey|TestAPIKeyManagementLifecycle|TestProxyFlowWithSplitKey' -count=1

test-phase2-race:
	go test -race ./internal/config ./internal/api ./internal/middleware ./internal/services -run 'TestLoad|TestRAGSearchResponseStatus|TestRAGSearchHandlerStatusContract|TestRAGIndexHandlerContract|TestCreateAPIKey|TestListAPIKeys|TestUsageSummary|TestRevokeAPIKey|TestRotateAPIKey|TestRateLimitMiddleware|TestAdminMiddleware|TestAuthMiddleware|TestLiteLLM|TestElasticsearch|TestQdrant' -count=1

test-phase2-runtime: smoke-gateway-local smoke-gateway-auth

test-phase2: test-phase2-unit test-phase2-contract test-phase2-race

test-proxy-flow-contract:
	go test ./tests/integration -run TestProxyFlowWithSplitKey -count=1 -v

test-proxy-usage-params-contract:
	go test ./tests/integration -run 'TestProxyFlowWithSplitKey/(usage_summary_.*fallback|usage_summary_.*boundary_validation)' -count=1 -v

test-ci-fast-proxy-usage: test-health-contract test-proxy-usage-params-contract

test-prepush-local: test-ci-fast-proxy-usage
	$(MAKE) test-proxy-gate-local ITERATIONS=$${ITERATIONS:-2}

test-proxy-operational:
	go test ./tests/integration -run TestProxyOperationalFlow -count=1 -v

test-proxy-quick-local: test-proxy-flow-contract test-proxy-operational

test-proxy-gate-local: test-proxy-quick-local
	$(MAKE) test-proxy-operational-flake ITERATIONS=$${ITERATIONS:-5}

test-proxy-operational-flake:
	bash scripts/ci/run_proxy_operational_flake_check.sh "$${ITERATIONS:-5}"

test-race:
	go test -race ./...

bench-health:
	go test -bench BenchmarkHealthHandler -benchmem ./internal/api

bench-api-errors:
	go test -bench 'BenchmarkRenderAPIError|BenchmarkRAGBackendError' -benchmem ./internal/api

bench-middleware:
	go test -bench BenchmarkRequestIDMiddleware -benchmem ./internal/middleware

bench-assert:
	bash scripts/ci/benchmark_assert.sh

bench-assert-stable:
	BENCH_ASSERT_REPEAT=$${BENCH_ASSERT_REPEAT:-3} bash scripts/ci/benchmark_assert.sh

bench-assert-json:
	@BENCH_ASSERT_OUTPUT=json bash scripts/ci/benchmark_assert.sh

bench-compare-json:
	@bash scripts/ci/benchmark_compare_json.sh "$${BASELINE_BENCH_JSON:?set BASELINE_BENCH_JSON}" "$${CURRENT_BENCH_JSON:?set CURRENT_BENCH_JSON}"

bench-compare-self:
	@bash scripts/ci/benchmark_compare_self.sh

test-ci-fast: test-health-contract

test-ci-strict: test-health-contract
	INTEGRATION_STRICT_BACKENDS=1 go test ./tests/integration -count=1

test-ci-all:
	$(MAKE) test-health-contract
	INTEGRATION_STRICT_BACKENDS=1 go test ./tests/integration -count=1
	$(MAKE) test-race

governance-ci-fast:
	$(MAKE) verify-workflow-conventions
	$(MAKE) report-policy-selftest

ci-check-matrix:
	bash scripts/ci/describe_checks.sh

ci-local-status:
	bash scripts/ci/check_local_tools.sh

smoke-gateway-local:
	bash scripts/ci/smoke_gateway.sh

smoke-gateway-auth:
	bash scripts/ci/smoke_gateway_auth.sh

report-generate-local-smoke:
	bash scripts/ci/report_generate_local_smoke.sh

report-generate-local-smoke-auth:
	bash scripts/ci/report_generate_local_smoke_auth.sh

report-latest-summary:
	bash scripts/ci/report_latest_smoke_summary.sh

report-latest-summary-json:
	bash scripts/ci/report_latest_smoke_summary_json.sh

report-compare-latest:
	bash scripts/ci/report_compare_latest.sh

report-compare-latest-json:
	bash scripts/ci/report_compare_latest_json.sh

report-trend-last:
	bash scripts/ci/report_trend_last.sh

report-trend-last-json:
	bash scripts/ci/report_trend_last_json.sh

report-trend-assert:
	bash scripts/ci/report_trend_assert.sh "$${TREND_LIMIT:-5}" "$${MAX_FAIL:-0}" "$${MAX_UNKNOWN:-0}" "$${MIN_PASS_RATE:-100}"

report-guard:
	bash scripts/ci/report_guard.sh

report-guard-auth:
	bash scripts/ci/report_guard_auth.sh

report-guard-all:
	bash scripts/ci/report_guard_all.sh

report-guard-all-json:
	bash scripts/ci/report_guard_all_json.sh

report-guard-all-assert:
	bash scripts/ci/report_guard_all_assert.sh "$${EXPECTED_OVERALL:-PASS}" "$${EXPECTED_AUTH_MODE:-ANY}"

report-health-dashboard-json:
	bash scripts/ci/report_health_dashboard_json.sh

report-health-dashboard-json-lean:
	DASHBOARD_LEAN=1 bash scripts/ci/report_health_dashboard_json.sh

report-policy-overview-json:
	bash scripts/ci/report_policy_overview_json.sh

report-policy-selftest:
	bash scripts/ci/report_policy_selftest.sh

report-prune:
	bash scripts/ci/report_prune_reports.sh "$${KEEP_STANDARD:-20}" "$${KEEP_AUTH:-20}"

report-prune-assert:
	bash scripts/ci/report_prune_assert.sh

report-prune-assert-json:
	bash scripts/ci/report_prune_assert_json.sh

verify-workflow-conventions:
	bash scripts/ci/verify_workflow_conventions.sh

verify-governance-artifacts:
	bash scripts/ci/verify_artifact_bundle.sh "$${ARTIFACT_DIR:-artifacts}" "$${BUNDLE_MODE:-auto}"

verify-governance-artifacts-selftest:
	bash scripts/ci/verify_artifact_bundle_selftest.sh

install-shellcheck-linux:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck already installed"; \
	elif command -v apt-get >/dev/null 2>&1; then \
		echo "installing shellcheck via apt-get (requires sudo)"; \
		sudo apt-get update && sudo apt-get install -y shellcheck; \
	else \
		echo "unsupported platform: install shellcheck manually"; \
		exit 1; \
	fi

install-prepush-hook:
	bash scripts/git-hooks/install_pre_push.sh

install-prepush-hook-dry-run:
	bash scripts/git-hooks/install_pre_push.sh --dry-run

install-prepush-hook-force:
	bash scripts/git-hooks/install_pre_push.sh --force

shellcheck-scripts:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/ci/*.sh scripts/git-hooks/*.sh scripts/git-hooks/*.example; \
	else \
		echo "shellcheck not installed; skipping script lint"; \
	fi
