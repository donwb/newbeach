FROM golang:1.24-alpine AS builder

WORKDIR /build

# Install git for module downloads
RUN apk add --no-cache git

# Copy module files first for layer caching
COPY api/go.mod api/go.sum ./api/
WORKDIR /build/api
RUN go mod download

# Copy source code
WORKDIR /build
COPY api/ ./api/
COPY web/ ./web/

# Build static binary
WORKDIR /build/api
RUN CGO_ENABLED=0 GOOS=linux go build -o /beach-api ./cmd/server

# Runtime stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /beach-api /beach-api
COPY --from=builder /build/api/migrations /migrations
COPY --from=builder /build/web /web

ENV WEB_DIR=/web

EXPOSE 8080

ENTRYPOINT ["/beach-api"]
