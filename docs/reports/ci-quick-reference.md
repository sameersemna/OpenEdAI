# CI Quick Reference

## Fast PR Checks
- Workflow job: `health-contract-fast`
- Local equivalent: `make test-ci-fast`
- Includes:
  - Config validation tests for health threshold parsing
  - `/healthz` contract integration test
  - Startup config validation integration test
  - Strict-mode parser integration test

## Strict Backend Checks
- Workflow job: `health-contract-strict` (opt-in in main workflow)
- Nightly workflow: `.github/workflows/health-contract-strict-nightly.yml`
- Local equivalent: `make test-ci-strict`
- Behavior:
  - Uses `INTEGRATION_STRICT_BACKENDS=1`
  - Backend outages fail tests instead of skipping

## Useful Commands
- Phase 2 consolidated quality gate: `make test-phase2`
  - Includes config, API contracts (RAG + management), middleware contracts, services contracts, integration contracts, and focused race checks.
- Show matrix: `make ci-check-matrix`
- Show local tool status: `make ci-local-status`
- Governance quick check: `make governance-ci-fast`
- Fast parity: `make test-ci-fast`
- Fast contract gate (health + management route + usage params): `make test-ci-fast-contracts`
- Fast contract gate (strict backend mode): `make test-ci-fast-contracts-strict`
- Fast contract gate (strict + local backend reachability checks): `make test-ci-fast-contracts-strict-local`
- Fast contract gate with report artifact output: `make test-ci-fast-contracts-report`
- Fast contract report markdown validation: `make fast-contract-report-validate-markdown FAST_CONTRACT_REPORT=docs/reports/<report>.md`
- Fast contract report markdown validator self-test: `make fast-contract-report-validate-selftest`
- Fast contract gate status summary artifact generation: `make fast-contract-status-summary`
- Fast contract status summary JSON validation: `make fast-contract-status-validate-json`
- Fast contract status summary validator self-test: `make fast-contract-status-validate-selftest`
- Fast contract trend JSON generation: `make fast-contract-trend-json`
- Fast contract trend JSON validation: `make fast-contract-trend-validate-json`
- Fast contract trend validator self-test: `make fast-contract-trend-validate-selftest`
- Fast contract trend threshold assertion: `make fast-contract-trend-assert`
- Fast contract gate verdict JSON generation: `make fast-contract-gate-verdict`
- Fast contract gate verdict JSON validation: `make fast-contract-gate-verdict-validate-json`
- Fast contract gate verdict JSON validator self-test: `make fast-contract-gate-verdict-validate-selftest`
- Fast contract gate verdict self-test: `make fast-contract-gate-verdict-selftest`
- Fast contract artifact pre-upload verification: `make fast-contract-artifacts-verify FAST_CONTRACT_REPORT=docs/reports/<report>.md`
- Fast contract artifact verifier self-test: `make fast-contract-artifacts-verify-selftest`
- Fast contract cross-artifact consistency validation: `make fast-contract-consistency-validate FAST_CONTRACT_REPORT=docs/reports/<report>.md`
- Fast contract consistency status JSON validation: `make fast-contract-consistency-validate-json`
- Fast contract cross-artifact consistency validator self-test: `make fast-contract-consistency-validate-selftest`
- Fast contract consistency status JSON validator self-test: `make fast-contract-consistency-json-validate-selftest`
- Fast contract consistency reason-code stability self-test: `make fast-contract-consistency-reason-codes-selftest`
- Fast contract consistency KPI JSON generation: `make fast-contract-consistency-kpi-json`
- Fast contract consistency KPI JSON validation: `make fast-contract-consistency-kpi-validate-json`
- Fast contract consistency KPI JSON validator self-test: `make fast-contract-consistency-kpi-validate-selftest`
- Fast contract consistency KPI threshold assertion: `make fast-contract-consistency-kpi-assert`
- Fast contract consistency KPI assertor self-test: `make fast-contract-consistency-kpi-assert-selftest`
- Fast contract artifact manifest generation: `make fast-contract-artifact-manifest-generate FAST_CONTRACT_REPORT=docs/reports/<report>.md`
- Fast contract artifact manifest validation: `make fast-contract-artifact-manifest-validate`
- Fast contract artifact manifest validator self-test: `make fast-contract-artifact-manifest-validate-selftest`
- Fast contract artifact manifest path integrity assertion: `make fast-contract-artifact-manifest-assert-paths`
  - Enforces lexicographically sorted file paths and normalized/unique entries.
  - Supports explicit count lock: `FAST_CONTRACT_EXPECTED_SIGNED_ARTIFACT_COUNT=<n> make fast-contract-artifact-manifest-assert-paths`.
  - Supports version-aware count map: `FAST_CONTRACT_SIGNED_ARTIFACT_COUNT_BY_VERSION=v1=7,v2=8 make fast-contract-artifact-manifest-assert-paths`.
