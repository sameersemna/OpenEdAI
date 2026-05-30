#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

repeat="${BENCH_COMPARE_REPEAT:-3}"
if ! [[ "$repeat" =~ ^[1-9][0-9]*$ ]]; then
  echo '{"error":"BENCH_COMPARE_REPEAT must be a positive integer"}'
  exit 1
fi

BENCH_ASSERT_REPEAT="$repeat" BENCH_ASSERT_OUTPUT=json bash scripts/ci/benchmark_assert.sh > "$tmpdir/base.json"
BENCH_ASSERT_REPEAT="$repeat" BENCH_ASSERT_OUTPUT=json bash scripts/ci/benchmark_assert.sh > "$tmpdir/current.json"

BASELINE_BENCH_JSON="$tmpdir/base.json" CURRENT_BENCH_JSON="$tmpdir/current.json" \
  bash scripts/ci/benchmark_compare_json.sh "$tmpdir/base.json" "$tmpdir/current.json"
