# Phase 2 Middleware Envelope Hardening (2026-05-30)

## Summary
This update strengthens middleware contract guarantees for authentication and admin authorization failures.

## Changes
- Added explicit JSON error envelope assertions in middleware tests for:
  - missing bearer token
  - malformed split key
  - key lookup failure
  - hash mismatch
  - expired key
  - missing admin context
  - non-admin access to admin paths
- Verified that all affected paths emit stable `error.message` and `error.type` values.

## Files
- internal/middleware/auth_test.go
- internal/middleware/admin_test.go

## Validation
- go test ./internal/middleware -count=1
- make test-phase2
- go test ./...

## Expected Impact
- Reduces regression risk for auth/admin response contracts.
- Improves confidence for downstream clients that parse standardized error envelopes.
