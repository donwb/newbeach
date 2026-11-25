#!/bin/bash
# Notices when the beach cams go dark and fixes what it can, so Don doesn't
# have to spot the stills and ask. Runs every 10 minutes under launchd on the
# Mac Studio (scripts/com.donwb.cam-watchdog.plist), beside the restreamer it
# watches. Three layers, cheapest first:
#
#   1. Known fixes, no AI. The PO-token plugin missing from yt-dlp's venv
#      (every `brew upgrade yt-dlp` removes it) is reinstalled on sight. An
#      outage whose logs show yt-dlp failing to resolve ("No video formats
#      found", n-challenge errors — YouTube rotated its player JS and the
#      installed yt-dlp can't solve it; 2026-11-24, 14h of stills) gets
#      `brew upgrade yt-dlp` + plugin reinstall + a test resolve + restreamer
#      restart. At most once per FIX_COOLDOWN.
#   2. Headless Claude for everything else. If the outage outlives layer 1 (or
#      layer 1 had nothing to try), `claude -p` runs in the repo with the
#      incident facts, reads docs/CAM-RELAY.md, and may apply only the fixes on
#      an explicit allowlist (--permission-mode dontAsk denies the rest). No
#      repo edits, no commits. Once per incident, at most once per
#      CLAUDE_COOLDOWN.
#   3. Email. Every action and its outcome, any escalation report, and the
#      recovery go to ALERT_EMAIL_TO over SMTP (curl). Unconfigured, alerts
#      land in the log only.
#
# "Outage" = a majority of the roster's cams not serving HLS from the relay
# (DOWN_MIN overrides) on two consecutive runs. A single cam dying upstream is
# routine (Ormond-by-the-Sea has been dead for weeks) — clients show its still,
# and nobody needs an email about it. Quiet hours (the restreamer's own
# QUIET_HOURS window, every cam dark by design) are skipped entirely.
#
# Config: ~/.cam-restreamer.env (shared with the restreamer — API_KEY,
# QUIET_HOURS) plus, for email:
#   ALERT_EMAIL_TO   recipient
#   SMTP_USER        sending account (also the From address)
#   SMTP_PASS        its password — for Gmail an app password
#   SMTP_URL         default smtps://smtp.gmail.com:465
#
# Usage: cam-watchdog.sh            one check (what launchd runs)
#        cam-watchdog.sh --test-email   send a test email and exit
#        cam-watchdog.sh --status       print state and cam health, change nothing

set -uo pipefail

ENV_FILE="$HOME/.cam-restreamer.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

API_BASE="${API_BASE:-https://beach.donwb.com}"
API_KEY="${API_KEY:-}"
RELAY_HLS_BASE="${RELAY_HLS_BASE:-https://cams.donwb.com}"
QUIET_HOURS="${QUIET_HOURS-23-6}"
RESTREAMER_LABEL="com.donwb.cam-restreamer"
CAM_LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/cam-restreamer}"
REPO_DIR="${REPO_DIR:-$HOME/dev/newbeach}"
STATE_DIR="$HOME/.cam-watchdog"
WD_LOG="$HOME/Library/Logs/cam-watchdog.log"
YTDLP_PY="/opt/homebrew/opt/yt-dlp/libexec/bin/python"
POT_SERVER="http://127.0.0.1:4416"

