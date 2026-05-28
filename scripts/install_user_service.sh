#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$HOME/Public/Shared/Work/Projects/OpenEdAI"
SERVICE_NAME="openedai-gateway.service"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

cd "$PROJECT_DIR"

echo "Building gateway binary..."
go build -o openedai-gateway ./cmd/gateway
chmod +x openedai-gateway

mkdir -p "$USER_SYSTEMD_DIR"
cp deploy/systemd/openedai-gateway.user.service "$USER_SYSTEMD_DIR/$SERVICE_NAME"

systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

systemctl --user status "$SERVICE_NAME" --no-pager

echo "If you need auto-start at boot without login session, run as root once:"
echo "  sudo loginctl enable-linger $USER"
