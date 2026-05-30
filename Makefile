.PHONY: tidy build run migrate setup install-service test-integration test-integration-strict test-startup-config test-health-contract test-management-route-contract test-proxy-flow-contract test-proxy-usage-params-contract contract-env-status contract-env-status-json contract-env-validate-json contract-env-validate-selftest contract-env-selftest fast-contract-consistency-validate fast-contract-consistency-validate-json fast-contract-consistency-validate-selftest fast-contract-consistency-json-validate-selftest fast-contract-consistency-kpi-json fast-contract-consistency-kpi-validate-json fast-contract-consistency-kpi-validate-selftest fast-contract-consistency-kpi-assert fast-contract-consistency-kpi-assert-selftest fast-contract-consistency-reason-codes-selftest fast-contract-artifact-manifest-generate fast-contract-artifact-manifest-validate fast-contract-artifact-manifest-validate-selftest fast-contract-checksums-generate fast-contract-checksums-verify fast-contract-checksums-verify-selftest fast-contract-gate-manifest-assert fast-contract-gate-manifest-assert-selftest fast-contract-report-validate-markdown fast-contract-report-validate-selftest fast-contract-status-summary fast-contract-status-validate-json fast-contract-status-validate-selftest fast-contract-trend-json fast-contract-trend-validate-json fast-contract-trend-validate-selftest fast-contract-trend-assert fast-contract-gate-verdict fast-contract-gate-verdict-validate-json fast-contract-gate-verdict-validate-selftest fast-contract-gate-verdict-selftest fast-contract-artifacts-verify fast-contract-artifacts-verify-selftest test-ci-fast-contracts-preflight test-ci-fast-contracts test-ci-fast-contracts-strict test-ci-fast-contracts-strict-local test-ci-fast-contracts-report test-ci-fast-contract-gate-local test-ci-fast-proxy-usage test-prepush-local test-prepush-parity-local test-proxy-operational test-proxy-quick-local test-proxy-gate-local test-proxy-operational-flake test-race test-phase2-unit test-phase2-contract test-phase2-race test-phase2-runtime test-phase2 bench-health bench-api-errors bench-middleware bench-assert bench-assert-stable bench-assert-json bench-compare-json bench-compare-self test-ci-fast test-ci-strict test-ci-all governance-ci-fast ci-check-matrix ci-local-status smoke-gateway-local smoke-gateway-auth report-generate-local-smoke report-generate-local-smoke-auth report-latest-summary report-latest-summary-json report-compare-latest report-compare-latest-json report-trend-last report-trend-last-json report-trend-assert report-guard report-guard-auth report-guard-all report-guard-all-json report-guard-all-assert report-health-dashboard-json report-health-dashboard-json-lean report-policy-overview-json report-policy-selftest report-prune report-prune-assert report-prune-assert-json verify-workflow-conventions verify-governance-artifacts verify-governance-artifacts-selftest install-shellcheck-linux install-prepush-hook install-prepush-hook-dry-run install-prepush-hook-force shellcheck-scripts

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

test-management-route-contract:
	go test ./internal/api -run 'TestManagementRoute' -count=1

test-phase2-unit:
	go test ./internal/config ./internal/api ./internal/middleware ./internal/services -run 'TestLoad|TestRAGSearchResponseStatus|TestRAGSearchHandlerStatusContract|TestRAGIndexHandlerContract|TestRAGBackendError|TestCreateAPIKey|TestListAPIKeys|TestUsageSummary|TestRevokeAPIKey|TestRotateAPIKey|TestManagementRoute|TestRateLimitMiddleware|TestAdminMiddleware|TestAuthMiddleware|TestLiteLLM|TestElasticsearch|TestQdrant' -count=1

test-phase2-contract:
	go test ./tests/integration -run 'TestGatewayStartupRejects|TestRAGFlowWithSplitKey|TestAPIKeyManagementLifecycle|TestProxyFlowWithSplitKey' -count=1

test-phase2-race:
	go test -race ./internal/config ./internal/api ./internal/middleware ./internal/services -run 'TestLoad|TestRAGSearchResponseStatus|TestRAGSearchHandlerStatusContract|TestRAGIndexHandlerContract|TestCreateAPIKey|TestListAPIKeys|TestUsageSummary|TestRevokeAPIKey|TestRotateAPIKey|TestManagementRoute|TestRateLimitMiddleware|TestAdminMiddleware|TestAuthMiddleware|TestLiteLLM|TestElasticsearch|TestQdrant' -count=1