- Fast contract artifact manifest path integrity assertion self-test: `make fast-contract-artifact-manifest-assert-paths-selftest`
- Fast contract artifact manifest version-lock self-test: `make fast-contract-artifact-manifest-version-lock-selftest`
- Fast contract signed-count version-map parser self-test: `make fast-contract-signed-count-version-map-parser-selftest`
- Fast contract signed-count lock matrix self-test: `make fast-contract-signed-count-lock-matrix-selftest`
- Fast contract signed-count lock error-message self-test: `make fast-contract-signed-count-lock-error-messages-selftest`
- Fast contract gate verdict reason-code self-test: `make fast-contract-gate-verdict-reason-codes-selftest`
- Fast contract policy fingerprint JSON generation: `make fast-contract-policy-fingerprint-json`
- Fast contract policy fingerprint JSON validation: `make fast-contract-policy-fingerprint-validate-json`
- Fast contract policy fingerprint JSON validator self-test: `make fast-contract-policy-fingerprint-validate-selftest`
- Fast contract policy fingerprint canonical serialization self-test: `make fast-contract-policy-fingerprint-canonical-selftest`
- Fast contract policy fingerprint drift self-test: `make fast-contract-policy-fingerprint-drift-selftest`
- Fast contract artifact checksum generation: `make fast-contract-checksums-generate FAST_CONTRACT_REPORT=docs/reports/<report>.md`
- Fast contract artifact checksum verification: `make fast-contract-checksums-verify`
- Fast contract artifact checksum verifier self-test: `make fast-contract-checksums-verify-selftest`
- Fast contract artifact checksum tamper-detection self-test: `make fast-contract-checksums-tamper-selftest`
- Fast contract gate manifest assertion self-test: `make fast-contract-gate-manifest-assert-selftest`
- Fast contract gate manifest conformance assertion: `make fast-contract-gate-manifest-assert`
- Full local parity run for fast-contract-gate workflow (status JSON + validator checks + report + summary): `make test-ci-fast-contract-gate-local`
- Fast parity + usage query-param contract checks: `make test-ci-fast-proxy-usage`
  - The sample `scripts/git-hooks/pre-push.example` uses this command before running `make test-proxy-gate-local`.
- Strict parity: `make test-ci-strict`
- Full parity (fast + strict): `make test-ci-all`
- Focused proxy-flow contract checks: `make test-proxy-flow-contract`
- Focused usage query-param contract checks: `make test-proxy-usage-params-contract`
- Simulate sample pre-push flow locally: `make test-prepush-local` (override gate flake count with `ITERATIONS=<n>`)
- Combined pre-push + fast-contract-gate parity run: `make test-prepush-parity-local` (override with `ITERATIONS=<n>`)
- Single operational flow check: `make test-proxy-operational`
- Combined focused + operational single-run checks: `make test-proxy-quick-local`
- High-confidence local gate (quick-local + flake): `make test-proxy-gate-local` (override flake count with `ITERATIONS=<n>`)
- Re-run the proxy operational flow for flake detection: `make test-proxy-operational-flake` (override with `ITERATIONS=<n>`)
- Local service smoke (restart + endpoint checks): `make smoke-gateway-local`
- Local service smoke with required auth check: `make smoke-gateway-auth`
  - If `GATEWAY_TEST_API_KEY` is unset (or fails), the script bootstraps a temporary admin split key in Postgres and retries once.
- Generate timestamped local smoke report: `make report-generate-local-smoke`
- Generate timestamped auth-enforced smoke report: `make report-generate-local-smoke-auth`
- Summarize latest smoke report: `make report-latest-summary`
- Summarize latest smoke report (JSON): `make report-latest-summary-json`
- Compare latest two smoke reports: `make report-compare-latest`
- Compare latest two smoke reports (JSON): `make report-compare-latest-json`
- Show trend for recent smoke reports: `make report-trend-last` (default 5)
- Show trend for recent smoke reports (JSON): `make report-trend-last-json` (default 5)
  - JSON includes per-report derived `overall` and aggregate summary (`pass`/`fail`/`unknown`, `pass_rate_percent`).
