# Phase 2 Commit Split Plan

This plan breaks the current Phase 2 work into review-friendly commits while preserving bisectability and minimizing merge risk.

## Commit 1: Config Hardening and Startup Validation

### Files
- `internal/config/config.go`
- `internal/config/config_test.go`
- `tests/integration/startup_config_validation_test.go`

### Scope
- Fail-fast strict validation behavior.
- URL and timeout validation.
- Startup integration checks for strict-mode failures.

### Verification
- `go test ./internal/config -count=1`
- `go test ./tests/integration -run 'TestGatewayStartupRejects' -count=1`

## Commit 2: RAG API Status Semantics and Contracts

### Files
- `internal/api/server.go`
- `internal/api/server_error_test.go`
- `internal/api/rag_search_contract_test.go`
- `internal/api/rag_index_contract_test.go`
- `tests/integration/rag_flow_test.go`

### Scope
- RAG search status mapping (`200/206/502`).
- RAG backend error envelope assertions.
- Handler-level contracts for rag index/search.

### Verification
- `go test ./internal/api -run 'TestRAG' -count=1`
- `go test ./tests/integration -run 'TestRAGFlowWithSplitKey' -count=1`

## Commit 3: Auth/Rate/Admin Middleware Hardening and Tests

### Files
- `internal/middleware/auth.go`
- `internal/middleware/auth_test.go`
- `internal/middleware/rate_limit_test.go`
- `internal/middleware/admin_test.go`

### Scope
- Auth middleware test seam.
- Defensive inactive/expired checks.
- Rate-limit and admin middleware contract coverage.

### Verification
- `go test ./internal/middleware -count=1`
- `go test -race ./internal/middleware -count=1`

## Commit 4: Service Testability and Client Tests

### Files
- `internal/services/contracts.go`
- `internal/services/litellm_test.go`
- `internal/services/elasticsearch_test.go`
- `internal/services/qdrant_test.go`

### Scope
- Service interfaces for API dependency inversion.
- Client tests for LiteLLM/Elasticsearch/Qdrant behavior.

### Verification
- `go test ./internal/services -count=1`
- `go test -race ./internal/services -count=1`

## Commit 5: Integration Lifecycle/Boundary Expansion

### Files
- `tests/integration/api_key_management_test.go`
- `tests/integration/helpers_test.go`
- `tests/integration/proxy_flow_test.go`

### Scope
- API key revoke/rotate edge cases.
- Usage window boundary with timestamped logs.
- Helper extension for seeded timestamps.

### Verification
- `go test ./tests/integration -run 'TestAPIKeyManagementLifecycle|TestProxyFlowWithSplitKey' -count=1`

## Commit 6: Plan and Quality Gates

### Files
- `docs/plans/Plan_Phase2.md`
- `docs/plans/Phase2_Commit_Split.md`
- `Makefile`

### Scope
- Phase 2 execution plan docs.
- Focused phase-2 unit/contract/race/runtime targets.

### Verification
- `make test-phase2`
- `make test-phase2-runtime`

## Final Pre-Push Checklist
1. `make test-phase2`
2. `make test-phase2-runtime`
3. `go test ./...`
4. `git status --short` to ensure only intended files are staged

## Suggested Staging Commands

Use these command groups to stage logically coherent commits.

### Commit 1
`git add internal/config/config.go internal/config/config_test.go tests/integration/startup_config_validation_test.go`

### Commit 2
`git add internal/api/server.go internal/api/server_error_test.go internal/api/rag_search_contract_test.go internal/api/rag_index_contract_test.go tests/integration/rag_flow_test.go internal/api/errors.go internal/api/management_contract_test.go`

### Commit 3
`git add internal/middleware/auth.go internal/middleware/auth_test.go internal/middleware/admin_test.go internal/middleware/rate_limit_test.go`

### Commit 4
`git add internal/services/contracts.go internal/services/litellm_test.go internal/services/elasticsearch_test.go internal/services/qdrant_test.go`

### Commit 5
`git add tests/integration/api_key_management_test.go tests/integration/helpers_test.go tests/integration/proxy_flow_test.go`

### Commit 6
`git add Makefile docs/plans/Plan_Phase2.md docs/plans/Phase2_Commit_Split.md`