test-phase2-runtime: smoke-gateway-local smoke-gateway-auth

test-phase2: test-phase2-unit test-phase2-contract test-phase2-race

test-proxy-flow-contract:
	go test ./tests/integration -run TestProxyFlowWithSplitKey -count=1 -v

test-proxy-usage-params-contract:
	go test ./tests/integration -run 'TestProxyFlowWithSplitKey/(usage_summary_.*fallback|usage_summary_.*boundary_validation)' -count=1 -v

contract-env-status:
	bash scripts/ci/check_contract_gate_env.sh status

contract-env-status-json:
	bash scripts/ci/check_contract_gate_env.sh status-json

contract-env-validate-json:
	bash scripts/ci/validate_contract_env_status_json.sh "$${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}"

contract-env-validate-selftest:
	bash scripts/ci/validate_contract_env_status_json_selftest.sh

contract-env-selftest:
	bash scripts/ci/check_contract_gate_env_selftest.sh

fast-contract-consistency-validate:
	bash scripts/ci/validate_fast_contract_consistency.sh "$${FAST_CONTRACT_REPORT:?set FAST_CONTRACT_REPORT}" "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}" "$${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}"

fast-contract-consistency-validate-json:
	bash scripts/ci/validate_fast_contract_consistency_json.sh "$${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}"

fast-contract-consistency-validate-selftest:
	bash scripts/ci/validate_fast_contract_consistency_selftest.sh

fast-contract-consistency-json-validate-selftest:
	bash scripts/ci/validate_fast_contract_consistency_json_selftest.sh

fast-contract-consistency-kpi-json:
	bash scripts/ci/fast_contract_consistency_kpi_json.sh "$${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}" "$${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}"

fast-contract-consistency-kpi-validate-json:
	bash scripts/ci/validate_fast_contract_consistency_kpi_json.sh "$${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}"

fast-contract-consistency-kpi-validate-selftest:
	bash scripts/ci/validate_fast_contract_consistency_kpi_json_selftest.sh

fast-contract-consistency-kpi-assert:
	bash scripts/ci/assert_fast_contract_consistency_kpi.sh "$${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}" "$${FAST_CONTRACT_EXPECTED_CONSISTENCY_PASS:-1}" "$${FAST_CONTRACT_EXPECTED_GATE_PASS:-1}" "$${FAST_CONTRACT_MAX_REASON_COUNT:-0}"

fast-contract-consistency-kpi-assert-selftest:
	bash scripts/ci/assert_fast_contract_consistency_kpi_selftest.sh

fast-contract-consistency-reason-codes-selftest:
	bash scripts/ci/validate_fast_contract_consistency_reason_codes_selftest.sh

fast-contract-artifact-manifest-generate:
	bash scripts/ci/generate_fast_contract_artifact_manifest.sh "$${FAST_CONTRACT_REPORT:?set FAST_CONTRACT_REPORT}" "$${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}" "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}" "$${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}" "$${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}" "$${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}"

fast-contract-artifact-manifest-validate:
	bash scripts/ci/validate_fast_contract_artifact_manifest.sh "$${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}"

fast-contract-artifact-manifest-validate-selftest:
	bash scripts/ci/validate_fast_contract_artifact_manifest_selftest.sh

fast-contract-checksums-generate:
	bash scripts/ci/generate_fast_contract_checksums.sh "$${FAST_CONTRACT_REPORT:?set FAST_CONTRACT_REPORT}" "$${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}" "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}" "$${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}" "$${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}" "$${FAST_CONTRACT_CHECKSUMS:-artifacts/contracts/sha256sums.txt}" "$${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}"

fast-contract-checksums-verify:
	bash scripts/ci/verify_fast_contract_checksums.sh "$${FAST_CONTRACT_CHECKSUMS:-artifacts/contracts/sha256sums.txt}" "$${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}"

fast-contract-checksums-verify-selftest:
	bash scripts/ci/verify_fast_contract_checksums_selftest.sh

fast-contract-gate-manifest-assert:
	bash scripts/ci/assert_fast_contract_gate_manifest.sh "$${FAST_CONTRACT_GATE_MANIFEST:-scripts/ci/fast_contract_gate_manifest.json}"