- Assert trend thresholds: `make report-trend-assert` (default: `TREND_LIMIT=5 MAX_FAIL=0 MAX_UNKNOWN=0 MIN_PASS_RATE=100`)
- Enforce report gate (PASS + NO_DRIFT): `make report-guard`
- Enforce auth report gate: `make report-guard-auth`
- Enforce standard guard + conditional auth guard: `make report-guard-all`
- Emit combined machine-readable guard result: `make report-guard-all-json`
- Assert combined guard expectations: `bash scripts/ci/report_guard_all_assert.sh [PASS|FAIL] [ANY|SKIPPED|ENFORCED]`
- Make-target assertion (override expectations): `make report-guard-all-assert EXPECTED_OVERALL=PASS EXPECTED_AUTH_MODE=ENFORCED`
- Emit compact merged dashboard payload (summary + drift + trend + guard): `make report-health-dashboard-json`
- Emit lean dashboard payload without duplicated top-level prune data: `make report-health-dashboard-json-lean`
- Emit unified governance payload (trend policy + prune policy): `make report-policy-overview-json`
- Run governance regression self-test: `make report-policy-selftest`
- Prune old smoke reports with retention limits: `make report-prune` (defaults: `KEEP_STANDARD=20 KEEP_AUTH=20`)
  - Use `DRY_RUN=1 make report-prune` to preview removals without deleting files.
- Assert report inventory policy limits: `make report-prune-assert` (defaults: `MAX_STANDARD_TOTAL=200 MAX_AUTH_TOTAL=200`)
  - Optional age limits: `MAX_STANDARD_AGE_DAYS` and `MAX_AUTH_AGE_DAYS` (`-1` disables age checks).
