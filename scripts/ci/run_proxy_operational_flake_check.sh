#!/usr/bin/env bash
set -euo pipefail

iterations="${1:-5}"

if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -le 0 ]]; then
  echo "usage: $0 [positive-iteration-count]" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if [[ ! -f .env ]]; then
  echo "missing .env in $repo_root" >&2
  exit 1
fi

pass_count=0

echo "Running TestProxyOperationalFlow $iterations time(s) from $repo_root"

for ((i = 1; i <= iterations; i++)); do
  echo
  echo "[$i/$iterations] go test ./tests/integration -run TestProxyOperationalFlow -count=1 -v"

  if env -i PATH="$PATH" HOME="$HOME" XAUTHORITY="${XAUTHORITY:-}" TERM="${TERM:-xterm}" bash -lc 'set -euo pipefail; cd "$1"; set -a; source .env; set +a; go test ./tests/integration -run TestProxyOperationalFlow -count=1 -v' _ "$repo_root"; then
    pass_count=$((pass_count + 1))
  else
    echo
    echo "flake check failed on iteration $i/$iterations" >&2
    exit 1
  fi
done

echo
echo "flake check passed: $pass_count/$iterations successful iterations"