fast-contract-gate-manifest-assert-selftest:
	bash scripts/ci/assert_fast_contract_gate_manifest_selftest.sh

fast-contract-report-validate-markdown:
	bash scripts/ci/validate_fast_contract_report_markdown.sh "$${FAST_CONTRACT_REPORT:?set FAST_CONTRACT_REPORT}"

fast-contract-report-validate-selftest:
	bash scripts/ci/validate_fast_contract_report_markdown_selftest.sh

fast-contract-status-summary:
	bash scripts/ci/fast_contract_status_summary.sh "$${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}" "$${FAST_CONTRACT_REPORT:-}" "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}"

fast-contract-status-validate-json:
	bash scripts/ci/validate_fast_contract_status_summary_json.sh "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}"

fast-contract-status-validate-selftest:
	bash scripts/ci/validate_fast_contract_status_summary_json_selftest.sh

fast-contract-trend-json:
	bash scripts/ci/fast_contract_trend_json.sh "$${FAST_CONTRACT_TREND_LIMIT:-10}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}"

fast-contract-trend-validate-json:
	bash scripts/ci/validate_fast_contract_trend_json.sh "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}"

fast-contract-trend-validate-selftest:
	bash scripts/ci/validate_fast_contract_trend_json_selftest.sh

fast-contract-trend-assert:
	bash scripts/ci/fast_contract_trend_assert.sh "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_MAX_FAIL:-0}" "$${FAST_CONTRACT_MAX_UNKNOWN:-0}" "$${FAST_CONTRACT_MIN_PASS_RATE:-100}"

fast-contract-gate-verdict:
	bash scripts/ci/fast_contract_gate_verdict.sh "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}" "$${FAST_CONTRACT_MAX_FAIL:-0}" "$${FAST_CONTRACT_MAX_UNKNOWN:-0}" "$${FAST_CONTRACT_MIN_PASS_RATE:-100}"

fast-contract-gate-verdict-validate-json:
	bash scripts/ci/validate_fast_contract_gate_verdict_json.sh "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}"

fast-contract-gate-verdict-validate-selftest:
	bash scripts/ci/validate_fast_contract_gate_verdict_json_selftest.sh

fast-contract-gate-verdict-selftest:
	bash scripts/ci/fast_contract_gate_verdict_selftest.sh

fast-contract-artifacts-verify:
	bash scripts/ci/verify_fast_contract_artifacts.sh "$${FAST_CONTRACT_REPORT:?set FAST_CONTRACT_REPORT}" "$${CONTRACT_ENV_JSON:-artifacts/contracts/contract-env-status.json}" "$${FAST_CONTRACT_STATUS_SUMMARY:-artifacts/contracts/fast-contract-status-summary.json}" "$${FAST_CONTRACT_TREND_JSON:-artifacts/contracts/fast-contract-trend.json}" "$${FAST_CONTRACT_VERDICT_JSON:-artifacts/contracts/fast-contract-gate-verdict.json}" "$${FAST_CONTRACT_CONSISTENCY_JSON:-artifacts/contracts/fast-contract-consistency-status.json}" "$${FAST_CONTRACT_CONSISTENCY_KPI_JSON:-artifacts/contracts/fast-contract-consistency-kpi.json}" "$${FAST_CONTRACT_CHECKSUMS:-artifacts/contracts/sha256sums.txt}" "$${FAST_CONTRACT_ARTIFACT_MANIFEST:-artifacts/contracts/fast-contract-artifact-manifest.json}"

fast-contract-artifacts-verify-selftest:
	bash scripts/ci/verify_fast_contract_artifacts_selftest.sh

test-ci-fast-contracts-preflight:
	bash scripts/ci/check_contract_gate_env.sh fast

test-ci-fast-contracts: test-ci-fast-contracts-preflight test-health-contract test-management-route-contract test-proxy-usage-params-contract

test-ci-fast-contracts-strict:
	FAST_CONTRACTS_REQUIRE_INTEGRATION_ENV=1 INTEGRATION_STRICT_BACKENDS=1 $(MAKE) test-ci-fast-contracts

test-ci-fast-contracts-strict-local:
	bash scripts/ci/check_contract_gate_env.sh strict-local
	API_KEY_HASH_PEPPER="$${API_KEY_HASH_PEPPER:?set API_KEY_HASH_PEPPER}" $(MAKE) test-ci-fast-contracts-strict

