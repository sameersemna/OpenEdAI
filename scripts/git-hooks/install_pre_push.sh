#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install the repository pre-push hook template.

Usage:
  scripts/git-hooks/install_pre_push.sh [--dry-run] [--force]

Options:
  --dry-run  Print actions without writing files
  --force    Overwrite an existing .git/hooks/pre-push without prompting
  -h, --help Show this help
EOF
}

dry_run=false
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel)"
src="$repo_root/scripts/git-hooks/pre-push.example"
dest="$repo_root/.git/hooks/pre-push"

if [[ ! -f "$src" ]]; then
  echo "hook template not found: $src" >&2
  exit 1
fi

if [[ -f "$dest" && "$force" != "true" ]]; then
  read -r -p "pre-push hook already exists. Overwrite? [y/N] " response
  case "$response" in
    [yY]|[yY][eE][sS]) ;;
    *)
      echo "aborted"
      exit 0
      ;;
  esac
fi

if [[ "$dry_run" == "true" ]]; then
  echo "[dry-run] cp \"$src\" \"$dest\""
  echo "[dry-run] chmod +x \"$dest\""
  exit 0
fi

cp "$src" "$dest"
chmod +x "$dest"

echo "installed pre-push hook: $dest"