- Emit JSON-only report inventory policy status: `make report-prune-assert-json`
- Verify governance workflow conventions: `make verify-workflow-conventions`
- Verify expected-count workflow conventions negative fixture: `make verify-workflow-conventions-fast-contract-expected-count-selftest`
- Verify policy-fingerprint-summary workflow conventions negative fixture: `make verify-workflow-conventions-fast-contract-policy-fingerprint-summary-selftest`
- Verify policy-fingerprint-summary-order workflow conventions negative fixture: `make verify-workflow-conventions-fast-contract-policy-fingerprint-summary-order-selftest`
- Verify heartbeat canonical-command workflow conventions negative fixture: `make verify-workflow-conventions-fast-contract-heartbeat-canonical-selftest`
- Verify heartbeat unexpected-vs-run-order priority fixture (unexpected command failure must win when run-order also drifts): `make verify-workflow-conventions-fast-contract-heartbeat-unexpected-vs-run-order-priority-selftest`
- Verify fast-contract summary error-message stability fixture: `make verify-workflow-conventions-fast-contract-summary-error-messages-selftest` (missing checksum/verdict/policy-fingerprint lines, ordering drift, and duplicate verdict line)
- Verify fast-contract summary single-fault determinism fixture: `make verify-workflow-conventions-fast-contract-summary-single-fault-selftest`
- Verify heartbeat duplicate required-command workflow conventions fixture: `make verify-workflow-conventions-fast-contract-heartbeat-duplicate-required-command-selftest`
- Verify heartbeat required-command priority fixture (missing beats duplicate): `make verify-workflow-conventions-fast-contract-heartbeat-required-command-priority-selftest`
- Verify heartbeat required-command relative order fixture: `make verify-workflow-conventions-fast-contract-heartbeat-required-command-order-selftest`
- Verify heartbeat mixed-fault priority fixture (missing beats duplicate/order, single error): `make verify-workflow-conventions-fast-contract-heartbeat-mixed-fault-priority-selftest`
- Verify heartbeat unexpected-command allowlist fixture: `make verify-workflow-conventions-fast-contract-heartbeat-unexpected-command-selftest`
- Verify heartbeat unexpected-over-missing priority fixture (unexpected beats missing, single error): `make verify-workflow-conventions-fast-contract-heartbeat-unexpected-over-missing-priority-selftest`
- Verify heartbeat step-name lock fixture (critical label drift detection): `make verify-workflow-conventions-fast-contract-heartbeat-step-name-lock-selftest`
- Verify heartbeat step-name duplicate fixture (critical label uniqueness): `make verify-workflow-conventions-fast-contract-heartbeat-step-name-duplicate-selftest`
- Verify heartbeat required-step-name order fixture (required labels must appear in canonical sequence): `make verify-workflow-conventions-fast-contract-heartbeat-required-step-name-order-selftest`
- Verify heartbeat step-name-order-vs-run-order priority fixture (step-name-order failure must win when both ordering faults exist): `make verify-workflow-conventions-fast-contract-heartbeat-step-name-order-vs-run-order-priority-selftest`
- Verify heartbeat step-name-vs-command priority fixture (unexpected command beats label drift, single error): `make verify-workflow-conventions-fast-contract-heartbeat-step-name-vs-command-priority-selftest`
- Verify heartbeat manifest schema fixture (manifest contract validation): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-selftest`
- Verify heartbeat manifest schema-version lock fixture (supported manifest versions): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-version-selftest`
- Verify heartbeat manifest top-level keys lock fixture (reject unknown manifest keys): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-keys-selftest`
- Verify heartbeat manifest keys-vs-step-name-order priority fixture (unknown key failure must win when both manifest faults exist): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-keys-vs-step-name-order-priority-selftest`
- Verify heartbeat manifest keys-vs-command-class-order priority fixture (unknown key failure must precede command-class-order fault in mixed manifests): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-keys-vs-command-class-order-priority-selftest`
- Verify heartbeat manifest run-command order lock fixture (first command and command-class order): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-run-order-selftest`
- Verify heartbeat manifest command-class order fixture (verify-workflow cannot follow fast-contract commands): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-command-class-order-selftest`
- Verify heartbeat manifest command-class priority fixture (first offending cross-class command wins deterministically): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-command-class-priority-selftest`
- Verify heartbeat manifest step-name order lock fixture (critical step-name sequence): `make verify-workflow-conventions-fast-contract-heartbeat-manifest-step-name-order-selftest`
- Verify heartbeat step-count lock fixture (manifest-backed step count): `make verify-workflow-conventions-fast-contract-heartbeat-step-count-selftest`
- Verify heartbeat make-step-name lock fixture (non-empty labels for make-run steps): `make verify-workflow-conventions-fast-contract-heartbeat-make-step-name-selftest`
- Verify heartbeat verify-block contiguous lock fixture (verify-workflow commands must remain before fast-contract commands): `make verify-workflow-conventions-fast-contract-heartbeat-verify-block-contiguous-selftest`
- Run artifact verifier self-test (includes expected failures): `make verify-governance-artifacts-selftest`
- Startup validation only: `make test-startup-config`
- Focused health contract: `make test-health-contract`
- Focused management route contracts (auth + read-only store errors): `make test-management-route-contract`
- Contract environment status snapshot: `make contract-env-status`
- Contract environment status snapshot (JSON): `make contract-env-status-json`
- Contract environment status JSON validation: `make contract-env-validate-json`
- Contract environment status JSON validator self-test: `make contract-env-validate-selftest`
- Contract environment status self-test (JSON + strict failure semantics): `make contract-env-selftest`
- Pre-push hook install (interactive): `make install-prepush-hook`
- Pre-push hook install dry-run: `make install-prepush-hook-dry-run`
- Pre-push hook install force: `make install-prepush-hook-force`
- Script lint: `make shellcheck-scripts`
- Install shellcheck on Debian/Ubuntu: `make install-shellcheck-linux`

## Phase 2 Contract Coverage Map
- Config + startup contract checks: `make test-health-contract`
- Management route contracts (auth topology + read-only store failure envelopes): `make test-management-route-contract`
- RAG/API/middleware/services focused Phase 2 unit + race contracts: `make test-phase2-unit` and `make test-phase2-race`
- Integration contracts (startup, rag, key lifecycle, proxy): `make test-phase2-contract`
- Consolidated Phase 2 gate: `make test-phase2`

## Contract Gate Selection
| Goal | Command | Typical Use |
| --- | --- | --- |
| Fast baseline parity | `make test-ci-fast` | Quick local sanity before development pushes |
| Fast contract coverage | `make test-ci-fast-contracts` | Pre-push contract confidence loop |
| Fast contract coverage (strict backends) | `make test-ci-fast-contracts-strict` | Self-hosted/ready backend environments |
| Fast contract coverage (strict + local reachability) | `make test-ci-fast-contracts-strict-local` | Local environments where Postgres/Redis/LiteLLM must be confirmed before strict checks |
| Fast contract coverage + report artifact | `make test-ci-fast-contracts-report` | Capture contract-gate evidence in `docs/reports/` |
| Full Phase 2 quality gate | `make test-phase2` | Release readiness and final validation |

