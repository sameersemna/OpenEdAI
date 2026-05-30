# Phase 2 Fast Gate Report Contract Validator Hardening (2026-05-30)

## Summary
Added explicit markdown-contract validation for fast-contract gate reports and integrated it into local parity, CI fast-gate workflow, heartbeat governance checks, and pre-upload artifact verification.

## Changes
- Added `scripts/ci/validate_fast_contract_report_markdown.sh`:
  - Enforces report contract:
    - Header format: `# Fast Contract Gate Report (YYYYMMDD-HHMMSS)`
    - Exactly one status line (`- Status: PASS|FAIL`)
    - Exactly one command line with expected command (`make test-ci-fast-contracts`)
    - Required `## Output` section with text code fence
- Added `scripts/ci/validate_fast_contract_report_markdown_selftest.sh`:
  - Positive fixture passes
  - Negative fixture (missing command line) fails
- Updated `scripts/ci/verify_fast_contract_artifacts.sh`:
  - Replaced ad-hoc status regex check with full report-contract validator
- Updated `scripts/ci/verify_fast_contract_artifacts_selftest.sh`:
  - Fixtures aligned to strict report contract
  - Added negative case for invalid command line
- Updated `Makefile`:
  - Added targets:
    - `fast-contract-report-validate-markdown`
    - `fast-contract-report-validate-selftest`
  - Wired report validation + selftest into `test-ci-fast-contract-gate-local`
- Updated `.github/workflows/health-contract.yml`:
  - Added fast-contract-gate steps:
    - Validate fast contract report markdown
    - Validate fast contract report markdown validator behavior
- Updated `.github/workflows/fast-contract-governance-heartbeat.yml`:
  - Added lightweight report validator selftest step
- Updated `scripts/ci/verify_workflow_conventions.sh`:
  - Enforced step-order and required command presence for report validator coverage
- Updated `docs/reports/ci-quick-reference.md` with new commands and flow coverage.

## Validation
- `make verify-workflow-conventions`
- `make fast-contract-report-validate-selftest`
- `make fast-contract-gate-verdict-validate-selftest`
- `make fast-contract-gate-verdict-selftest`
- `make fast-contract-artifacts-verify-selftest`
- `make test-ci-fast-contract-gate-local`
- `PRE_PUSH_CONTRACT_MODE=parity ITERATIONS=1 bash scripts/git-hooks/pre-push.example`
- `make test-phase2`
- `go test ./...`

## Evidence
- `docs/reports/20260530-222126-fast-contract-gate-report.md`
- `docs/reports/20260530-222136-fast-contract-gate-report.md`
