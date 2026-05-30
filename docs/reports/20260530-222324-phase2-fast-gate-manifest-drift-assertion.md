# Phase 2 Fast Gate Manifest Drift Assertion (2026-05-30)

## Summary
Added a machine-readable fast-contract gate manifest and assertion script to detect workflow-step drift against a single source of truth, then wired it into local parity, CI fast-gate checks, heartbeat governance checks, and workflow-convention enforcement.

## Changes
- Added `scripts/ci/fast_contract_gate_manifest.json`:
  - Defines expected fast-contract gate job metadata:
    - workflow path and job name
    - ordered step names
    - required run commands
- Added `scripts/ci/assert_fast_contract_gate_manifest.sh`:
  - Parses workflow YAML and manifest JSON
  - Asserts ordered step presence
  - Asserts required run command presence
- Updated `Makefile`:
  - Added target: `fast-contract-gate-manifest-assert`
  - Added manifest assertion into `test-ci-fast-contract-gate-local` before artifact verification
- Updated `.github/workflows/health-contract.yml`:
  - Added step: `Assert fast contract gate manifest conformance`
- Updated `.github/workflows/fast-contract-governance-heartbeat.yml`:
  - Added required run command: `make fast-contract-gate-manifest-assert`
- Updated `scripts/ci/verify_workflow_conventions.sh`:
  - Enforced ordered step name includes manifest assertion step
  - Enforced required run command includes manifest assertion for heartbeat
  - Enforced fast-gate run block includes manifest assertion command
- Updated `docs/reports/ci-quick-reference.md` with manifest command and coverage updates.

## Validation
- `make verify-workflow-conventions`
- `make fast-contract-gate-manifest-assert`
- `make fast-contract-report-validate-selftest`
- `make fast-contract-gate-verdict-validate-selftest`
- `make fast-contract-gate-verdict-selftest`
- `make fast-contract-artifacts-verify-selftest`
- `make test-ci-fast-contract-gate-local`
- `PRE_PUSH_CONTRACT_MODE=parity ITERATIONS=1 bash scripts/git-hooks/pre-push.example`
- `make test-phase2`
- `go test ./...`

## Evidence
- `docs/reports/20260530-222301-fast-contract-gate-report.md`
- `docs/reports/20260530-222309-fast-contract-gate-report.md`