## Contract Gate Environment Notes
- Fast contract preflight checks for `API_KEY_HASH_PEPPER` and warns when it is missing.
- Set `FAST_CONTRACTS_REQUIRE_INTEGRATION_ENV=1` to make missing integration env fail fast.
- Sample pre-push hook contract mode can be changed with `PRE_PUSH_CONTRACT_MODE=fast|strict|strict-local` (default `fast`).
- Use `PRE_PUSH_CONTRACT_MODE=parity` in the sample pre-push hook for a high-assurance combined local parity run.
- Set `PRE_PUSH_PARITY_STRICT_LOCAL=1` with parity mode to enforce strict-local backend reachability before the combined parity run.
- Strict fast-contract gate also requires reachable local integration backends (notably Postgres for proxy usage-parameter contract tests).
- Set `AUTO_SOURCE_ENV=1` to auto-source `.env` before contract environment checks (useful for local shells).
- Set `STATUS_REQUIRE_ALL_UP=1` with `make contract-env-status-json` when automation should fail if Postgres/Redis/LiteLLM is unreachable.

## PR Gate Coverage
- The `health-contract-fast` workflow job runs `make test-ci-fast` for baseline health/startup contract parity.
- The `fast-contract-gate` workflow job captures `make contract-env-status-json`, validates JSON shape with `make contract-env-validate-json`, runs `make contract-env-validate-selftest`, runs `make contract-env-selftest`, runs `make test-ci-fast-contracts-report`, validates report markdown contract with `make fast-contract-report-validate-markdown`, runs `make fast-contract-report-validate-selftest`, generates `make fast-contract-status-summary`, validates summary shape with `make fast-contract-status-validate-json`, runs `make fast-contract-status-validate-selftest`, generates `make fast-contract-trend-json`, validates trend shape with `make fast-contract-trend-validate-json`, asserts thresholds with `make fast-contract-trend-assert`, generates verdict with `make fast-contract-gate-verdict`, validates verdict shape with `make fast-contract-gate-verdict-validate-json`, runs `make fast-contract-trend-validate-selftest`, runs `make fast-contract-gate-verdict-validate-selftest`, runs `make fast-contract-gate-verdict-selftest`, runs `make fast-contract-artifacts-verify-selftest`, runs `make fast-contract-consistency-validate-selftest`, runs `make fast-contract-consistency-json-validate-selftest`, runs `make fast-contract-consistency-reason-codes-selftest`, runs `make fast-contract-consistency-kpi-validate-selftest`, runs `make fast-contract-consistency-kpi-assert-selftest`, runs `make fast-contract-artifact-manifest-validate-selftest`, runs `make fast-contract-artifact-manifest-assert-paths-selftest`, runs `make fast-contract-artifact-manifest-version-lock-selftest`, runs `make fast-contract-signed-count-version-map-parser-selftest`, runs `make fast-contract-signed-count-lock-matrix-selftest`, runs `make fast-contract-signed-count-lock-error-messages-selftest`, runs `make fast-contract-gate-verdict-reason-codes-selftest`, runs `make fast-contract-policy-fingerprint-validate-selftest`, runs `make fast-contract-policy-fingerprint-canonical-selftest`, runs `make fast-contract-policy-fingerprint-drift-selftest`, runs `make fast-contract-checksums-verify-selftest`, runs `make fast-contract-checksums-tamper-selftest`, runs `make fast-contract-gate-manifest-assert-selftest`, asserts workflow conformance with `make fast-contract-gate-manifest-assert`, validates cross-artifact consistency with `make fast-contract-consistency-validate`, validates consistency status JSON with `make fast-contract-consistency-validate-json`, generates consistency KPI JSON with `make fast-contract-consistency-kpi-json`, validates consistency KPI JSON with `make fast-contract-consistency-kpi-validate-json`, asserts KPI thresholds with `make fast-contract-consistency-kpi-assert`, generates fast-contract artifact manifest with `make fast-contract-artifact-manifest-generate`, validates manifest with `make fast-contract-artifact-manifest-validate`, asserts manifest path integrity with `make fast-contract-artifact-manifest-assert-paths`, generates fast-contract policy fingerprint JSON with `make fast-contract-policy-fingerprint-json`, validates policy fingerprint JSON with `make fast-contract-policy-fingerprint-validate-json`, generates fast-contract checksums with `make fast-contract-checksums-generate`, verifies checksums with `make fast-contract-checksums-verify`, verifies all fast-gate artifacts with `make fast-contract-artifacts-verify`, uploads all fast-gate artifacts, and appends a step summary with status/summary/trend/verdict/consistency/consistency-kpi JSON payloads plus checksum metadata.
- Fast-contract step summary lines are convention-locked in this exact order: checksum status, signed artifacts, policy fingerprint, verdict.
- Strict backend checks remain in `health-contract-strict` and run when explicitly enabled via workflow dispatch or repository variable.

