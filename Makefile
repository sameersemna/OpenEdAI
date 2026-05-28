.PHONY: tidy build run migrate setup install-service

tidy:
	go mod tidy

build:
	go build -o openedai-gateway ./cmd/gateway

run:
	go run ./cmd/gateway

migrate:
	psql "$${DATABASE_URL}" -f migrations/001_init.sql

setup:
	bash scripts/setup.sh

install-service:
	bash scripts/install_service.sh
