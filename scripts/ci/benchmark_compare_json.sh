#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ $# -ne 2 ]]; then
  echo '{"error":"usage: benchmark_compare_json.sh <baseline-json> <current-json>"}'
  exit 1
fi

baseline_file="$1"
current_file="$2"

if [[ ! -f "$baseline_file" ]]; then
  echo '{"error":"baseline benchmark json file not found"}'
  exit 1
fi
if [[ ! -f "$current_file" ]]; then
  echo '{"error":"current benchmark json file not found"}'
  exit 1
fi

BENCH_COMPARE_PROFILE="${BENCH_COMPARE_PROFILE:-normal}"

case "$BENCH_COMPARE_PROFILE" in
    strict)
        default_ns_delta_pct="5"
        default_bytes_delta_pct="5"
        default_allocs_delta_pct="5"
        ;;
    normal)
        default_ns_delta_pct="10"
        default_bytes_delta_pct="10"
        default_allocs_delta_pct="10"
        ;;
    relaxed)
        default_ns_delta_pct="20"
        default_bytes_delta_pct="20"
        default_allocs_delta_pct="20"
        ;;
    *)
        echo '{"error":"BENCH_COMPARE_PROFILE must be one of: strict, normal, relaxed"}'
        exit 1
        ;;
esac

MAX_NS_DELTA_PCT="${BENCH_COMPARE_MAX_NS_DELTA_PCT:-$default_ns_delta_pct}"
MAX_BYTES_DELTA_PCT="${BENCH_COMPARE_MAX_BYTES_DELTA_PCT:-$default_bytes_delta_pct}"
MAX_ALLOCS_DELTA_PCT="${BENCH_COMPARE_MAX_ALLOCS_DELTA_PCT:-$default_allocs_delta_pct}"

if ! [[ "$MAX_NS_DELTA_PCT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"error":"BENCH_COMPARE_MAX_NS_DELTA_PCT must be a non-negative number"}'
  exit 1
fi
if ! [[ "$MAX_BYTES_DELTA_PCT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"error":"BENCH_COMPARE_MAX_BYTES_DELTA_PCT must be a non-negative number"}'
  exit 1
fi
if ! [[ "$MAX_ALLOCS_DELTA_PCT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"error":"BENCH_COMPARE_MAX_ALLOCS_DELTA_PCT must be a non-negative number"}'
  exit 1
fi

python3 - "$baseline_file" "$current_file" "$MAX_NS_DELTA_PCT" "$MAX_BYTES_DELTA_PCT" "$MAX_ALLOCS_DELTA_PCT" <<'PY'
import json
import sys
from pathlib import Path

baseline_path = Path(sys.argv[1])
current_path = Path(sys.argv[2])
max_ns_delta_pct = float(sys.argv[3])
max_bytes_delta_pct = float(sys.argv[4])
max_allocs_delta_pct = float(sys.argv[5])

def load_payload(path: Path):
    text = path.read_text().strip()
    if not text:
        raise ValueError(f"empty benchmark json file: {path}")
    if text.startswith("{"):
        return json.loads(text)
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise ValueError(f"unable to find json payload in {path}")

baseline = load_payload(baseline_path)
current = load_payload(current_path)

baseline_results = {item["benchmark"]: item for item in baseline.get("results", [])}
current_results = {item["benchmark"]: item for item in current.get("results", [])}

benchmark_names = sorted(set(baseline_results) | set(current_results))
changes = []
passes = 0
fails = 0
unknown = 0

def pct_change(before, after):
    before = float(before)
    after = float(after)
    if before == 0:
        return 0.0 if after == 0 else 100.0
    return ((after - before) / before) * 100.0

for name in benchmark_names:
    base = baseline_results.get(name)
    cur = current_results.get(name)
    if base is None or cur is None:
        changes.append({
            "benchmark": name,
            "status": "unknown",
            "reason": "missing benchmark in one of the payloads",
        })
        unknown += 1
        continue

    ns_delta = pct_change(base["ns_op"], cur["ns_op"])
    bytes_delta = pct_change(base["bytes_op"], cur["bytes_op"])
    allocs_delta = pct_change(base["allocs_op"], cur["allocs_op"])

    reasons = []
    if ns_delta > max_ns_delta_pct:
        reasons.append(f"ns_op increased by {ns_delta:.1f}% (max {max_ns_delta_pct:.1f}%)")
    if bytes_delta > max_bytes_delta_pct:
        reasons.append(f"bytes_op increased by {bytes_delta:.1f}% (max {max_bytes_delta_pct:.1f}%)")
    if allocs_delta > max_allocs_delta_pct:
        reasons.append(f"allocs_op increased by {allocs_delta:.1f}% (max {max_allocs_delta_pct:.1f}%)")

    status = "ok" if not reasons else "fail"
    if status == "ok":
        passes += 1
    else:
        fails += 1

    changes.append({
        "benchmark": name,
        "status": status,
        "baseline": {
            "ns_op": base["ns_op"],
            "bytes_op": base["bytes_op"],
            "allocs_op": base["allocs_op"],
        },
        "current": {
            "ns_op": cur["ns_op"],
            "bytes_op": cur["bytes_op"],
            "allocs_op": cur["allocs_op"],
        },
        "delta_percent": {
            "ns_op": round(ns_delta, 1),
            "bytes_op": round(bytes_delta, 1),
            "allocs_op": round(allocs_delta, 1),
        },
        "reason": "; ".join(reasons),
    })

overall = "PASS" if fails == 0 and unknown == 0 else ("UNKNOWN" if fails == 0 else "FAIL")
output = {
    "overall": overall,
    "summary": {
        "pass": passes,
        "fail": fails,
        "unknown": unknown,
        "max_ns_delta_pct": max_ns_delta_pct,
        "max_bytes_delta_pct": max_bytes_delta_pct,
        "max_allocs_delta_pct": max_allocs_delta_pct,
    },
    "baseline": baseline_path.name,
    "current": current_path.name,
    "changes": changes,
}

print(json.dumps(output, separators=(",", ":")))

if overall != "PASS":
    sys.exit(1)
PY
