# OpenEdAI Gateway (Go)

OpenAI-compatible API gateway for LAN-hosted LiteLLM/Ollama with:
- Bearer API key validation from PostgreSQL
- Per-key token usage logging to PostgreSQL
- Redis-backed rate limiting
- RAG endpoints over Elasticsearch + Qdrant

## LAN Topology
- Ollama: http://promaxgb10-6116:11434
- LiteLLM: http://latitude:11435
- PostgreSQL: latitude:5432
- Redis: latitude:6379
- Elasticsearch: https://latitude:9200 (security enabled)
- Qdrant: http://promaxgb10-6116:6333

## Quick Start
1. Copy `.env.example` to `.env` and fill credentials.
   - For secured Elasticsearch, set `ELASTICSEARCH_URL`, `ELASTICSEARCH_USERNAME`/`ELASTICSEARCH_PASSWORD` or `ELASTICSEARCH_API_KEY`, and `ELASTICSEARCH_INSECURE_SKIP_VERIFY=true` if using self-signed certs.
2. Run connectivity checks:
   - `bash scripts/setup.sh`
3. Apply schema:
   - `set -a && source .env && set +a`
   - `PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f migrations/001_init.sql`
4. Build and run:
   - `go mod tidy`
   - `go run ./cmd/gateway`

## Create API Key
- Generate a client key and hash:
  - `go run ./cmd/keygen --name your-key-name`
- Insert resulting hash into table `api_keys`.

## Service Endpoints
- `POST /v1/chat/completions` (proxy to LiteLLM)
- `POST /v1/completions` (proxy to LiteLLM)
- `POST /v1/rag/index`
- `POST /v1/rag/search`
- `GET /v1/management/api-keys` (masked key metadata)
- `GET /v1/management/usage` (per-key usage summary + recent logs)
- `GET /healthz`
- `GET /livez`
- `GET /discovery`

`/healthz` now returns structured telemetry for postgres, redis, litellm, and elasticsearch, including per-dependency latency in milliseconds and reachability state, plus local host metrics for disk, memory, and CPU.
The response also includes a compact `health_policy` object with the effective degraded-latency threshold and resolved critical dependencies.
For compatibility, `critical_dependencies` remains as a top-level sorted array.

`/livez` is a process-only liveness endpoint that returns `200` while the gateway is serving requests, regardless of upstream dependency state.

Example response:

```json
{
   "status": "degraded",
   "health_policy": {
      "degraded_latency_ms": 2000,
      "critical_dependencies": ["postgres", "redis"]
   },
   "critical_dependencies": ["postgres", "redis"],
   "dependencies": {
      "postgres": {
         "status": "healthy",
         "reachable": true,
         "latency_ms": 12
      },
      "litellm": {
         "status": "degraded",
         "reachable": true,
         "latency_ms": 2450
      }
   },
   "host_metrics": {
      "hostname": "promaxgb10-6116",
      "disk_usage_percent": 61.4,
      "memory_used_mb": 18492,
      "memory_total_mb": 64183,
      "cpu_utilization_percent": 23.8
   }
}
```

HTTP status mapping:
- `200` for `healthy` and `degraded`
- `503` for `unhealthy`

Liveness mapping:
- `/livez` returns `200` with `{ "status": "healthy" }` when the gateway process is up

Threshold configuration:
- `HEALTH_DEGRADED_LATENCY_MS` controls when a reachable dependency is reported as `degraded`
- Default: `2000` milliseconds
- Malformed/non-integer values currently fall back to default (`2000`); negative values fail startup validation.
- `HEALTH_CRITICAL_DEPENDENCIES` controls which unreachable dependencies force overall `unhealthy`
- Default: `postgres,redis,litellm,elasticsearch`

