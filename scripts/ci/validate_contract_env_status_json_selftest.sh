#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
validator="${repo_root}/scripts/ci/validate_contract_env_status_json.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_json="${tmp_dir}/valid.json"
invalid_json="${tmp_dir}/invalid.json"

cat >"$valid_json" <<'EOF'
{
  "mode": "status-json",
  "auto_source_env": false,
  "overall_status": "degraded",
  "status_require_all_up": 0,
  "api_key_hash_pepper": "missing",
  "services": {
    "postgres": {"host": "127.0.0.1", "port": 5432, "status": "down"},
    "redis": {"host": "127.0.0.1", "port": 6379, "status": "down"},
    "litellm": {"host": "127.0.0.1", "port": 4000, "status": "down"}
  }
}
EOF

cat >"$invalid_json" <<'EOF'
{
  "mode": "status-json",
  "auto_source_env": false,
  "status_require_all_up": 0,
  "api_key_hash_pepper": "missing",
  "services": {
    "postgres": {"host": "127.0.0.1", "port": 5432, "status": "down"},
    "redis": {"host": "127.0.0.1", "port": 6379, "status": "down"},
    "litellm": {"host": "127.0.0.1", "port": 4000, "status": "down"}
  }
}
EOF

bash "$validator" "$valid_json"

set +e
bash "$validator" "$invalid_json" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" == "0" ]]; then
  echo "[contracts][fail] validator should reject invalid json missing overall_status" >&2
  exit 1
fi

echo "[contracts][ok] validator selftest passed"
