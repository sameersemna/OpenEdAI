# OpenEdAI Phase 2 Plan (2-Day Vibe Coding Sprint)

## Objective
Deliver a balanced, incremental hardening sprint across security, API behavior consistency, testability, and quality gates in 2 days, with clear ownership so Agent mode can execute in parallel.

## Scope
- In scope:
  - Fail-fast config hardening for unsafe/malformed settings.
  - API error-contract consistency, especially RAG partial-failure semantics.
  - Minimal dependency inversion (service interfaces) that unlocks tests.
  - High-risk test expansion (auth, rate limit, startup config, service/storage paths).
  - Focused CI/Make targets and critical regression checks.
- Out of scope:
  - Full architectural rewrite of handler layer.
  - Full secrets platform migration (Vault rollout).
  - Full observability stack migration.

## Work Lanes and Ownership
1. Agent A: Security and config fail-fast.
2. Agent B: API contract consistency and error mapping.
3. Agent C: Service interfaces and resilience hooks.
4. Agent D: Test expansion and CI quality gates.
5. Agent Lead: Integration, release checks, and risk closure.

## Day 1 Plan

### Phase 0 (Kickoff, 60-90 min)
1. Capture baseline behavior for:
   - `/livez`
   - `/healthz`
   - authenticated proxy path
   - RAG index/search flow
2. Create a short baseline note in report format.
3. Confirm merge cadence every 2-3 hours and freeze non-critical additions.

### Phase 1 (Day 1 AM): Security and config fail-fast (Agent A)
1. Harden config loading in `internal/config/config.go`:
   - reject insecure defaults in strict mode
   - reject malformed upstream URLs
   - reject non-positive timeout values
   - keep health policy contract behavior intact
2. Extend tests:
   - `internal/config/config_test.go`
   - `tests/integration/startup_config_validation_test.go`
3. Success criteria:
   - invalid config fails at startup
   - existing healthy startup paths unchanged

### Phase 2 (Day 1 PM): API consistency (Agent B)
1. Normalize RAG partial-failure semantics in `internal/api/server.go`.
2. Centralize error mapping in `internal/api/errors.go`.
3. Preserve `/healthz` status mapping and payload contract in `internal/api/health.go`.
4. Add/extend contract coverage:
   - `tests/integration/rag_flow_test.go`
   - `tests/integration/proxy_flow_test.go`
   - `tests/integration/healthz_contract_test.go`
5. Success criteria:
   - clients can detect full failure vs partial failure reliably
   - no health contract regressions

## Day 2 Plan

### Phase 3 (Day 2 AM): Testability and resilience (Agent C)
1. Introduce minimal interfaces for:
   - LiteLLM
   - Elasticsearch
   - Qdrant
2. Wire through server dependencies with minimal surface change.
3. Add bounded retry/backoff hooks for transient failures (config-driven).
4. Add high-risk tests:
   - `internal/middleware/auth_test.go`
   - `internal/middleware/rate_limit_test.go`
   - `internal/services/litellm_test.go`
   - `internal/services/elasticsearch_test.go`
   - `internal/storage/postgres_test.go`
5. Success criteria:
   - no behavior regressions in existing flows
   - improved ability to unit test backend integrations

### Phase 4 (Day 2 PM): CI quality gates and integration (Agent D + Lead)
1. Add focused targets in `Makefile`:
   - phase-2 targeted tests
   - race checks for critical packages
2. Keep existing smoke/governance commands green.
3. Execute integration checklist:
   - rebuild and restart service
   - verify `/livez` and `/healthz`
   - verify auth behavior on management endpoints
   - verify proxy flow
   - verify RAG flow with partial failure simulation
4. Publish closure summary:
   - risks closed
   - residual risks
   - deferred items for Phase 3+

## Task Board (Ready for Agent Mode)

### P1 Critical
1. Fail-fast config hardening (Agent A).
2. RAG partial-failure status semantics (Agent B).
3. Startup validation tests for hardened config (Agent A).

### P2 High
1. Error contract normalization (Agent B).
2. Auth/rate-limit edge-case tests (Agent C).
3. Service/storage risk-path tests (Agent C).

### P3 Medium
1. Minimal retry/backoff hooks (Agent C).
2. Focused race/flake checks in make targets (Agent D).

## Verification Matrix
1. Config hardening:
   - invalid values fail startup with clear error.
2. API contract:
   - proxy, RAG, and health endpoints emit consistent status/error semantics.
3. Regression safety:
   - existing health contract and smoke flows remain green.
4. Test quality:
   - newly added high-risk tests pass and are deterministic.

## Risks and Mitigations
1. Risk: stricter validation may break existing local envs.
   - Mitigation: gate strict checks by explicit strict mode env for local transition.
2. Risk: partial-failure status changes may impact existing clients.
   - Mitigation: keep response body shape backward-compatible while changing status semantics.
3. Risk: 2-day scope overrun.
   - Mitigation: drop optional resilience extras before dropping critical validation and contract fixes.

## Definition of Done
1. P1 tasks merged and validated.
2. P2 tests added and green.
3. Service restart and core endpoint checks pass.
4. Plan execution summary published with follow-on backlog for next sprint.
