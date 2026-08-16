#!/bin/bash
# Continuously restreams every camera in the roster from YouTube to the relay
# droplet, which serves stable HLS URLs to all platforms.
#
# Why this exists: YouTube's googlevideo HLS URLs became IP-locked and
# client-checked (Aug 2026), so the old model — resolve a URL at home and hand
# it to viewers — silently broke: manifests load but every segment fetch 403s,
# giving players a black screen. Now this host (residential IP) downloads the
# video itself and re-publishes it over RTMP to MediaMTX on the relay, which
# serves it at a STABLE per-camera URL:
#
#     https://<relay>/<camera-id>/index.m3u8
#
# Pipeline per camera: yt-dlp (mweb player client — its HLS URLs sustain where
# the default web client's get cut off after the DVR window) -> ffmpeg remux
# (-c copy, no transcode) -> RTMP publish. A watchdog restarts a camera's
# pipeline if ffmpeg's progress file stops advancing (YouTube cut the session),
# and the whole roster is refreshed + restarted every ROSTER_REFRESH seconds.
#
# The roster comes from GET /api/v2/admin/cameras, so adding/removing a camera
# is a database change, never an edit to this script. A camera whose stream is
# offline (e.g. Ormond Beach) retries with exponential backoff, RETRY_SECS
# doubling up to RETRY_MAX — resolving a dead video every 2 minutes is exactly
# the anonymous-automation pattern that got the home IP bot-checked. A pipeline
# that was streaming and dropped (the common YouTube session cut) recovers at
# a flat RETRY_STREAMED — kept short because every second of it is viewer-
# visible downtime, and a host that just streamed for minutes is not the
# bot-check-drawing pattern that dead-video polling is.
#
# Requires: yt-dlp, ffmpeg, jq, curl   (brew install yt-dlp ffmpeg jq)
#
# Config via environment or ~/.cam-restreamer.env:
#   API_BASE        beach API base URL
#   API_KEY         admin API key (roster fetch)
#   RELAY_HOST      relay droplet host/IP (RTMP ingest)
#   RELAY_PUB_PASS  MediaMTX publisher password
#   YTDLP_COOKIES   optional path to a Netscape cookies.txt exported from a
#                   browser signed into YouTube. Needed since Aug 2026:
#                   YouTube bot-checks anonymous yt-dlp resolves ("Sign in to
#                   confirm you're not a bot"), so without cookies a dropped
#                   pipeline can never re-resolve its stream.
#
# Runs under launchd: see scripts/com.donwb.cam-restreamer.plist

set -uo pipefail

ENV_FILE="$HOME/.cam-restreamer.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

API_BASE="${API_BASE:-https://beach.donwb.com}"
API_KEY="${API_KEY:?set API_KEY (admin api key)}"
RELAY_HOST="${RELAY_HOST:?set RELAY_HOST (relay droplet ip/host)}"
RELAY_PUB_PASS="${RELAY_PUB_PASS:?set RELAY_PUB_PASS (mediamtx publisher password)}"
YTDLP_COOKIES="${YTDLP_COOKIES:-}"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/cam-restreamer}"

STALL_SECS=60        # restart a pipeline if ffmpeg makes no progress this long
RETRY_STREAMED=30    # retry after a stream that was up and dropped
RETRY_SECS=120       # base delay for resolve-failure backoff + roster retries
RETRY_MAX=1800       # backoff cap for streams that fail to resolve at all
ROSTER_REFRESH=21600 # full roster re-fetch + clean restart (6h)

mkdir -p "$LOG_DIR"

log() { echo "$(date '+%F %T') $*"; }

# Optional YouTube cookies for yt-dlp (empty array when unset). Expanded with
# the ${arr[@]+...} idiom so set -u survives an empty array on bash 3.2.
COOKIE_ARGS=()
if [ -n "$YTDLP_COOKIES" ]; then
    if [ -r "$YTDLP_COOKIES" ]; then
        COOKIE_ARGS=(--cookies "$YTDLP_COOKIES")
    else
        log "WARNING: YTDLP_COOKIES=$YTDLP_COOKIES not readable, resolving without cookies"
    fi
fi

