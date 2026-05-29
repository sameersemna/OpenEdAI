#!/usr/bin/env bash
set -euo pipefail

print_status() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "[ok] $tool: $(command -v "$tool")"
  else
    echo "[missing] $tool"
  fi
}

echo "OpenEdAI Local CI Tooling Status"
echo
print_status git
print_status make
print_status go
print_status shellcheck

echo
if command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is available; run: make shellcheck-scripts"
else
  echo "shellcheck is missing; on Debian/Ubuntu, run: make install-shellcheck-linux"
fi