## Recommended Local Sequence
1. `make contract-env-status`
2. `make test-ci-fast-contracts`
3. `make test-phase2`

## Interpreting Skips vs Fails
- A `SKIP` in focused integration contracts usually indicates missing optional local prerequisites (for example `API_KEY_HASH_PEPPER` in non-strict fast mode).
- A `FAIL` in strict gates indicates required prerequisites are enforced and missing or unreachable (for example strict-local backend reachability checks).
- Use `make test-ci-fast-contracts` for flexible local loops, and `make test-ci-fast-contracts-strict-local` when you want hard guarantees before pushing.

## Optional Git Hook
- Template: `scripts/git-hooks/pre-push.example`
- Installer: `scripts/git-hooks/install_pre_push.sh`
- Dry-run install: `scripts/git-hooks/install_pre_push.sh --dry-run`

## Troubleshooting
- `health-contract-fast` fails with startup validation error:
  - Ensure `HEALTH_DEGRADED_LATENCY_MS` is not negative in your environment.
- Strict integration checks fail due to backend outage:
  - Confirm LiteLLM, Elasticsearch, Redis, and Postgres are reachable from the test environment.
  - For local development, use non-strict checks unless you intentionally want backend outages to fail tests.
- `shellcheck-scripts` prints "shellcheck not installed":
  - Install shellcheck locally or rely on the `Script Lint` GitHub workflow.

## Manual Strict Workflow Dispatch
- Main workflow (`health-contract.yml`):
  - Run via Actions > Health Contract > Run workflow.
  - Set input `run_strict_backends` to `true`.
- Nightly workflow (`health-contract-strict-nightly.yml`):
  - Run via Actions > Health Contract Strict Nightly > Run workflow.
  - This always includes strict backend checks.

## Manual Local Smoke Guard Workflow
- Workflow (`local-smoke-report-guard.yml`):
  - Run via Actions > Local Smoke Report Guard > Run workflow.
  - Requires a self-hosted runner with local OpenEdAI dependencies available.
  - Optional dispatch inputs: `trend_limit`, `max_fail`, `max_unknown`, `min_pass_rate`, `max_standard_total`, `max_auth_total`, `max_standard_age_days`, `max_auth_age_days`, `dashboard_lean`, `run_policy_selftest`.
  - Generates two timestamped local smoke reports, runs `make report-guard`, prints `make report-trend-last-json`, enforces `make report-trend-assert`, asserts `make report-guard-all-assert EXPECTED_OVERALL=PASS EXPECTED_AUTH_MODE=ANY`, prints both `make report-guard-all-json` and either `make report-health-dashboard-json` or `make report-health-dashboard-json-lean` when `dashboard_lean=true`, runs `DRY_RUN=1 make report-prune` for retention visibility, enforces `make report-prune-assert` for inventory limits, and optionally runs `make report-policy-selftest` when `run_policy_selftest=true`.
  - Uploads governance artifacts with 14-day retention: JSON outputs (`latest-summary.json`, `latest-drift.json`, `trend.json`, `combined-guard.json`, `policy-overview.json`, `dashboard.json`, `prune-policy.json`) plus `artifact-manifest.json` and `status-summary.json`.
  - Includes `sha256sums.txt` for artifact integrity verification.
  - Adds a concise Governance Artifact Summary to the workflow run step summary.

