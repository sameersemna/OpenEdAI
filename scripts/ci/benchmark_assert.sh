#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

BENCH_ASSERT_OUTPUT="${BENCH_ASSERT_OUTPUT:-text}"
BENCH_ASSERT_REPEAT="${BENCH_ASSERT_REPEAT:-1}"

if ! [[ "$BENCH_ASSERT_REPEAT" =~ ^[1-9][0-9]*$ ]]; then
  echo "[bench-assert][fail] BENCH_ASSERT_REPEAT must be a positive integer (got: $BENCH_ASSERT_REPEAT)"
  exit 1
fi

# Thresholds can be overridden from env for tighter or looser local policy.
HEALTH_ENABLED_MAX_NS="${HEALTH_ENABLED_MAX_NS:-7000}"
HEALTH_ENABLED_MAX_BYTES="${HEALTH_ENABLED_MAX_BYTES:-3200}"
HEALTH_ENABLED_MAX_ALLOCS="${HEALTH_ENABLED_MAX_ALLOCS:-30}"
HEALTH_DISABLED_MAX_NS="${HEALTH_DISABLED_MAX_NS:-20000}"
HEALTH_DISABLED_MAX_BYTES="${HEALTH_DISABLED_MAX_BYTES:-5000}"
HEALTH_DISABLED_MAX_ALLOCS="${HEALTH_DISABLED_MAX_ALLOCS:-50}"
RENDER_ERROR_MAX_NS="${RENDER_ERROR_MAX_NS:-7000}"
RENDER_ERROR_MAX_BYTES="${RENDER_ERROR_MAX_BYTES:-4000}"
RENDER_ERROR_MAX_ALLOCS="${RENDER_ERROR_MAX_ALLOCS:-45}"
RAG_BACKEND_MAX_NS="${RAG_BACKEND_MAX_NS:-800}"
RAG_BACKEND_MAX_BYTES="${RAG_BACKEND_MAX_BYTES:-450}"
RAG_BACKEND_MAX_ALLOCS="${RAG_BACKEND_MAX_ALLOCS:-6}"
REQ_ID_GENERATE_MAX_NS="${REQ_ID_GENERATE_MAX_NS:-7000}"
REQ_ID_GENERATE_MAX_BYTES="${REQ_ID_GENERATE_MAX_BYTES:-7000}"
REQ_ID_GENERATE_MAX_ALLOCS="${REQ_ID_GENERATE_MAX_ALLOCS:-30}"
REQ_ID_PRESERVE_MAX_NS="${REQ_ID_PRESERVE_MAX_NS:-7000}"
REQ_ID_PRESERVE_MAX_BYTES="${REQ_ID_PRESERVE_MAX_BYTES:-7000}"
REQ_ID_PRESERVE_MAX_ALLOCS="${REQ_ID_PRESERVE_MAX_ALLOCS:-30}"

bench_results_json=""

