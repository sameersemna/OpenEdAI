#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_root="/tmp/openedai-artifact-selftest"
smoke_ok_dir="$tmp_root/smoke-ok"
selftest_ok_dir="$tmp_root/selftest-ok"
smoke_bad_dir="$tmp_root/smoke-bad"
smoke_tamper_dir="$tmp_root/smoke-tamper"
report_md="/tmp/openedai_artifact_selftest_report.md"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

mkdir -p "$smoke_ok_dir" "$selftest_ok_dir" "$smoke_bad_dir" "$smoke_tamper_dir"

cat > "$report_md" <<'EOF'
# Governance Artifact Verifier Self-Test

| Case | Expected | Result |
|---|---|---|
EOF

printf '{"generated_at":"2026-05-29T00:00:00Z","workflow":"selftest","run_id":"1","run_attempt":"1","overall":"PASS","policy_status":"PASS","dashboard_mode":"full"}\n' > "$smoke_ok_dir/status-summary.json"
printf '{"status":"ok"}\n' > "$smoke_ok_dir/artifact-manifest.json"
(
  cd "$smoke_ok_dir"
  sha256sum status-summary.json artifact-manifest.json > sha256sums.txt
)

printf '{"generated_at":"2026-05-29T00:00:00Z","workflow":"selftest","run_id":"2","run_attempt":"1","selftest_passed":true,"policy_status":"PASS"}\n' > "$selftest_ok_dir/status-summary.json"
printf '{"status":"ok"}\n' > "$selftest_ok_dir/artifact-manifest.json"
(
  cd "$selftest_ok_dir"
  sha256sum status-summary.json artifact-manifest.json > sha256sums.txt
)

# Deliberately malformed smoke bundle: dashboard_mode missing
printf '{"generated_at":"2026-05-29T00:00:00Z","workflow":"selftest","run_id":"3","run_attempt":"1","overall":"PASS","policy_status":"PASS"}\n' > "$smoke_bad_dir/status-summary.json"
printf '{"status":"ok"}\n' > "$smoke_bad_dir/artifact-manifest.json"
(
  cd "$smoke_bad_dir"
  sha256sum status-summary.json artifact-manifest.json > sha256sums.txt
)

printf '{"generated_at":"2026-05-29T00:00:00Z","workflow":"selftest","run_id":"4","run_attempt":"1","overall":"PASS","policy_status":"PASS","dashboard_mode":"full"}\n' > "$smoke_tamper_dir/status-summary.json"
printf '{"status":"ok"}\n' > "$smoke_tamper_dir/artifact-manifest.json"
(
  cd "$smoke_tamper_dir"
  sha256sum status-summary.json artifact-manifest.json > sha256sums.txt
)
# Tamper after checksum generation to verify integrity failure detection.
printf '{"generated_at":"2026-05-29T00:00:00Z","workflow":"selftest","run_id":"4","run_attempt":"2","overall":"PASS","policy_status":"PASS","dashboard_mode":"full"}\n' > "$smoke_tamper_dir/status-summary.json"

echo "[artifact-selftest] validating smoke bundle (expected pass)"
bash scripts/ci/verify_artifact_bundle.sh "$smoke_ok_dir" smoke >/tmp/openedai_artifact_selftest_smoke_ok.log
echo "| smoke valid bundle | pass | pass |" >> "$report_md"

echo "[artifact-selftest] validating selftest bundle (expected pass)"
bash scripts/ci/verify_artifact_bundle.sh "$selftest_ok_dir" selftest >/tmp/openedai_artifact_selftest_selftest_ok.log
echo "| selftest valid bundle | pass | pass |" >> "$report_md"

echo "[artifact-selftest] validating malformed smoke bundle (expected fail)"
set +e
bash scripts/ci/verify_artifact_bundle.sh "$smoke_bad_dir" smoke >/tmp/openedai_artifact_selftest_smoke_bad.log 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[artifact-selftest][fail] malformed smoke bundle unexpectedly passed"
  echo "| malformed smoke bundle | fail | FAIL (unexpected pass) |" >> "$report_md"
  cat /tmp/openedai_artifact_selftest_smoke_bad.log
  cat "$report_md"
  exit 1
fi

echo "[artifact-selftest][ok] malformed smoke bundle failed as expected"
echo "| malformed smoke bundle | fail | pass |" >> "$report_md"

echo "[artifact-selftest] validating checksum-tampered smoke bundle (expected fail)"
set +e
bash scripts/ci/verify_artifact_bundle.sh "$smoke_tamper_dir" smoke >/tmp/openedai_artifact_selftest_smoke_tamper.log 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo "[artifact-selftest][fail] checksum-tampered smoke bundle unexpectedly passed"
  echo "| checksum-tampered smoke bundle | fail | FAIL (unexpected pass) |" >> "$report_md"
  cat /tmp/openedai_artifact_selftest_smoke_tamper.log
  cat "$report_md"
  exit 1
fi

echo "[artifact-selftest][ok] checksum-tampered smoke bundle failed as expected"
echo "| checksum-tampered smoke bundle | fail | pass |" >> "$report_md"
echo
echo "[artifact-selftest] markdown report: $report_md"
cat "$report_md"
echo "[artifact-selftest][ok] all checks passed"