# Kill one camera's whole pipeline: the remux ffmpeg, yt-dlp, and yt-dlp's
# internal downloader ffmpeg (its cmdline contains the googlevideo URL with
# the video id, which plain child-killing misses once orphaned).
kill_pipeline() {
    local id="$1" vid="$2" pid="$3"
    kill -TERM "$pid" 2>/dev/null
    pkill -TERM -f "watch\?v=$vid" 2>/dev/null
    pkill -TERM -f "/id/$vid" 2>/dev/null
    sleep 2
    kill -KILL "$pid" 2>/dev/null
    pkill -KILL -f "watch\?v=$vid" 2>/dev/null
    pkill -KILL -f "/id/$vid" 2>/dev/null
}

# Restream one camera forever. $1=camera id, $2=youtube watch URL
stream_one() {
    local id="$1" yt="$2"
    local vid="${yt##*v=}"
    local log_f="$LOG_DIR/$id.log"
    local prog="$LOG_DIR/$id.progress"
    local delay=$(( RETRY_SECS / 2 ))  # doubled before first use

    while true; do
        log "[$id] starting pipeline ($yt)" >> "$log_f"
        rm -f "$prog"
        yt-dlp --no-warnings --no-part \
            --extractor-args "youtube:player_client=mweb" \
            ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} \
            -f "best[protocol^=m3u8]" -o - "$yt" 2>> "$log_f" \
            | ffmpeg -hide_banner -loglevel error -nostdin \
                -i pipe:0 -c copy -f flv -progress "$prog" \
                "rtmp://$RELAY_HOST:1935/$id?user=publisher&pass=$RELAY_PUB_PASS" \
                >> "$log_f" 2>&1 &
        local pid=$!

        # Watchdog: ffmpeg rewrites $prog every ~1s while data flows.
        while kill -0 "$pid" 2>/dev/null; do
            sleep 15
            if [ -f "$prog" ]; then
                local age=$(( $(date +%s) - $(stat -f %m "$prog") ))
                if [ "$age" -gt "$STALL_SECS" ]; then
                    log "[$id] stalled (${age}s without progress), restarting" >> "$log_f"
                    kill_pipeline "$id" "$vid" "$pid"
                    break
                fi
            fi
        done
        wait "$pid" 2>/dev/null

        # ffmpeg CREATES $prog at startup but only WRITES to it once data
        # moves, so the streamed-vs-never-streamed test must be -s (non-empty),
        # not -f: with -f a dead camera looks "streamed" on every attempt and
        # the exponential backoff never engages (this is how ormond-beach spent
        # days re-resolving every 2 minutes). Streamed-then-dropped gets a flat
        # fast retry; never-streamed doubles its delay up to RETRY_MAX.
        if [ -s "$prog" ]; then
            delay="$RETRY_STREAMED"
        else
            delay=$(( delay * 2 ))
            [ "$delay" -gt "$RETRY_MAX" ] && delay="$RETRY_MAX"
        fi
        log "[$id] pipeline down, retrying in ${delay}s" >> "$log_f"
        sleep "$delay"
    done
}

log "fetching roster from $API_BASE"
while true; do
    ROSTER=$(curl -sf -H "X-Api-Key: $API_KEY" "$API_BASE/api/v2/admin/cameras") || {
        log "ERROR: roster fetch failed, retrying in ${RETRY_SECS}s"
        sleep "$RETRY_SECS"
        continue
    }

    PIDS=()
    VIDS=()
    while IFS=$'\t' read -r ID YT; do
        [ -z "$ID" ] && continue
        stream_one "$ID" "$YT" &
        PIDS+=($!)
        VIDS+=("${YT##*v=}")
        log "spawned restreamer for $ID"
    done < <(echo "$ROSTER" | jq -r '.cameras[] | [.id, .youtube_url] | @tsv')

    if [ "${#PIDS[@]}" -eq 0 ]; then
        log "ERROR: roster empty, retrying in ${RETRY_SECS}s"
        sleep "$RETRY_SECS"
        continue
    fi

    # Let everything run, then do a clean restart to pick up roster changes.
    sleep "$ROSTER_REFRESH"
    log "roster refresh: stopping all pipelines"
    for i in "${!PIDS[@]}"; do
        kill -TERM "${PIDS[$i]}" 2>/dev/null
        pkill -TERM -f "watch\?v=${VIDS[$i]}" 2>/dev/null
        pkill -TERM -f "/id/${VIDS[$i]}" 2>/dev/null
    done
    sleep 3
    for i in "${!PIDS[@]}"; do
        kill -KILL "${PIDS[$i]}" 2>/dev/null
        pkill -KILL -f "watch\?v=${VIDS[$i]}" 2>/dev/null
        pkill -KILL -f "/id/${VIDS[$i]}" 2>/dev/null
    done
done
