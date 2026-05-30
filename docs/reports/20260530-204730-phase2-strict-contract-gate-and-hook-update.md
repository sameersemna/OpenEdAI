# Phase 2 Strict Contract Gate and Pre-Push Update (2026-05-30)

## Summary
Introduced a strict fast-contract gate and aligned the sample pre-push hook with the consolidated contract gate flow.

## Changes
- Added `test-ci-fast-contracts-strict` make target.
- Updated `scripts/git-hooks/pre-push.example` to run `make test-ci-fast-contracts` as first-stage contract checks.
- Added a "Contract Gate Selection" table in CI quick reference to clarify when to use fast, strict, and full gates.

## Files
- Makefile
- scripts/git-hooks/pre-push.example
- docs/reports/ci-quick-reference.md

## Validation
- make test-ci-fast-contracts-strict
- make test-phase2
- go test ./...

## Notes
- In this environment, focused proxy usage-param tests can skip when required integration env values are absent (`API_KEY_HASH_PEPPER`).
