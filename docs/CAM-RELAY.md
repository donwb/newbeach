# Beach Cam Relay — Architecture & Runbook

*Built 2026-08-14. Replaces the retired `scripts/update-stream-url.sh` URL-push cron.*

## Why this exists

In August 2026 YouTube locked down its `googlevideo.com` live-HLS URLs:

- **IP-locked** — media segments only serve to the exact IP that resolved the URL
  (even another address on the same /64 gets 403). Manifests still load anywhere,
  so players start up and then render black.
- **Client-checked** — fetches must look like the client the URL was minted for;
  plain ffmpeg with a Lavf user agent gets cut off after the ~40s DVR window.
- **Intermittent** — enforcement is A/B'd server-side; the same URL can work one
  hour and 403 the next. This is why the cams "sometimes worked."

So the old model — resolve HLS URLs at home with yt-dlp and hand them to viewers —
is permanently dead. Nobody but the resolving machine can play those URLs.

## How it works now

```
county cams → YouTube Live
                  │  yt-dlp (mweb player client) downloads;
                  │  ffmpeg remuxes -c copy (no transcode)
                  ▼
  Mac Studio (home, residential IP — YouTube blocks datacenter IPs)
  launchd: com.donwb.cam-restreamer → ~/bin/cam-restreamer.sh
                  │  RTMP publish, password-protected, one path per camera id
                  ▼
  beach-cam-relay droplet (DigitalOcean nyc3, 68.183.149.152, $6/mo)
  MediaMTX (RTMP :1935 in, HLS out) behind Caddy auto-TLS
                  │  stable URLs: https://cams.donwb.com/<camera-id>/index.m3u8
                  ▼
  web (hls.js) · iOS/iPadOS · tvOS (AVPlayer) — via the roster's stream_url
```

Key properties:

- **Stream URLs never rotate.** The roster's `stream_url` values are permanent;
  the whole resolve-and-push-URLs cycle is gone.
- **No transcoding.** ffmpeg copies the H.264/AAC bitstream; CPU cost ≈ zero.
  Home upload is fixed at ~0.4–2.5 Mbps per camera regardless of viewer count.
- **The mweb client is load-bearing.** yt-dlp must run with
  `--extractor-args "youtube:player_client=mweb"`. The default web client's URLs
  die after the DVR window; ios/tv/web_safari return no formats at all (as of
  yt-dlp 2026.07.04).
- **Self-healing.** Each camera runs in its own supervised loop: a watchdog
  restarts the pipeline if ffmpeg's progress file goes stale (>60s), YouTube's
  ~6h URL expiry just triggers a restart (2 min retry after any session that
  streamed), and the whole roster re-fetches + restarts every 6h (picks up
  roster changes). launchd restarts the supervisor itself if it dies. A camera
  that fails to *resolve* at all (offline broadcast, bot-checked) backs off
  exponentially, 2 min doubling to a 30 min cap — hammering YouTube's player
  API every 2 min from one IP is what drew the Aug 2026 bot-wall.

## Components & where things live

| What | Where |
|------|-------|
| Restreamer script (source of truth) | `scripts/cam-restreamer.sh` in this repo |
| Installed copy on Mac Studio | `~/bin/cam-restreamer.sh` |
| launchd job | `~/Library/LaunchAgents/com.donwb.cam-restreamer.plist` (source: `scripts/com.donwb.cam-restreamer.plist`) |
| Studio config/secrets | `~/.cam-restreamer.env` (API_KEY, RELAY_HOST, RELAY_PUB_PASS, YTDLP_COOKIES) |
| Studio logs | `~/Library/Logs/cam-restreamer/<cam-id>.log` + `/tmp/cam-restreamer.launchd.log` |
| Relay droplet | `beach-cam-relay`, DO nyc3, 68.183.149.152 (ssh root@, ProMax key) |
| MediaMTX config (incl. publisher password) | droplet `/opt/mediamtx/mediamtx.yml`, service `mediamtx` |
| TLS / hostname | droplet `/etc/caddy/Caddyfile`, service `caddy`; serves `cams.donwb.com` + `68-183-149-152.sslip.io` fallback |
| Camera roster | `cameras` table; `GET /api/v2/cameras` (public), admin endpoints under `/api/v2/admin/cameras` |

## Runbook

**A camera is black — where do I look?**
1. Is the relay serving it? `curl -sL https://cams.donwb.com/<id>/index.m3u8` —
   `#EXTM3U` means yes (problem is client-side); an error JSON means no publisher.
2. Is the Studio pushing? Check `~/Library/Logs/cam-restreamer/<id>.log` on the
   Studio. "This live stream recording is not available" = the cam is offline at
   YouTube or its video ID rotated (see below).
3. Is the relay itself up? `ssh root@68.183.149.152 systemctl status mediamtx caddy`
   and `journalctl -u mediamtx -n 50`.

**Restart everything on the Studio:**
`launchctl kickstart -k gui/$(id -u)/com.donwb.cam-restreamer`

**"Sign in to confirm you're not a bot" in a camera's log** (seen Aug 2026):
YouTube bot-checks anonymous yt-dlp resolves from the home IP — it's IP-level
(every player client is walled). Running pipelines keep working, but any camera
that drops can't re-resolve and stays down. Fix: run the bgutil PO-token
provider on the Studio — it mints BotGuard proof-of-origin tokens locally, no
Google account or cookies involved, and the yt-dlp plugin auto-detects it at
127.0.0.1:4416 (zero restreamer changes). Install steps are in the header of
`scripts/com.donwb.bgutil-pot.plist`. Verified 2026-08-14 from the home IP:
resolves that failed the bot-check anonymously succeed with the provider up.
Fallback if the provider path ever breaks: `YTDLP_COOKIES=/path/to/cookies.txt`
in `~/.cam-restreamer.env` (Netscape cookies.txt from a signed-in browser;
prefer a throwaway account — heavy automated use can flag it).

**A camera's YouTube video ID changed** (stream restarted under a new ID — this is
what "Ormond Beach offline" looks like): update the roster row's `youtube_url`
(`POST /api/v2/admin/cameras/<id>/stream` only sets hls_url; youtube_url is a DB
change), then kickstart the restreamer or wait for the 6h refresh.

**Add/remove a camera:** insert/delete the `cameras` row (id, name, location,
youtube_url, sort_order) and set `stream_url` to
`https://cams.donwb.com/<new-id>/index.m3u8`. The restreamer picks it up at the
next 6h refresh (or kickstart). No script edits, no relay config — MediaMTX
accepts any authenticated path.

**Rebuild the droplet from scratch:** create droplet → install caddy + ufw (apt)
and MediaMTX (GitHub release tarball → `/opt/mediamtx/`) → restore
`/opt/mediamtx/mediamtx.yml` (rtmp on, hls on 127.0.0.1:8888, variant mpegts,
publisher auth), systemd unit, `/etc/caddy/Caddyfile` → ufw allow 22/80/443/1935.
New publisher password goes in the Studio's `~/.cam-restreamer.env`.

## Caveats

- **The Studio is a single point of failure** for video (not for ramp/tide data).
  If it's off, streams stop; the relay and stable URLs stay up.
- **ToS**: this restreams YouTube-delivered content outside their player. It's the
  county's own public cameras at personal scale, but if the county or its camera
  vendor ever exposes a direct feed, point the restreamer at that instead.
- **yt-dlp bit-rots.** When YouTube changes things, `brew upgrade yt-dlp` on the
  Studio is the first fix to try; the second is testing other
  `player_client` values (see the sustain-test method in the git history of this
  file's original session: download with `-o -` to a file and confirm it grows
  past ~60s).
