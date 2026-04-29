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

# python3 is required by yt-dlp; ffmpeg is not needed (we only use -g to print
# the HLS URL, no muxing/transcoding).
RUN apk add --no-cache ca-certificates tzdata python3 curl \
    && curl -fsSL -o /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp \
    && apk del curl

COPY --from=builder /beach-api /beach-api
COPY --from=builder /build/api/migrations /migrations
COPY --from=builder /build/web /web

ENV WEB_DIR=/web
ENV YT_DLP_PATH=/usr/local/bin/yt-dlp

EXPOSE 8080

ENTRYPOINT ["/beach-api"]
