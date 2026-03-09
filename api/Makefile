.PHONY: dev run test lint build clean

# Load environment variables from .env file if it exists.
# Copy .env.example to .env and fill in your credentials.
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Run locally with hot reload (requires air: go install github.com/air-verse/air@latest)
dev:
	air

# Run without hot reload
run:
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
