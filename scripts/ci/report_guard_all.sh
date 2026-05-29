#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

bash scripts/ci/report_guard.sh

if ls docs/reports/*-local-release-smoke-auth.md >/dev/null 2>&1; then
  echo "[guard-all] auth report detected; enforcing auth guard"
  bash scripts/ci/report_guard_auth.sh
else
  echo "[guard-all] no auth report detected; skipping auth guard"
  echo "[guard-all] hint: run make report-generate-local-smoke-auth to include auth evidence"
fi
