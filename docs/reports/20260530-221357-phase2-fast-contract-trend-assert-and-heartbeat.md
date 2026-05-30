# Phase 2 Fast Contract Trend Assert and Heartbeat (2026-05-30)

## Summary
Added enforceable fast-contract trend thresholds, artifact-verifier self-test coverage, and a lightweight weekly governance heartbeat workflow for fast-contract CI surfaces.

## Changes
- Added script: `scripts/ci/fast_contract_trend_assert.sh`
  - Enforces trend thresholds from `fast-contract-trend.json`:
    - max fail count
    - max unknown count
    - minimum pass-rate percentage
  - Uses robust JSON parsing with Python.
- Added script: `scripts/ci/verify_fast_contract_artifacts_selftest.sh`
  - Verifies `verify_fast_contract_artifacts.sh` behavior for valid and invalid synthetic inputs.
- Updated `Makefile`:
  - Added targets:
    - `fast-contract-trend-assert`
    - `fast-contract-artifacts-verify-selftest`
  - Extended `test-ci-fast-contract-gate-local` to include trend assertion and artifact-verifier self-test.
- Updated `.github/workflows/health-contract.yml`:
  - Added `Assert fast contract trend thresholds`.
  - Added `Validate fast contract artifact verifier behavior`.
- Updated `scripts/ci/verify_workflow_conventions.sh`:
  - Enforces new ordered fast-gate checks for trend assertion and verifier self-test steps.
- Added workflow: `.github/workflows/fast-contract-governance-heartbeat.yml`
  - Runs weekly and on manual dispatch.
  - Executes lightweight fast-contract governance checks:
    - workflow conventions
    - status-summary validator self-test
    - trend validator self-test
    - artifact-verifier self-test
- Updated `docs/reports/ci-quick-reference.md`:
  - Added commands for trend assertion and artifact-verifier self-test.
  - Added heartbeat workflow section.

## Validation
- `make verify-workflow-conventions`
- `make fast-contract-trend-validate-selftest`
- `make fast-contract-artifacts-verify-selftest`
- `make test-ci-fast-contract-gate-local`
- `PRE_PUSH_CONTRACT_MODE=parity ITERATIONS=1 bash scripts/git-hooks/pre-push.example`
- `make test-phase2`
- `go test ./...`

## Evidence
- `docs/reports/20260530-221307-fast-contract-gate-report.md`
- `docs/reports/20260530-221334-fast-contract-gate-report.md`
- `docs/reports/20260530-221341-fast-contract-gate-report.md`

## Notes
- Trend assertion defaults are strict (`max_fail=0`, `max_unknown=0`, `min_pass_rate=100`) and can be overridden by environment variables when needed.