ALERT_EMAIL_TO="${ALERT_EMAIL_TO:-}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_URL="${SMTP_URL:-smtps://smtp.gmail.com:465}"

DOWN_MIN="${DOWN_MIN:-}"            # empty = majority of the roster
CONFIRM_RUNS=2                       # consecutive down checks before acting
FIX_COOLDOWN=$(( 6 * 3600 ))         # layer 1 brew upgrade, at most this often
CLAUDE_COOLDOWN=$(( 6 * 3600 ))      # layer 2, at most this often
CLAUDE_TIMEOUT=900                   # seconds before a stuck claude run is killed
CLAUDE_BUDGET_USD="${CLAUDE_BUDGET_USD:-3}"
RECOVER_WAIT="${RECOVER_WAIT:-120}"                    # seconds to let cams come back after a restart

mkdir -p "$STATE_DIR" "$(dirname "$WD_LOG")"

# stderr, so log lines never leak into a $(...) capture (the claude report).
log() { echo "$(date '+%F %T') $*" >&2; }

# ---------------------------------------------------------------- state ----
# One file per key under $STATE_DIR; absent = unset.
sget() { cat "$STATE_DIR/$1" 2>/dev/null; }
sset() { echo "$2" > "$STATE_DIR/$1"; }
sdel() { rm -f "$STATE_DIR/$1"; }
now() { date +%s; }

# ---------------------------------------------------------------- email ----
send_email() {
    local subject="$1" body="$2"
    log "ALERT: $subject"
    if [ -z "$ALERT_EMAIL_TO" ] || [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASS" ]; then
        log "  (email not configured — set ALERT_EMAIL_TO, SMTP_USER, SMTP_PASS in $ENV_FILE)"
        printf '%s\n' "$body" | sed 's/^/  | /' >&2
        return 0
    fi
    local msg
    msg=$(mktemp "$STATE_DIR/mail.XXXXXX")
    {
        printf 'From: Beach cam watchdog <%s>\r\n' "$SMTP_USER"
        printf 'To: %s\r\n' "$ALERT_EMAIL_TO"
        printf 'Subject: [beach cams] %s\r\n' "$subject"
        printf 'Date: %s\r\n' "$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"
        printf 'Content-Type: text/plain; charset=utf-8\r\n\r\n'
        printf '%s\n' "$body" | sed 's/$/\r/'
    } > "$msg"
    # Credentials go in a curl config on a pipe, not argv, so they never show in ps.
    if printf 'user = "%s:%s"\n' "$SMTP_USER" "$SMTP_PASS" | \
        curl -sS --max-time 30 --ssl-reqd -K - --url "$SMTP_URL" \
            --mail-from "$SMTP_USER" --mail-rcpt "$ALERT_EMAIL_TO" \
            --upload-file "$msg"; then
        log "  emailed $ALERT_EMAIL_TO"
    else
        log "  ERROR: email send failed"
    fi
    rm -f "$msg"
}

# ---------------------------------------------------------- quiet hours ----
# Same window semantics as the restreamer (START-END local hours, wraps midnight).
in_quiet_hours() {
    [[ "$QUIET_HOURS" =~ ^([0-9]{1,2})-([0-9]{1,2})$ ]] || return 1
    local s=$(( 10#${BASH_REMATCH[1]} % 24 )) e=$(( 10#${BASH_REMATCH[2]} % 24 ))
    local h=$(( 10#$(date +%H) ))
    [ "$s" -eq "$e" ] && return 1
    if [ "$s" -lt "$e" ]; then [ "$h" -ge "$s" ] && [ "$h" -lt "$e" ]
    else [ "$h" -ge "$s" ] || [ "$h" -lt "$e" ]; fi
}

# ------------------------------------------------------------- probing ----
# Prints "id<TAB>youtube_url" per roster camera. Falls back to the last good
# roster if the API is unreachable (an API outage is not a cam outage).
roster() {
    local r
    if [ -n "$API_KEY" ] && r=$(curl -sf --max-time 20 -H "X-Api-Key: $API_KEY" \
            "$API_BASE/api/v2/admin/cameras" | jq -r '.cameras[] | [.id, .youtube_url] | @tsv' 2>/dev/null) \
            && [ -n "$r" ]; then
        echo "$r" > "$STATE_DIR/roster.tsv"
        echo "$r"
    else
        cat "$STATE_DIR/roster.tsv" 2>/dev/null
    fi
}

# Captured, not piped into head/grep -q: under pipefail an early-exiting
# reader SIGPIPEs the writer and turns a match into a failure.
cam_up() {
    local body
    body=$(curl -sfL --max-time 10 "$RELAY_HLS_BASE/$1/index.m3u8" 2>/dev/null) || return 1
    [[ "$body" == "#EXTM3U"* ]]
}

restreamer_running() {
    launchctl print "gui/$(id -u)/$RESTREAMER_LABEL" 2>/dev/null | grep -qE '^\s+state = running'
}

restart_restreamer() {
    log "  restarting $RESTREAMER_LABEL"
    launchctl kickstart -k "gui/$(id -u)/$RESTREAMER_LABEL"
}

# ------------------------------------------------------------- layer 1 ----
plugin_installed() {
    "$YTDLP_PY" -m pip show -q bgutil-ytdlp-pot-provider >/dev/null 2>&1
}

# Reinstall the PO-token plugin at the version the running token server reports.
reinstall_plugin() {
    local ver
    ver=$(curl -sf --max-time 5 "$POT_SERVER/ping" | jq -r '.version // empty' 2>/dev/null)
    if [ -z "$ver" ]; then
        log "  token server at $POT_SERVER not answering — can't pick a plugin version"
        return 1
    fi
    log "  installing bgutil-ytdlp-pot-provider==$ver"
    "$YTDLP_PY" -m pip install -q "bgutil-ytdlp-pot-provider==$ver"
}

# Does yt-dlp resolve this cam's stream right now? Same flags as the restreamer.
test_resolve() {
    yt-dlp -4 --simulate --no-warnings --extractor-args "youtube:player_client=mweb" \
        -f "best[protocol^=m3u8]" "$1" >/dev/null 2>&1
}

# True when the down cams' recent log lines show yt-dlp failing to resolve —
# the outdated-yt-dlp signature, as opposed to segment 403s (bot wall) or a
# relay/network problem, which an upgrade can't fix.
resolve_failure_signature() {
    local id recent=""
    for id in "$@"; do
        recent+=$(tail -n 200 "$CAM_LOG_DIR/$id.log" 2>/dev/null)$'\n'
    done
    grep -qE 'No video formats found|n challenge solving failed|Error solving n challenge|Requested format is not available' <<< "$recent"
}

# ------------------------------------------------------------- layer 2 ----
run_with_timeout() {
    local secs="$1"; shift
    "$@" &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 5; waited=$(( waited + 5 ))
        if [ "$waited" -ge "$secs" ]; then
            log "  timed out after ${secs}s, killing"
            kill -TERM "$pid" 2>/dev/null; sleep 5; kill -KILL "$pid" 2>/dev/null
            return 124
        fi
    done
    wait "$pid"
}

escalate_to_claude() {
    local facts="$1" report="$STATE_DIR/claude-report.txt"
    if ! command -v claude >/dev/null 2>&1; then
        echo "claude CLI not on PATH ($PATH) — escalation skipped."
        return 1
    fi
    if [ ! -d "$REPO_DIR" ]; then
        echo "Repo not found at $REPO_DIR — escalation skipped."
        return 1
    fi
    local prompt
    prompt="You are the beach cam watchdog's escalation step, running unattended on the Mac Studio
(no human is watching; nobody can answer questions). The camera restreamer has an outage that the
watchdog's scripted fixes did not clear. Facts:

$facts

Do this:
1. Read docs/CAM-RELAY.md (the runbook) — especially the failure-mode sections.
2. Diagnose from the per-camera logs in $CAM_LOG_DIR and the commands you are allowed to run.
   Note quiet hours, IPv6, the PO-token plugin, yt-dlp version, and bot-wall 403s are all covered there.
3. If a runbook fix applies and your allowed commands can perform it, apply it, restart the
   restreamer, wait about two minutes, and check \`make restreamer-status\`.
4. Do NOT edit or create files in the repo, do NOT commit, do NOT touch the relay droplet.
   If the fix needs anything outside your allowed commands, say exactly what Don should run.

Your final message is emailed to Don verbatim. Make its FIRST line a one-sentence summary
(e.g. \"Fixed: upgraded yt-dlp, all four live cams back\" or \"Not fixed: segments 403 on every
cam — looks like the home IP is bot-walled\"), then a blank line, then a short plain-text
explanation: what you found, what you did, what's left. No markdown headings."

    local allowed=(
        "Read" "Grep" "Glob"
        "Bash(make restreamer-status)" "Bash(make restreamer-diff)"
        "Bash(tail *)" "Bash(grep *)" "Bash(head *)" "Bash(ls *)" "Bash(cat *)" "Bash(date *)"
        "Bash(yt-dlp *)" "Bash(ffmpeg -version)" "Bash(ffprobe *)"
        "Bash(brew outdated *)" "Bash(brew info *)" "Bash(brew upgrade yt-dlp)" "Bash(brew list *)"
        "Bash(curl -s http://127.0.0.1:4416/ping)" "Bash(curl -sL *cams.donwb.com*)" "Bash(curl -sI *cams.donwb.com*)"
        "Bash($YTDLP_PY -m pip show *)" "Bash($YTDLP_PY -m pip install bgutil-ytdlp-pot-provider*)"
        "Bash(launchctl print *)" "Bash(launchctl kickstart -k gui/*/com.donwb.cam-restreamer)"
        "Bash(ifconfig *)" "Bash(networksetup -getinfo *)" "Bash(sleep *)"
    )
    log "  escalating to claude (budget \$$CLAUDE_BUDGET_USD, timeout ${CLAUDE_TIMEOUT}s)"
    # CAM_WATCHDOG=1 tells the repo's Stop hook (ATC status guard) to stand
    # down — otherwise its prompt becomes the final message we email.
    (cd "$REPO_DIR" && export CAM_WATCHDOG=1 && run_with_timeout "$CLAUDE_TIMEOUT" \
        claude -p "$prompt" \
            --permission-mode dontAsk \
            --allowedTools "${allowed[@]}" \
            --max-budget-usd "$CLAUDE_BUDGET_USD" \
            --output-format text) > "$report" 2>&1
    local rc=$?
    log "  claude exited $rc"
    cat "$report"
    [ "$rc" -eq 0 ]
}

# Recent, readable log excerpt for the down cams (googlevideo URLs are 1.5 KB
# of noise each — cut every line to 240 chars).
log_excerpt() {
    local id
    for id in "$@"; do
        echo "--- $id (last 25 lines of $CAM_LOG_DIR/$id.log) ---"
        tail -n 400 "$CAM_LOG_DIR/$id.log" 2>/dev/null | grep -vE '^(frame=|\[hls)' | tail -n 25 | cut -c1-240
    done
}

# ---------------------------------------------------------------- check ----
probe_all() {
    # Sets globals: ROSTER_IDS, DOWN_IDS, UP_IDS, NEED
    ROSTER_IDS=() DOWN_IDS=() UP_IDS=()
    local id yt
    while IFS=$'\t' read -r id yt; do
        [ -z "$id" ] && continue
        ROSTER_IDS+=("$id")
        if cam_up "$id"; then UP_IDS+=("$id"); else DOWN_IDS+=("$id"); fi
    done < <(roster)
    local n=${#ROSTER_IDS[@]}
    NEED=${DOWN_MIN:-$(( n / 2 + 1 ))}
}

yt_url_for() {
    awk -F'\t' -v id="$1" '$1 == id { print $2 }' "$STATE_DIR/roster.tsv" 2>/dev/null
}

status() {
    probe_all
    echo "roster: ${ROSTER_IDS[*]:-none}"
    echo "up:     ${UP_IDS[*]:-none}"
    echo "down:   ${DOWN_IDS[*]:-none}   (outage at >= $NEED down)"
    echo "restreamer running: $(restreamer_running && echo yes || echo NO)"
    echo "PO-token plugin:    $(plugin_installed && echo installed || echo MISSING)"
    echo "quiet hours now:    $(in_quiet_hours && echo yes || echo no) ($QUIET_HOURS)"
    echo "email:              $([ -n "$ALERT_EMAIL_TO" ] && [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ] && echo "configured → $ALERT_EMAIL_TO" || echo "NOT configured")"
    echo "state:"
    local f
    for f in down_streak incident_since fix_at claude_at; do
        printf '  %-15s %s\n' "$f" "$(sget $f || true)"
    done
}

main() {
    if in_quiet_hours; then
        sdel down_streak
        return 0
    fi

    # The restreamer itself not running is an outage regardless of the probes.
    if ! restreamer_running; then
        log "restreamer not running — starting it"
        restart_restreamer
        send_email "restreamer was not running — restarted" \
"The watchdog found $RESTREAMER_LABEL not running and kickstarted it.
Check \`make restreamer-status\` and /tmp/cam-restreamer.launchd.log if this repeats."
        return 0
    fi

    # Layer 1, standing check: the plugin goes missing on every yt-dlp upgrade
    # (by hand, by brew, or by this script) and nothing else notices.
    if ! plugin_installed; then
        log "PO-token plugin missing from yt-dlp's venv — reinstalling"
        if reinstall_plugin && plugin_installed; then
            restart_restreamer
            send_email "PO-token plugin reinstalled" \
"bgutil-ytdlp-pot-provider was missing from yt-dlp's venv (a yt-dlp upgrade removes it).
The watchdog reinstalled it at the token server's version and restarted the restreamer.
No action needed."
        else
            send_email "PO-token plugin missing and reinstall FAILED" \
"bgutil-ytdlp-pot-provider is missing from yt-dlp's venv and the watchdog couldn't reinstall it.
See ~/Library/Logs/cam-watchdog.log, and the PO-token section of docs/CAM-RELAY.md."
        fi
    fi

    probe_all
    local ndown=${#DOWN_IDS[@]}

    if [ "${#ROSTER_IDS[@]}" -eq 0 ]; then
        log "no roster (API unreachable and no cached copy) — skipping"
        return 0
    fi

    # ---- healthy ----
    if [ "$ndown" -lt "$NEED" ]; then
        sdel down_streak
        local since
        since=$(sget incident_since)
        if [ -n "$since" ]; then
            local mins=$(( ($(now) - since) / 60 ))
            log "recovered after ${mins} min (up: ${UP_IDS[*]})"
            send_email "recovered — ${#UP_IDS[@]} of ${#ROSTER_IDS[@]} cams live" \
"The cams are back after about ${mins} minutes.
Live: ${UP_IDS[*]}
Still down: ${DOWN_IDS[*]:-none}"
            sdel incident_since
        fi
        return 0
    fi

    # ---- down: confirm across runs before acting ----
    local streak=$(( $(sget down_streak || echo 0) + 1 ))
    sset down_streak "$streak"
    log "$ndown/${#ROSTER_IDS[@]} cams down (${DOWN_IDS[*]}), streak $streak"
    [ "$streak" -lt "$CONFIRM_RUNS" ] && return 0

    local new_incident=0
    if [ -z "$(sget incident_since)" ]; then
        sset incident_since "$(now)"
        new_incident=1
        sdel claude_at_incident
    fi
    local since_h
    since_h=$(date -r "$(sget incident_since)" '+%a %-I:%M %p')

    # ---- layer 1: the outdated-yt-dlp signature ----
    local fix_at fix_note=""
    fix_at=$(sget fix_at || echo 0)
    if resolve_failure_signature "${DOWN_IDS[@]}"; then
        if [ $(( $(now) - fix_at )) -ge "$FIX_COOLDOWN" ]; then
            sset fix_at "$(now)"
            log "layer 1: yt-dlp resolve failures — upgrading"
            local before after
            before=$(yt-dlp --version 2>/dev/null)
            brew update >/dev/null 2>&1
            brew upgrade yt-dlp >/dev/null 2>&1
            after=$(yt-dlp --version 2>/dev/null)
            plugin_installed || reinstall_plugin
            local test_url resolve="untested"
            test_url=$(yt_url_for "${DOWN_IDS[0]}")
            if [ -n "$test_url" ]; then
                if test_resolve "$test_url"; then resolve="resolves"; else resolve="still FAILS to resolve"; fi
            fi
            restart_restreamer
            sleep "$RECOVER_WAIT"
            probe_all
            fix_note="Layer 1 (scripted): yt-dlp $before → $after, PO-token plugin $(plugin_installed && echo present || echo MISSING), ${DOWN_IDS[0]:-test cam} $resolve, restreamer restarted.
After ${RECOVER_WAIT}s: live ${UP_IDS[*]:-none}; down ${DOWN_IDS[*]:-none}."
            log "  $fix_note"
            if [ "${#DOWN_IDS[@]}" -lt "$NEED" ]; then
                sdel down_streak
                sdel incident_since
                send_email "fixed — yt-dlp upgraded, cams back" \
"The cams went dark at $since_h with yt-dlp failing to resolve (the outdated-yt-dlp signature
in docs/CAM-RELAY.md). The watchdog fixed it:

$fix_note"
                return 0
            fi
        else
            fix_note="Layer 1 skipped: already tried at $(date -r "$fix_at" '+%a %-I:%M %p') (cooldown $(( FIX_COOLDOWN / 3600 ))h)."
        fi
    else
        fix_note="Layer 1: nothing scripted applies (logs don't show the yt-dlp resolve-failure signature)."
    fi

    # ---- layer 2: claude, once per incident ----
    local claude_at
    claude_at=$(sget claude_at || echo 0)
    if [ -n "$(sget claude_at_incident)" ]; then
        log "still down; claude already ran this incident — waiting for recovery or Don"
        return 0
    fi
    if [ $(( $(now) - claude_at )) -lt "$CLAUDE_COOLDOWN" ]; then
        log "still down; claude cooldown — not escalating"
        [ "$new_incident" -eq 1 ] && send_email "cams down since $since_h — not escalated (cooldown)" \
"$ndown of ${#ROSTER_IDS[@]} cams down: ${DOWN_IDS[*]}
$fix_note
Claude last ran $(date -r "$claude_at" '+%a %-I:%M %p'); the next escalation waits out the $(( CLAUDE_COOLDOWN / 3600 ))h cooldown."
        return 0
    fi
    sset claude_at "$(now)"
    sset claude_at_incident 1

    local facts report rc subject
    facts="Now: $(date '+%a %F %T %Z'). Down since about $since_h.
Down ($ndown of ${#ROSTER_IDS[@]}): ${DOWN_IDS[*]}
Up: ${UP_IDS[*]:-none}
Note: ormond-by-the-sea has been dead upstream since 2026-11-23 (known, not this outage).
yt-dlp: $(yt-dlp --version 2>/dev/null)   PO-token plugin: $(plugin_installed && echo installed || echo MISSING)
$fix_note

$(log_excerpt "${DOWN_IDS[@]}")"
    report=$(escalate_to_claude "$facts"); rc=$?
    probe_all
    if [ "${#DOWN_IDS[@]}" -lt "$NEED" ]; then
        sdel down_streak
        sdel incident_since
        subject="back up — $(echo "$report" | head -1 | cut -c1-90)"
    elif [ "$rc" -eq 0 ]; then
        # Our own probe, not Claude's claim, decides "still down".
        subject="still down — $(echo "$report" | head -1 | cut -c1-90)"
    else
        subject="cams down since $since_h — escalation failed (exit $rc)"
    fi
    send_email "$subject" \
"$report

-- watchdog facts --
$facts
After escalation: live ${UP_IDS[*]:-none}; down ${DOWN_IDS[*]:-none}."
}

case "${1:-}" in
    --test-email)
        send_email "test" "Test from cam-watchdog on $(hostname -s) at $(date). If you got this, alerts work."
        ;;
    --status)
        status
        ;;
    "")
        exec >> "$WD_LOG" 2>&1
        main
        ;;
    *)
        echo "usage: $0 [--test-email|--status]" >&2; exit 2
        ;;
esac
