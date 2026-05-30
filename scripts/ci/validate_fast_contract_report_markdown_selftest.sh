#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_fast_contract_report_markdown.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_report="${tmp_dir}/valid-fast-contract-gate-report.md"
cat >"$valid_report" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS
- Command: make test-ci-fast-contracts

## Output
```text
ok
```
EOF

bash "$validator" "$valid_report"

invalid_report="${tmp_dir}/invalid-fast-contract-gate-report.md"
cat >"$invalid_report" <<'EOF'
# Fast Contract Gate Report (20260530-230000)

- Status: PASS

## Output
```text
ok
```
EOF

set +e
bash "$validator" "$invalid_report" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] report validator should fail when command line is missing" >&2
  exit 1
fi

echo "[contracts][ok] fast contract report markdown validator selftest passed"
