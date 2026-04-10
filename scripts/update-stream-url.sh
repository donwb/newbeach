#!/bin/bash
# Extracts the HLS URL from the YouTube live stream and pushes it to the API.
#
# Usage:
#   ./update-stream-url.sh
#
# Requires: yt-dlp (brew install yt-dlp)
#
# Configure these or set as environment variables:
YOUTUBE_URL="${YOUTUBE_URL:-https://www.youtube.com/watch?v=kB2PZC-ow68}"
API_BASE="${API_BASE:-https://beach-ramp-status-kff7g.ondigitalocean.app}"
API_KEY="${API_KEY:-test-secret-123}"

set -euo pipefail

echo "Extracting HLS URL from: $YOUTUBE_URL"
HLS_URL=$(yt-dlp -g --no-warnings -f "best[protocol=m3u8_native]" "$YOUTUBE_URL" 2>/dev/null)

if [ -z "$HLS_URL" ]; then
    echo "ERROR: Failed to extract HLS URL"
    exit 1
fi

echo "Got HLS URL (${#HLS_URL} chars)"

echo "Pushing to API..."
RESPONSE=$(curl -s -X POST "$API_BASE/api/v2/admin/settings" \
    -H "X-Api-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"video_stream_url\", \"value\": \"$HLS_URL\"}")

echo "API response: $RESPONSE"
echo "Done. TV app will pick up the new URL within 60 seconds."
