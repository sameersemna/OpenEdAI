# Phase 2 Fast Gate Verdict Schema Hardening (2026-05-30)

## Summary
Hardened fast-contract artifact governance by adding explicit schema validation for `fast-contract-gate-verdict.json` and enforcing it in local parity, CI workflow checks, heartbeat governance checks, and pre-upload artifact verification.

## Changes
- Added `scripts/ci/validate_fast_contract_gate_verdict_json.sh`:
  - Validates verdict payload shape and value constraints:
    - required top-level keys
    - workflow identity
    - `overall` enum (`PASS|FAIL`)
    - `reason_codes` non-empty string array
    - threshold numeric bounds
    - observed field presence and bounds
    - PASS/FAIL and reason-code consistency (`PASS -> ["none"]`, `FAIL -> no "none"`)
- Added `scripts/ci/validate_fast_contract_gate_verdict_json_selftest.sh`:
  - Positive fixture passes
  - Negative fixture intentionally fails PASS/reason-code consistency
- Updated `Makefile`:
  - Added targets:
    - `fast-contract-gate-verdict-validate-json`
    - `fast-contract-gate-verdict-validate-selftest`
  - Updated `fast-contract-artifacts-verify` target to pass verdict JSON path
  - Updated `test-ci-fast-contract-gate-local` to run verdict validation and validator self-test before artifact verification
- Updated `scripts/ci/verify_fast_contract_artifacts.sh`:
  - Added verdict artifact as required input
  - Added verdict schema validation invocation
- Updated `scripts/ci/verify_fast_contract_artifacts_selftest.sh`:
  - Added synthetic verdict fixture and verifier argument coverage
- Updated `.github/workflows/health-contract.yml` (`fast-contract-gate` job):
  - Added step to validate verdict JSON
  - Added step to validate verdict JSON validator behavior
  - Passed verdict path into pre-upload artifact verifier step
- Updated `.github/workflows/fast-contract-governance-heartbeat.yml`:
  - Added lightweight weekly/manual verdict JSON validator self-test check
- Updated `scripts/ci/verify_workflow_conventions.sh`:
  - Enforced ordered workflow step presence for verdict JSON validation and validator self-test
  - Enforced heartbeat required command includes `make fast-contract-gate-verdict-validate-selftest`
- Updated `docs/reports/ci-quick-reference.md` with new commands and coverage notes.

## Validation
- `make verify-workflow-conventions`
- `make fast-contract-gate-verdict-validate-selftest`
- `make fast-contract-gate-verdict-selftest`
- `make fast-contract-artifacts-verify-selftest`
- `make test-ci-fast-contract-gate-local`
- `PRE_PUSH_CONTRACT_MODE=parity ITERATIONS=1 bash scripts/git-hooks/pre-push.example`
- `make test-phase2`
- `go test ./...`

## Evidence
- `docs/reports/20260530-221907-fast-contract-gate-report.md`
- `docs/reports/20260530-221914-fast-contract-gate-report.md`