Integration test mode:
- By default, integration tests skip when LiteLLM/RAG backends are unavailable in local dev.
- Set `INTEGRATION_STRICT_BACKENDS=1` to make those cases fail instead, which is useful for CI environments where all backends are expected to be up.
- GitHub Actions strict backend checks are opt-in via repository variable `RUN_STRICT_BACKEND_TESTS=true` or manual workflow dispatch input `run_strict_backends=true`.
- Recommended branch protection: require the `health-contract-fast` status check for pull requests into `main`.
- Strict backend checks are also available in a scheduled/manual workflow: `.github/workflows/health-contract-strict-nightly.yml`.
- Local smoke/report gate automation is available as a manual self-hosted workflow: `.github/workflows/local-smoke-report-guard.yml`.
- Convenience targets:
   - `make governance-ci-fast` (runs governance workflow convention checks plus governance policy self-test)
   - `make test-ci-fast` (matches the `health-contract-fast` workflow job)
   - `make test-prepush-local` (simulates the sample pre-push path: fast proxy-usage checks + local gate)
   - `make test-ci-strict` (matches strict CI workflow jobs)
   - `make test-ci-all` (runs fast + strict parity checks in sequence)
   - `make smoke-gateway-local` (rebuild + restart + /livez + /healthz + unauthorized auth check)
   - `make smoke-gateway-auth` (same as local smoke, but requires `GATEWAY_TEST_API_KEY` and enforces authorized management check)
       - If `GATEWAY_TEST_API_KEY` is missing or invalid, the script attempts a one-time temporary admin key bootstrap in Postgres for local CI smoke.
   - `make report-generate-local-smoke` (runs local release checks and writes a timestamped report under `docs/reports/`)
   - `make report-generate-local-smoke-auth` (same as above, but enforces authenticated smoke checks and writes an auth report)
   - `make report-latest-summary` (prints compact pass/fail summary from latest local smoke report)
   - `make report-latest-summary-json` (prints machine-readable JSON summary from latest local smoke report)
   - `make report-compare-latest` (compares checklist results between the newest two smoke reports)
   - `make report-compare-latest-json` (machine-readable drift comparison between the newest two smoke reports)
   - `make report-trend-last` (prints a compact table for recent smoke report outcomes)
   - `make report-trend-last-json` (prints machine-readable trend data including per-report overall status and aggregate pass/fail/unknown summary)
   - `make report-guard` (fails when latest summary is not PASS or latest two reports show drift)
   - `make report-guard-auth` (fails unless latest auth smoke report exists and all auth checks pass)
   - `make report-guard-all` (enforces standard guard and adds auth guard automatically when auth reports are present)
   - `make report-guard-all-json` (prints one machine-readable JSON status for standard plus conditional auth gating)
   - `make report-guard-all-assert` (asserts expected combined gate status; defaults to PASS/ANY)
   - `make report-guard-all-assert EXPECTED_OVERALL=PASS EXPECTED_AUTH_MODE=ENFORCED` (strict mode when auth evidence must be present)
   - `make report-health-dashboard-json` (prints one compact JSON payload that merges latest summary, latest drift, trend, and combined guard status)
   - `make report-health-dashboard-json-lean` (prints a lean dashboard payload that omits duplicated top-level prune policy data)
   - `make report-policy-overview-json` (prints one governance JSON payload combining trend threshold policy status and prune policy status)
   - `make report-policy-selftest` (runs a regression self-test for governance pass/fail behavior across trend and prune policies)
   - `make report-prune` (retains recent reports and removes older ones; defaults `KEEP_STANDARD=20 KEEP_AUTH=20`, supports `DRY_RUN=1`)
   - `make report-prune-assert` (fails when report inventory exceeds policy limits; defaults `MAX_STANDARD_TOTAL=200 MAX_AUTH_TOTAL=200`, optional age controls `MAX_STANDARD_AGE_DAYS` and `MAX_AUTH_AGE_DAYS`, `-1` disables)
   - `make report-prune-assert-json` (prints prune policy status as machine-readable JSON only)
   - `make verify-workflow-conventions` (verifies governance workflows still enforce helper usage, upload steps, and retention policy)
   - `make verify-governance-artifacts ARTIFACT_DIR=/path/to/artifacts [BUNDLE_MODE=auto|smoke|selftest]` (verifies checksum integrity and validates status-summary fields from a downloaded governance artifact bundle)
   - `make verify-governance-artifacts-selftest` (runs positive/negative self-tests for artifact bundle verification rules)
   - `make test-integration`
   - `make test-integration-strict`
   - `make test-startup-config` (asserts invalid health threshold values fail fast at startup)
   - `make test-health-contract` (runs focused config+health contract checks)