test-ci-fast-contracts-report:
	@set -e; \
	ts="$$(date +%Y%m%d-%H%M%S)"; \
	out="docs/reports/$${ts}-fast-contract-gate-report.md"; \
	logfile="$$(mktemp)"; \
	status="PASS"; \
	if ! $(MAKE) test-ci-fast-contracts >"$$logfile" 2>&1; then status="FAIL"; fi; \
	{ \
		echo "# Fast Contract Gate Report ($$ts)"; \
		echo; \
		echo "- Status: $$status"; \
		echo "- Command: make test-ci-fast-contracts"; \
		echo; \
		echo "## Output"; \
		echo '```text'; \
		cat "$$logfile"; \
		echo '```'; \
	} > "$$out"; \
	rm -f "$$logfile"; \
	echo "[contracts][report] wrote $$out"; \
	if [ "$$status" = "FAIL" ]; then exit 1; fi

test-ci-fast-contract-gate-local:
	@set -e; \
	mkdir -p artifacts/contracts; \
	$(MAKE) contract-env-status-json > artifacts/contracts/contract-env-status.json; \
	$(MAKE) contract-env-validate-json CONTRACT_ENV_JSON=artifacts/contracts/contract-env-status.json; \
	$(MAKE) contract-env-validate-selftest; \
	$(MAKE) contract-env-selftest; \
	$(MAKE) test-ci-fast-contracts-report; \
	latest_report="$$(ls -1t docs/reports/*-fast-contract-gate-report.md | head -1)"; \
	$(MAKE) fast-contract-report-validate-markdown FAST_CONTRACT_REPORT="$$latest_report"; \
	$(MAKE) fast-contract-report-validate-selftest; \
	$(MAKE) fast-contract-status-summary CONTRACT_ENV_JSON=artifacts/contracts/contract-env-status.json FAST_CONTRACT_REPORT="$$latest_report" FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json; \
	$(MAKE) fast-contract-status-validate-json FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json; \
	$(MAKE) fast-contract-status-validate-selftest; \
	$(MAKE) fast-contract-trend-json FAST_CONTRACT_TREND_LIMIT=$${FAST_CONTRACT_TREND_LIMIT:-10} FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json; \
	$(MAKE) fast-contract-trend-validate-json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json; \
	$(MAKE) fast-contract-trend-assert FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_MAX_FAIL=$${FAST_CONTRACT_MAX_FAIL:-0} FAST_CONTRACT_MAX_UNKNOWN=$${FAST_CONTRACT_MAX_UNKNOWN:-0} FAST_CONTRACT_MIN_PASS_RATE=$${FAST_CONTRACT_MIN_PASS_RATE:-100}; \
	$(MAKE) fast-contract-gate-verdict FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json FAST_CONTRACT_MAX_FAIL=$${FAST_CONTRACT_MAX_FAIL:-0} FAST_CONTRACT_MAX_UNKNOWN=$${FAST_CONTRACT_MAX_UNKNOWN:-0} FAST_CONTRACT_MIN_PASS_RATE=$${FAST_CONTRACT_MIN_PASS_RATE:-100}; \
	$(MAKE) fast-contract-gate-verdict-validate-json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json; \
	$(MAKE) fast-contract-trend-validate-selftest; \
	$(MAKE) fast-contract-gate-verdict-validate-selftest; \
	$(MAKE) fast-contract-gate-verdict-selftest; \
	$(MAKE) fast-contract-artifacts-verify-selftest; \
	$(MAKE) fast-contract-consistency-validate-selftest; \
	$(MAKE) fast-contract-consistency-json-validate-selftest; \
	$(MAKE) fast-contract-consistency-kpi-validate-selftest; \
	$(MAKE) fast-contract-consistency-kpi-assert-selftest; \
	$(MAKE) fast-contract-consistency-reason-codes-selftest; \
	$(MAKE) fast-contract-artifact-manifest-validate-selftest; \
	$(MAKE) fast-contract-checksums-verify-selftest; \
	$(MAKE) fast-contract-gate-manifest-assert-selftest; \
	$(MAKE) fast-contract-gate-manifest-assert; \
	$(MAKE) fast-contract-consistency-validate FAST_CONTRACT_REPORT="$$latest_report" FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json FAST_CONTRACT_CONSISTENCY_JSON=artifacts/contracts/fast-contract-consistency-status.json; \
	$(MAKE) fast-contract-consistency-validate-json FAST_CONTRACT_CONSISTENCY_JSON=artifacts/contracts/fast-contract-consistency-status.json; \
	$(MAKE) fast-contract-consistency-kpi-json FAST_CONTRACT_CONSISTENCY_JSON=artifacts/contracts/fast-contract-consistency-status.json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json FAST_CONTRACT_CONSISTENCY_KPI_JSON=artifacts/contracts/fast-contract-consistency-kpi.json; \
	$(MAKE) fast-contract-consistency-kpi-validate-json FAST_CONTRACT_CONSISTENCY_KPI_JSON=artifacts/contracts/fast-contract-consistency-kpi.json; \
	$(MAKE) fast-contract-consistency-kpi-assert FAST_CONTRACT_CONSISTENCY_KPI_JSON=artifacts/contracts/fast-contract-consistency-kpi.json FAST_CONTRACT_EXPECTED_CONSISTENCY_PASS=1 FAST_CONTRACT_EXPECTED_GATE_PASS=1 FAST_CONTRACT_MAX_REASON_COUNT=0; \
	$(MAKE) fast-contract-artifact-manifest-generate FAST_CONTRACT_REPORT="$$latest_report" CONTRACT_ENV_JSON=artifacts/contracts/contract-env-status.json FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json FAST_CONTRACT_CONSISTENCY_JSON=artifacts/contracts/fast-contract-consistency-status.json FAST_CONTRACT_CONSISTENCY_KPI_JSON=artifacts/contracts/fast-contract-consistency-kpi.json FAST_CONTRACT_ARTIFACT_MANIFEST=artifacts/contracts/fast-contract-artifact-manifest.json; \
	$(MAKE) fast-contract-artifact-manifest-validate FAST_CONTRACT_ARTIFACT_MANIFEST=artifacts/contracts/fast-contract-artifact-manifest.json; \
	$(MAKE) fast-contract-checksums-generate FAST_CONTRACT_REPORT="$$latest_report" CONTRACT_ENV_JSON=artifacts/contracts/contract-env-status.json FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json FAST_CONTRACT_CONSISTENCY_JSON=artifacts/contracts/fast-contract-consistency-status.json FAST_CONTRACT_CONSISTENCY_KPI_JSON=artifacts/contracts/fast-contract-consistency-kpi.json FAST_CONTRACT_CHECKSUMS=artifacts/contracts/sha256sums.txt FAST_CONTRACT_ARTIFACT_MANIFEST=artifacts/contracts/fast-contract-artifact-manifest.json; \
	$(MAKE) fast-contract-checksums-verify FAST_CONTRACT_CHECKSUMS=artifacts/contracts/sha256sums.txt FAST_CONTRACT_ARTIFACT_MANIFEST=artifacts/contracts/fast-contract-artifact-manifest.json; \
	$(MAKE) fast-contract-artifacts-verify FAST_CONTRACT_REPORT="$$latest_report" CONTRACT_ENV_JSON=artifacts/contracts/contract-env-status.json FAST_CONTRACT_STATUS_SUMMARY=artifacts/contracts/fast-contract-status-summary.json FAST_CONTRACT_TREND_JSON=artifacts/contracts/fast-contract-trend.json FAST_CONTRACT_VERDICT_JSON=artifacts/contracts/fast-contract-gate-verdict.json FAST_CONTRACT_CONSISTENCY_JSON=artifacts/contracts/fast-contract-consistency-status.json FAST_CONTRACT_CONSISTENCY_KPI_JSON=artifacts/contracts/fast-contract-consistency-kpi.json FAST_CONTRACT_CHECKSUMS=artifacts/contracts/sha256sums.txt FAST_CONTRACT_ARTIFACT_MANIFEST=artifacts/contracts/fast-contract-artifact-manifest.json

test-ci-fast-proxy-usage: test-health-contract test-proxy-usage-params-contract

test-prepush-local: test-ci-fast-proxy-usage
	$(MAKE) test-proxy-gate-local ITERATIONS=$${ITERATIONS:-2}

test-prepush-parity-local:
	$(MAKE) test-prepush-local ITERATIONS=$${ITERATIONS:-2}
	$(MAKE) test-ci-fast-contract-gate-local

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
