#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

checksums_path="${1:-${FAST_CONTRACT_CHECKSUMS:-artifacts/contracts/sha256sums.txt}}"

if [[ ! -f "$checksums_path" ]]; then
  echo "[contracts][fail] checksum file not found: $checksums_path" >&2
  exit 1
fi

sha256sum -c "$checksums_path"

echo "[contracts][ok] verified fast contract checksums: $checksums_path"
