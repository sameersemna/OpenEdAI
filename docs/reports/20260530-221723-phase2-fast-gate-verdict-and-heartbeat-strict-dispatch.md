# Phase 2 Fast Gate Verdict and Heartbeat Strict Dispatch (2026-05-30)

## Summary
Added a compact reason-coded fast-gate verdict artifact, integrated it into local/CI fast-contract flows and summary output, and extended the heartbeat workflow with optional strict-local dispatch checks.

## Changes
- Added script: `scripts/ci/fast_contract_gate_verdict.sh`
  - Produces `fast-contract-gate-verdict.json` with:
    - overall PASS/FAIL
    - reason codes
    - observed values and thresholds
  - Uses status summary + trend data with configurable threshold inputs.
- Added script: `scripts/ci/fast_contract_gate_verdict_selftest.sh`
  - Validates PASS/FAIL verdict behavior and reason-code emission.
- Updated `Makefile`:
  - Added targets:
    - `fast-contract-gate-verdict`
    - `fast-contract-gate-verdict-selftest`
  - Extended `test-ci-fast-contract-gate-local` to generate verdict and run verdict self-test.
- Updated `.github/workflows/health-contract.yml`:
  - Added verdict generation and verdict self-test steps.
  - Uploads verdict artifact (`artifacts/contracts/fast-contract-gate-verdict.json`).
  - Appends compact summary line `Verdict: <PASS|FAIL> (<reason_codes>)` plus full verdict JSON in step summary.
- Updated `.github/workflows/fast-contract-governance-heartbeat.yml`:
  - Added optional manual dispatch input `run_strict_local_checks`.
  - Added conditional strict-local check step for manual runs.
- Updated `scripts/ci/verify_workflow_conventions.sh`:
  - Added coverage checks for:
    - verdict generation
    - verdict self-test
    - heartbeat workflow existence, weekly schedule, and required run commands.
- Updated `docs/reports/ci-quick-reference.md`:
  - Documented verdict commands, updated fast-gate coverage flow, and heartbeat strict-local dispatch option.

## Validation
- `make verify-workflow-conventions`
- `make fast-contract-gate-verdict-selftest`
- `make fast-contract-artifacts-verify-selftest`
- `make test-ci-fast-contract-gate-local`
- `PRE_PUSH_CONTRACT_MODE=parity ITERATIONS=1 bash scripts/git-hooks/pre-push.example`
- `make test-phase2`
- `go test ./...`

## Evidence
- `docs/reports/20260530-221652-fast-contract-gate-report.md`
- `docs/reports/20260530-221701-fast-contract-gate-report.md`

## Notes
- Heartbeat strict-local checks are intentionally opt-in for manual dispatch to avoid scheduled-run dependency on local backend reachability.