CI operations:
- Enable strict checks on demand in the main workflow by setting repository variable `RUN_STRICT_BACKEND_TESTS=true`.
- Keep branch protection lightweight for pull requests by requiring only `health-contract-fast` on `main`.
- Use `.github/workflows/health-contract-strict-nightly.yml` for ongoing strict backend signal without blocking normal PR flow.
- Run `make ci-check-matrix` to print a local summary of fast vs strict CI checks.
- Run `make ci-local-status` to see whether required local tooling (go/make/git/shellcheck) is available.
- Optional pre-push hook template is available at `scripts/git-hooks/pre-push.example` (copy to `.git/hooks/pre-push` and make it executable if you want automatic local parity checks before push).
- Optional installer for the pre-push hook: `make install-prepush-hook` (supports dry-run with `bash scripts/git-hooks/install_pre_push.sh --dry-run`).
- Additional hook installer shortcuts: `make install-prepush-hook-dry-run` and `make install-prepush-hook-force`.
- Optional script lint: `make shellcheck-scripts` (skips automatically if `shellcheck` is not installed).
- Debian/Ubuntu helper to install shellcheck locally: `make install-shellcheck-linux`.
- CI runbook summary is available at `docs/reports/ci-quick-reference.md`.
- Record local release checklist runs in timestamped reports under `docs/reports/`.
- Script lint workflow (`.github/workflows/script-lint.yml`) runs shellcheck automatically when scripts or workflows change.
- Governance policy self-test workflow (`.github/workflows/governance-policy-selftest.yml`) runs weekly and on manual dispatch to exercise governance regression checks independently.
- Governance workflow conventions workflow (`.github/workflows/governance-workflow-conventions.yml`) runs weekly, on relevant pull request changes, and on manual dispatch; it enforces both `make verify-workflow-conventions` and `make report-policy-selftest`.
- Governance policy self-test workflow uploads downloadable artifacts (`policy-selftest.log`, `policy-overview.json`, `artifact-manifest.json`, `status-summary.json`, `sha256sums.txt`) with 14-day retention and writes a concise run summary.
- Local smoke report guard workflow (`.github/workflows/local-smoke-report-guard.yml`) generates two local smoke reports and enforces `make report-guard` on self-hosted runners.
- Local smoke auth report guard workflow (`.github/workflows/local-smoke-report-guard-auth.yml`) generates two auth smoke reports and enforces `make report-guard-auth` on self-hosted runners (requires repository secret `GATEWAY_TEST_API_KEY`).
- Both local smoke guard workflows also print `make report-guard-all-json` for one combined machine-readable gate result.
- Both local smoke guard workflows also print `make report-trend-last-json` for machine-readable rolling trend diagnostics.
- Both local smoke guard workflows also enforce `make report-trend-assert` for default rolling trend quality thresholds.
- Both local smoke guard workflows also print `make report-policy-overview-json` for unified governance policy status.
- Both local smoke guard workflows also print `make report-health-dashboard-json` for external dashboards/alerts by default, including policy overview and prune policy status.
- Both local smoke guard workflows expose an optional `dashboard_lean` manual dispatch input that switches the workflow output to `make report-health-dashboard-json-lean`.
- Both local smoke guard workflows expose an optional `run_policy_selftest` manual dispatch input that runs `make report-policy-selftest` after the smoke-report governance checks complete.
- Both local smoke guard workflows upload governance JSON artifacts (`latest-summary.json`, `latest-drift.json`, `trend.json`, `combined-guard.json`, `policy-overview.json`, `dashboard.json`, `prune-policy.json`) plus `artifact-manifest.json`, `status-summary.json`, and `sha256sums.txt` with 14-day retention, and write a concise run summary.
- Governance workflows use `scripts/ci/workflow_artifact_manifest.sh` to generate artifact manifests and step summaries consistently (`smoke` and `selftest` modes).
- Governance workflow structure checks are available via `scripts/ci/verify_workflow_conventions.sh` (`make verify-workflow-conventions`) and include checksum-generation, pre-upload bundle validation, and governance conventions schedule enforcement.
- Governance artifact bundle verification is available via `scripts/ci/verify_artifact_bundle.sh` (`make verify-governance-artifacts`) and validates both checksum integrity and status summary readability/required fields (`BUNDLE_MODE=auto|smoke|selftest`).
- Both local smoke guard workflows also run `DRY_RUN=1 make report-prune` so retention impact is visible without deleting artifacts.
- Both local smoke guard workflows also enforce `make report-prune-assert` so report inventory growth breaches fail fast, with explicit default policy env values (`MAX_STANDARD_TOTAL=200`, `MAX_AUTH_TOTAL=200`, `MAX_STANDARD_AGE_DAYS=-1`, `MAX_AUTH_AGE_DAYS=-1`).
- Both local smoke guard workflows expose manual dispatch inputs for trend and prune policy tuning plus dashboard and governance verification controls (`trend_limit`, `max_fail`, `max_unknown`, `min_pass_rate`, `max_standard_total`, `max_auth_total`, `max_standard_age_days`, `max_auth_age_days`, `dashboard_lean`, `run_policy_selftest`).
- `make report-policy-selftest` now creates its own synthetic legacy report fixture for age-policy assertions, so it no longer depends on one hardcoded timestamped report file.

## Always-On Local Service (systemd)
- User-level service (no sudo):
   - `bash scripts/install_user_service.sh`
   - `systemctl --user status openedai-gateway.service`
   - Optional machine-boot autostart (one-time root action): `sudo loginctl enable-linger $USER`
- System-wide service (requires sudo):
  - `bash scripts/install_service.sh`
  - `systemctl status openedai-gateway.service`

Startup diagnostics:
- On boot, the gateway logs the resolved health policy as:
   - `health policy: degraded_latency_ms=<value> critical_dependencies=[...]`
- This reflects the effective values after fallback/default resolution.
