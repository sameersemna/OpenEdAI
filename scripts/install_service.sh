#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/home/sameer/Public/Shared/Work/Projects/OpenEdAI"
SERVICE_NAME="openedai-gateway.service"

cd "$PROJECT_DIR"

echo "Building gateway binary..."
go build -o openedai-gateway ./cmd/gateway

sudo cp openedai-gateway /usr/local/bin/openedai-gateway
sudo chmod +x /usr/local/bin/openedai-gateway

sudo cp deploy/systemd/$SERVICE_NAME /etc/systemd/system/$SERVICE_NAME
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl restart $SERVICE_NAME

sudo systemctl status $SERVICE_NAME --no-pager
