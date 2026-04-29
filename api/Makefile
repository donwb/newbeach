.PHONY: dev run test lint build clean db-up db-down check-env check-tools

# Load environment variables from .env file if it exists.
# Copy .env.example to .env and fill in your credentials.
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

COMPOSE_FILE := ../docker-compose.yml

# One-shot local dev: start postgres, validate prereqs, run API with hot reload.
dev: check-env check-tools db-up
	air

# Run without hot reload (still starts the db).
run: check-env db-up
	go run ./cmd/server

# Run tests
test:
	go test -race ./...

# Run linters
lint:
	go vet ./...
	staticcheck ./...

# Build binary
build:
	go build -o bin/beach-api ./cmd/server

# Clean build artifacts
clean:
	rm -rf bin/ tmp/

# Start the local Postgres container (no-op if already running).
db-up:
	@docker compose -f $(COMPOSE_FILE) up -d db
	@echo "waiting for postgres..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		docker compose -f $(COMPOSE_FILE) exec -T db pg_isready -U beach >/dev/null 2>&1 && exit 0; \
		sleep 1; \
	done; \
	echo "postgres did not become ready in 10s" >&2; exit 1

db-down:
	docker compose -f $(COMPOSE_FILE) down

# Verify .env exists; otherwise tell the user how to create one.
check-env:
	@if [ ! -f .env ]; then \
		echo "ERROR: api/.env not found."; \
		echo "Run: cp .env.example .env  (then edit DATABASE_URL + ADMIN_API_KEY)"; \
		exit 1; \
	fi

# Verify required dev tools are on PATH.
check-tools:
	@command -v air      >/dev/null || { echo "ERROR: 'air' not found. Install: go install github.com/air-verse/air@latest"; exit 1; }
	@command -v yt-dlp   >/dev/null || { echo "WARN: 'yt-dlp' not on PATH — /api/v2/video/refresh will fail. Install: brew install yt-dlp"; }