## Manual Local Smoke Guard Auth Workflow
- Workflow (`local-smoke-report-guard-auth.yml`):
  - Run via Actions > Local Smoke Report Guard Auth > Run workflow.
  - Requires a self-hosted runner with local OpenEdAI dependencies available.
  - Requires repository secret `GATEWAY_TEST_API_KEY` (workflow exports it to the job environment).
  - Optional dispatch inputs: `trend_limit`, `max_fail`, `max_unknown`, `min_pass_rate`, `max_standard_total`, `max_auth_total`, `max_standard_age_days`, `max_auth_age_days`, `dashboard_lean`, `run_policy_selftest`.
  - Generates two timestamped auth smoke reports, runs `make report-guard-auth`, prints `make report-trend-last-json`, enforces `make report-trend-assert`, asserts `make report-guard-all-assert EXPECTED_OVERALL=PASS EXPECTED_AUTH_MODE=ENFORCED`, prints both `make report-guard-all-json` and either `make report-health-dashboard-json` or `make report-health-dashboard-json-lean` when `dashboard_lean=true`, runs `DRY_RUN=1 make report-prune` for retention visibility, enforces `make report-prune-assert` for inventory limits, and optionally runs `make report-policy-selftest` when `run_policy_selftest=true`.
  - Uploads governance artifacts with 14-day retention: JSON outputs (`latest-summary.json`, `latest-drift.json`, `trend.json`, `combined-guard.json`, `policy-overview.json`, `dashboard.json`, `prune-policy.json`) plus `artifact-manifest.json` and `status-summary.json`.
  - Includes `sha256sums.txt` for artifact integrity verification.
  - Adds a concise Governance Artifact Summary to the workflow run step summary.

## Governance Policy Self-Test Workflow
- Workflow (`governance-policy-selftest.yml`):
  - Runs weekly and supports manual dispatch.
  - Executes `make report-policy-selftest` as a standalone governance regression check.
  - Uses a synthetic legacy report fixture during age-policy assertions, so it does not depend on pre-existing timestamped report files.
  - Uploads artifacts with 14-day retention: `policy-selftest.log`, `policy-overview.json`, `artifact-manifest.json`, and `status-summary.json`.
  - Includes `sha256sums.txt` for artifact integrity verification.
  - Adds a concise Governance Self-Test Summary to the workflow run step summary.

## Governance Workflow Conventions Workflow
- Workflow (`governance-workflow-conventions.yml`):
  - Runs weekly, on pull requests that change workflows/governance CI surfaces, and on manual dispatch.
  - Executes `make verify-workflow-conventions` and `make report-policy-selftest` to block structural and behavioral governance drift.

## Fast Contract Governance Heartbeat
- Workflow (`fast-contract-governance-heartbeat.yml`):
  - Runs weekly and on manual dispatch.
  - Executes lightweight governance checks for fast-contract CI automation:
    - `make verify-workflow-conventions`
    - `make fast-contract-report-validate-selftest`
    - `make fast-contract-status-validate-selftest`
    - `make fast-contract-trend-validate-selftest`
    - `make fast-contract-gate-verdict-validate-selftest`
    - `make fast-contract-artifacts-verify-selftest`
    - `make fast-contract-consistency-validate-selftest`
    - `make fast-contract-consistency-json-validate-selftest`
    - `make fast-contract-consistency-reason-codes-selftest`
    - `make fast-contract-consistency-kpi-validate-selftest`
    - `make fast-contract-consistency-kpi-assert-selftest`
    - `make fast-contract-artifact-manifest-validate-selftest`
    - `make fast-contract-artifact-manifest-assert-paths-selftest`
    - `make fast-contract-artifact-manifest-version-lock-selftest`
    - `make fast-contract-signed-count-version-map-parser-selftest`
    - `make fast-contract-signed-count-lock-matrix-selftest`
    - `make fast-contract-signed-count-lock-error-messages-selftest`
    - `make fast-contract-gate-verdict-reason-codes-selftest`
    - `make fast-contract-policy-fingerprint-validate-selftest`
    - `make fast-contract-policy-fingerprint-drift-selftest`
    - `make fast-contract-checksums-verify-selftest`
    - `make fast-contract-checksums-tamper-selftest`
    - `make fast-contract-gate-manifest-assert-selftest`
    - `make fast-contract-gate-manifest-assert`
  - Manual dispatch can optionally include strict-local checks by setting `run_strict_local_checks=true`.

## Artifact Helper
- Script (`scripts/ci/workflow_artifact_manifest.sh`):
  - Shared helper used by governance workflows to generate `artifact-manifest.json` and append a concise step summary.
  - Modes: `smoke` (guard/policy/dashboard summary) and `selftest` (self-test/policy summary).
  - Also emits `status-summary.json` for lightweight downstream consumers.

## Status Summary Schema
- Smoke mode (`status-summary.json`): `generated_at`, `workflow`, `run_id`, `run_attempt`, `overall`, `policy_status`, `dashboard_mode`.
- Self-test mode (`status-summary.json`): `generated_at`, `workflow`, `run_id`, `run_attempt`, `selftest_passed`, `policy_status`.

Smoke example:
```json
{
  "generated_at": "2026-05-29T00:00:00+00:00",
  "workflow": "Local Smoke Report Guard",
  "run_id": "123456789",
  "run_attempt": "1",
  "overall": "PASS",
  "policy_status": "PASS",
  "dashboard_mode": "full"
}
```