log_msg() {
  if [[ "$BENCH_ASSERT_OUTPUT" == "json" ]]; then
    printf '%s\n' "$*" >&2
    return
  fi
  printf '%s\n' "$*"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

append_result() {
  local benchmark_name="$1"
  local status="$2"
  local ns="$3"
  local bytes="$4"
  local allocs="$5"
  local max_ns="$6"
  local max_bytes="$7"
  local max_allocs="$8"
  local reason="$9"

  local escaped_reason
  escaped_reason="$(json_escape "$reason")"

  local item
  item="{\"benchmark\":\"$benchmark_name\",\"status\":\"$status\",\"ns_op\":$ns,\"bytes_op\":$bytes,\"allocs_op\":$allocs,\"max_ns_op\":$max_ns,\"max_bytes_op\":$max_bytes,\"max_allocs_op\":$max_allocs,\"reason\":\"$escaped_reason\"}"

  if [[ -z "$bench_results_json" ]]; then
    bench_results_json="$item"
  else
    bench_results_json="$bench_results_json,$item"
  fi
}

run_bench() {
  local package="$1"
  local regex="$2"
  local i
  local combined=""
  for ((i = 1; i <= BENCH_ASSERT_REPEAT; i++)); do
    if [[ -n "$combined" ]]; then
      combined="$combined"$'\n'
    fi
    combined="$combined$(go test -run '^$' -bench "$regex" -benchmem "$package")"
  done
  printf '%s\n' "$combined"
}

parse_metrics() {
  local output="$1"
  local benchmark_name="$2"
  local metrics

  metrics="$(printf '%s\n' "$output" | awk -v name="$benchmark_name" '
    $1 ~ ("^" name "-") {
      n++
      ns[n] = $3 + 0
      bytes[n] = $5 + 0
      allocs[n] = $7 + 0
    }
    function sort_numeric(arr, count, i, j, tmp) {
      for (i = 1; i <= count; i++) {
        for (j = i + 1; j <= count; j++) {
          if (arr[i] > arr[j]) {
            tmp = arr[i]
            arr[i] = arr[j]
            arr[j] = tmp
          }
        }
      }
    }
    function median(arr, count, mid) {
      sort_numeric(arr, count)
      if (count % 2 == 1) {
        return arr[(count + 1) / 2]
      }
      mid = count / 2
      return (arr[mid] + arr[mid + 1]) / 2
    }
    END {
      if (n == 0) {
        exit
      }
      printf "%.3f,%.3f,%.3f", median(ns, n), median(bytes, n), median(allocs, n)
    }
  ')"
  if [[ -z "$metrics" ]]; then
    echo ""
    return
  fi

  printf '%s\n' "$metrics"
}

num_gt() {
  local actual="$1"
  local threshold="$2"
  awk -v a="$actual" -v b="$threshold" 'BEGIN { exit ((a + 0) > (b + 0) ? 0 : 1) }'
}

assert_benchmark() {
  local output="$1"
  local benchmark_name="$2"
  local max_ns="$3"
  local max_bytes="$4"
  local max_allocs="$5"

  local metrics
  metrics="$(parse_metrics "$output" "$benchmark_name")"
  if [[ -z "$metrics" ]]; then
    append_result "$benchmark_name" "fail" 0 0 0 "$max_ns" "$max_bytes" "$max_allocs" "benchmark not found"
    log_msg "[bench-assert][fail] benchmark not found: $benchmark_name"
    return 1
  fi

  local ns bytes allocs
  ns="${metrics%%,*}"
  bytes="$(printf '%s' "$metrics" | cut -d',' -f2)"
  allocs="${metrics##*,}"

  local reasons
  reasons=""

  if num_gt "$ns" "$max_ns"; then
    reasons="ns/op threshold exceeded (actual=$ns max=$max_ns)"
  fi

  if num_gt "$bytes" "$max_bytes"; then
    if [[ -n "$reasons" ]]; then
      reasons="$reasons; "
    fi
    reasons="$reasons""bytes/op threshold exceeded (actual=$bytes max=$max_bytes)"
  fi

  if num_gt "$allocs" "$max_allocs"; then
    if [[ -n "$reasons" ]]; then
      reasons="$reasons; "
    fi
    reasons="$reasons""allocs/op threshold exceeded (actual=$allocs max=$max_allocs)"
  fi

  if [[ -n "$reasons" ]]; then
    append_result "$benchmark_name" "fail" "$ns" "$bytes" "$allocs" "$max_ns" "$max_bytes" "$max_allocs" "$reasons"
    log_msg "[bench-assert][fail] $benchmark_name $reasons"
    return 1
  fi

  append_result "$benchmark_name" "ok" "$ns" "$bytes" "$allocs" "$max_ns" "$max_bytes" "$max_allocs" ""
  log_msg "[bench-assert][ok] $benchmark_name median_ns/op=$ns median_bytes/op=$bytes median_allocs/op=$allocs samples=$BENCH_ASSERT_REPEAT"
}

health_output="$(run_bench ./internal/api '^BenchmarkHealthHandlerCache(Enabled|Disabled)$')"
api_output="$(run_bench ./internal/api '^Benchmark(RenderAPIError|RAGBackendError(Elasticsearch|Qdrant))$')"
middleware_output="$(run_bench ./internal/middleware '^BenchmarkRequestIDMiddleware(Generate|Preserve)$')"

status=0

assert_benchmark "$health_output" "BenchmarkHealthHandlerCacheEnabled" "$HEALTH_ENABLED_MAX_NS" "$HEALTH_ENABLED_MAX_BYTES" "$HEALTH_ENABLED_MAX_ALLOCS" || status=1
assert_benchmark "$health_output" "BenchmarkHealthHandlerCacheDisabled" "$HEALTH_DISABLED_MAX_NS" "$HEALTH_DISABLED_MAX_BYTES" "$HEALTH_DISABLED_MAX_ALLOCS" || status=1
assert_benchmark "$api_output" "BenchmarkRenderAPIError" "$RENDER_ERROR_MAX_NS" "$RENDER_ERROR_MAX_BYTES" "$RENDER_ERROR_MAX_ALLOCS" || status=1
assert_benchmark "$api_output" "BenchmarkRAGBackendErrorElasticsearch" "$RAG_BACKEND_MAX_NS" "$RAG_BACKEND_MAX_BYTES" "$RAG_BACKEND_MAX_ALLOCS" || status=1
assert_benchmark "$api_output" "BenchmarkRAGBackendErrorQdrant" "$RAG_BACKEND_MAX_NS" "$RAG_BACKEND_MAX_BYTES" "$RAG_BACKEND_MAX_ALLOCS" || status=1
assert_benchmark "$middleware_output" "BenchmarkRequestIDMiddlewareGenerate" "$REQ_ID_GENERATE_MAX_NS" "$REQ_ID_GENERATE_MAX_BYTES" "$REQ_ID_GENERATE_MAX_ALLOCS" || status=1
assert_benchmark "$middleware_output" "BenchmarkRequestIDMiddlewarePreserve" "$REQ_ID_PRESERVE_MAX_NS" "$REQ_ID_PRESERVE_MAX_BYTES" "$REQ_ID_PRESERVE_MAX_ALLOCS" || status=1

if (( status != 0 )); then
  log_msg "[bench-assert][fail] one or more benchmark thresholds were exceeded"
  if [[ "$BENCH_ASSERT_OUTPUT" == "json" ]]; then
    printf '{"overall":"fail","results":[%s]}\n' "$bench_results_json"
  fi
  exit 1
fi

log_msg "[bench-assert][ok] all benchmark thresholds satisfied"
if [[ "$BENCH_ASSERT_OUTPUT" == "json" ]]; then
  printf '{"overall":"ok","results":[%s]}\n' "$bench_results_json"
fi
