#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
OpenEdAI CI Check Matrix

Fast PR check (health-contract-fast):
  make test-ci-fast
  - internal config validation tests
  - healthz contract integration test
  - startup config rejection integration test
  - strict-mode parser integration test

Strict backend check (health-contract-strict / nightly strict):
  make test-ci-strict
  - full integration suite with INTEGRATION_STRICT_BACKENDS=1
  - backend outages become failures instead of skips

Combined local run:
  make test-ci-all
  - fast parity checks
  - strict parity checks

Governance quick check:
  make governance-ci-fast
  - workflow convention verification
  - governance policy self-test regression

Useful local commands:
  make test-startup-config
  make test-health-contract
  make test-ci-all
  make smoke-gateway-local
  make smoke-gateway-auth
  make report-generate-local-smoke
  make report-generate-local-smoke-auth
  make report-latest-summary
  make report-latest-summary-json
  make report-compare-latest
  make report-compare-latest-json
  make report-trend-last
  make report-trend-last-json
  make report-trend-assert
  make report-guard
  make report-guard-auth
  make report-guard-all
  make report-guard-all-json
  make report-guard-all-assert
  make report-health-dashboard-json
  make report-health-dashboard-json-lean
  make report-policy-overview-json
  make report-policy-selftest
  make report-prune
  make report-prune-assert
  make report-prune-assert-json
  make verify-workflow-conventions
  make verify-governance-artifacts
  make verify-governance-artifacts-selftest
  make governance-ci-fast
  make test-integration
  make test-integration-strict

Manual self-hosted workflows:
  .github/workflows/local-smoke-report-guard.yml
  .github/workflows/local-smoke-report-guard-auth.yml

Governance workflows:
  .github/workflows/governance-policy-selftest.yml
  .github/workflows/governance-workflow-conventions.yml
EOF
