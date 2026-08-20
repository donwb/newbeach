#!/bin/bash
# RETIRED 2026-08-14 — superseded by scripts/cam-restreamer.sh (MediaMTX relay).
# YouTube IP-locked its googlevideo HLS URLs in Aug 2026, so pushing resolved
# URLs to viewers yields a black player. Kept for reference only; do NOT cron
# this. See CLAUDE.md "Beach Cam Relay".
#
# Resolves the live HLS URL for every camera in the roster and pushes each back
# to the API. Runs on a residential-IP host (home Mac Studio) on a cron, because
# YouTube filters datacenter IPs — so this, not the server-side refresher, WAS
# the freshness mechanism before the relay took over.
#
# The roster is pulled from the API (GET /api/v2/admin/cameras), so adding or
# removing a camera is a database change, never an edit to this script.
#
# Usage:
#   ./update-stream-url.sh
#
# Requires: yt-dlp (brew install yt-dlp), jq (brew install jq)
#
# Configure these or set as environment variables:
API_BASE="${API_BASE:-https://beach.donwb.com}"
API_KEY="${API_KEY:-test-secret-123}"

set -uo pipefail

echo "Fetching camera roster from $API_BASE ..."
ROSTER=$(curl -sf -H "X-Api-Key: $API_KEY" "$API_BASE/api/v2/admin/cameras") || {
    echo "ERROR: failed to fetch camera roster"
    exit 1
}

COUNT=$(echo "$ROSTER" | jq '.cameras | length')
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
    echo "ERROR: roster is empty or unparseable"
    exit 1
fi
echo "Roster has $COUNT camera(s)."

FAILURES=0

# Iterate id<TAB>youtube_url pairs.
while IFS=$'\t' read -r ID YOUTUBE_URL; do
    [ -z "$ID" ] && continue
    echo "----"
    echo "[$ID] resolving: $YOUTUBE_URL"

    HLS_URL=$(yt-dlp -g --no-warnings -f "best[protocol=m3u8_native]" "$YOUTUBE_URL" 2>/dev/null)
    if [ -z "$HLS_URL" ]; then
        echo "[$ID] ERROR: failed to extract HLS URL — skipping"
        FAILURES=$((FAILURES + 1))
        continue
    fi
    echo "[$ID] got HLS URL (${#HLS_URL} chars), pushing..."

    RESPONSE=$(jq -nc --arg u "$HLS_URL" '{hls_url: $u}' | curl -sf -X POST \
        "$API_BASE/api/v2/admin/cameras/$ID/stream" \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        --data-binary @-) || {
        echo "[$ID] ERROR: API push failed"
        FAILURES=$((FAILURES + 1))
        continue
    }
    echo "[$ID] API response: $RESPONSE"
done < <(echo "$ROSTER" | jq -r '.cameras[] | [.id, .youtube_url] | @tsv')

echo "===="
if [ "$FAILURES" -gt 0 ]; then
    echo "Done with $FAILURES failure(s). Clients pick up new URLs within 60 seconds."
    exit 1
fi
echo "Done. All $COUNT cameras refreshed. Clients pick up new URLs within 60 seconds."