Self-test example:
```json
{
  "generated_at": "2026-05-29T00:00:00+00:00",
  "workflow": "Governance Policy Self-Test",
  "run_id": "123456789",
  "run_attempt": "1",
  "selftest_passed": true,
  "policy_status": "PASS"
}
```

## Workflow Convention Verifier
- Script (`scripts/ci/verify_workflow_conventions.sh`):
  - Verifies governance workflows still include shared helper invocation, checksum generation, pre-upload artifact-bundle verification, artifact upload steps, status-summary generation, `retention-days: 14` policy, and weekly scheduling for the governance conventions workflow.
  - Run locally via `make verify-workflow-conventions` after workflow edits.

## Artifact Bundle Verifier
- Script (`scripts/ci/verify_artifact_bundle.sh`):
  - Verifies `sha256sums.txt` integrity and validates readable `status-summary.json` in a downloaded artifact directory.
  - Supports strict mode checks with `BUNDLE_MODE=smoke` or `BUNDLE_MODE=selftest` (defaults to `auto`).
  - Run locally via `make verify-governance-artifacts ARTIFACT_DIR=/path/to/artifacts [BUNDLE_MODE=auto|smoke|selftest]`.

- Script (`scripts/ci/verify_artifact_bundle_selftest.sh`):
  - Runs positive and negative checks for artifact-bundle validation logic.
  - Ensures malformed smoke summaries fail as expected.
  - Run locally via `make verify-governance-artifacts-selftest`.

## Release Checklist
1. Run `make ci-local-status` and ensure required local tools are available.
2. Run `make test-ci-all` to execute fast + strict local parity checks.
3. Run `make test-proxy-operational-flake ITERATIONS=5` when you need repeated confidence on the end-to-end proxy accounting path.
4. Run `make smoke-gateway-local` to validate restart + endpoint behavior.
5. If you have a management test key, export `GATEWAY_TEST_API_KEY` and run `make smoke-gateway-auth`.
6. If shell scripts/workflows changed, run `make shellcheck-scripts`.
7. Capture the run output in a timestamped report under `docs/reports/` (or run `make report-generate-local-smoke`).
8. Run `make report-latest-summary` for a compact pass/fail line.
9. Run `make report-latest-summary-json` for machine-readable output.
10. If you need enforced auth validation evidence, run `make report-generate-local-smoke-auth`.
11. Run `make report-compare-latest` to detect checklist drift across recent runs.
12. Run `make report-compare-latest-json` for machine-readable drift detection.
13. Run `make report-guard` to fail fast when summary is not PASS or drift is detected.
14. Run `make report-trend-last` to inspect trend across recent reports (or `bash scripts/ci/report_trend_last.sh <N>`).
15. Run `make report-trend-last-json` when machine-readable trend data is needed (or `bash scripts/ci/report_trend_last_json.sh <N>`).
16. Run `make report-trend-assert` to enforce rolling trend thresholds.
17. Run `make report-guard-auth` to enforce that the latest auth smoke report exists and all auth checks are zero.
18. Run `make report-guard-all` to enforce standard guard and automatically include auth guard when auth reports exist.
19. Run `make report-guard-all-json` when CI or automation needs one combined JSON status payload.
20. Run `bash scripts/ci/report_guard_all_assert.sh PASS ANY` to fail fast when combined guard output does not match expected states.
21. Run `make report-health-dashboard-json` when dashboards/alerts need one compact payload combining latest summary, latest drift, trend, combined guard status, policy overview, and prune policy status.
22. Run `make report-health-dashboard-json-lean` when you want the same dashboard payload but without the duplicated top-level `prune_policy` block.
23. Run `DRY_RUN=1 make report-prune` to preview report retention effects, then run `make report-prune` to apply cleanup.
24. Run `make report-prune-assert` to enforce maximum report inventory limits for standard/auth smoke artifacts.
25. Run `make report-prune-assert-json` when automation needs prune policy status as pure JSON.
26. Set `MAX_STANDARD_AGE_DAYS` / `MAX_AUTH_AGE_DAYS` when you need retention policy assertions on report age, not only counts.
27. Run `make report-policy-overview-json` when automation needs one JSON status for both trend thresholds and prune policy limits.
28. Run `make report-policy-selftest` to verify expected success/failure behavior for baseline, trend-threshold, prune-total, and prune-age governance cases.
