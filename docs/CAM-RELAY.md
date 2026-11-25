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
  restarts the pipeline if ffmpeg's progress file goes stale or its frame count
  freezes (>45s), or if the relay stops serving it for three 15s probes, YouTube's
  ~6h URL expiry just triggers a restart (30s retry after any session that
  streamed), and the whole roster re-fetches + restarts every 6h (picks up
  roster changes). launchd restarts the supervisor itself if it dies. A camera
  that fails to *resolve* at all (offline broadcast, bot-checked) backs off
  exponentially, 2 min doubling to a 30 min cap — hammering YouTube's player
  API every 2 min from one IP is what drew the Aug 2026 bot-wall.
- **Quiet hours: no live video 11pm–6am local** (`QUIET_HOURS`, default `23-6`,
  empty = around the clock; set it in `~/.cam-restreamer.env`). At 23:00 the
  supervisor stops every pipeline (checked each minute) and sleeps until 06:00,
  then fetches the roster and starts fresh. Nothing touches YouTube overnight. The
  relay goes dark, the health poller marks each cam `online: false`, and clients
  show the cam's still (`still_url`, YouTube's live thumbnail) instead of video.
  Added 2026-11-23, after the 11/20 IP block: seven fewer hours of five
  round-the-clock pulls, and overnight video of a dark beach was never worth
  much. So **every cam reading offline between 11pm and 6am is expected**, not
  an outage.

## Components & where things live

| What | Where |
|------|-------|
| Restreamer script (source of truth) | `scripts/cam-restreamer.sh` in this repo |
| Installed copy on Mac Studio | `~/bin/cam-restreamer.sh` |
| launchd job | `~/Library/LaunchAgents/com.donwb.cam-restreamer.plist` (source: `scripts/com.donwb.cam-restreamer.plist`) |
| Studio config/secrets | `~/.cam-restreamer.env` (API_KEY, RELAY_HOST, RELAY_PUB_PASS, YTDLP_COOKIES) |
| Studio logs | `~/Library/Logs/cam-restreamer/<cam-id>.log` + `/tmp/cam-restreamer.launchd.log` — per-cam logs copy-truncate to `<cam-id>.log.1` past `LOG_MAX_MB` (64) |
| Relay droplet | `beach-cam-relay`, DO nyc3, 68.183.149.152 (ssh root@, ProMax key) |
| MediaMTX config (incl. publisher password) | droplet `/opt/mediamtx/mediamtx.yml`, service `mediamtx` |
| TLS / hostname | droplet `/etc/caddy/Caddyfile`, service `caddy`; serves `cams.donwb.com` + `68-183-149-152.sslip.io` fallback |
| ERDDAP wave proxy | same Caddyfile, `handle /erddap/*` → `coastwatch.pfeg.noaa.gov` (added 2026-08-18) — the beach API fetches NDBC buoy wave data through it because NOAA tarpits the app's DO egress IP; see `NDBC_ERDDAP_URL` in the main CLAUDE.md. Removing this route silently starves the wave-aware prediction model. |
| Camera roster | `cameras` table; `GET /api/v2/cameras` (public), admin endpoints under `/api/v2/admin/cameras` |
| Health hook script | droplet `/opt/mediamtx/health-hook.sh` (holds the `CAM_HOOK_KEY` value) |

## Health monitoring

Two reconciling sources feed `camera_health` / `camera_health_history` in the
API's Postgres (added 2026-08-16, after a day of silent flapping):

- **Hooks (instant):** MediaMTX `runOnReady`/`runOnNotReady` on the droplet run
  `/opt/mediamtx/health-hook.sh`, which POSTs `{id, online}` to
  `POST /api/v2/hooks/camera-health` with the `X-Hook-Key` header. The key is
  the `CAM_HOOK_KEY` env var on the API (placeholder in `.do/app.yaml`, real
  value set in the platform UI) and is baked into the droplet script — a
  deliberately scoped secret that can only report camera health. Non-roster
  paths (ad-hoc test publishes) are acknowledged and ignored.
- **Poller (reconcile):** the API probes each roster camera's `stream_url`
  every `CAM_HEALTH_INTERVAL` (60s) — with `hlsAlwaysRemux` the manifest is
  200 exactly when a publisher is connected — establishing state at boot and
  repairing anything a missed hook left stale. Works even with no hook key
  configured; hooks only tighten transition latency to ~instant.

Consumers: `GET /api/v2/cameras` now carries `online` + `status_changed_at`
per camera (omitted until first observation — strictly additive), and
`GET /api/v2/cameras/health` returns full current state plus recent flap
history (`?limit=N`). History rows are written only on actual flips, so the
history table doubles as an uptime/flap log for exactly the kind of "is the
restreamer flaky?" question that prompted all this.

## Runbook

**A camera is black — where do I look?**
1. Is the relay serving it? `curl -sL https://cams.donwb.com/<id>/index.m3u8` —
   `#EXTM3U` means yes (problem is client-side); an error JSON means no publisher.
2. Is the Studio pushing? Check `~/Library/Logs/cam-restreamer/<id>.log` on the
   Studio. "This live stream recording is not available" = the cam is offline at
   YouTube or its video ID rotated (see below).
3. Is the relay itself up? `ssh root@68.183.149.152 systemctl status mediamtx caddy`
   and `journalctl -u mediamtx -n 50`.

The iOS and tvOS players don't wait on any of this (2026-10-09): they read their own
picture every 2s (`CamPictureSampler`, BeachStatus) and after 10s of black change to
the next cam in roster order (`CamDarkWatch`). A black cam rarely recovers in place but
is usually fine a few minutes later. The watch skips cams the roster marks
`online: false` and cams already left black in the same sweep. When every cam is black
it stays put for 2 min before another sweep, and it does nothing after civil dusk,
because a dark beach at night is not a dead feed. Web doesn't do this yet.

**Restart everything on the Studio:**
`launchctl kickstart -k gui/$(id -u)/com.donwb.cam-restreamer`

**Cams flapping every few minutes, relay log full of `closed: … i/o timeout`**
(seen 2026-08-16): the home→droplet RTMP leg stalls for 10–30s at a time and
MediaMTX kills any publisher silent longer than `readTimeout`. Diagnosis that
pinned it: ffmpeg's FLV output hit "End of file" *right after* a healthy
progress line (the relay hung up on a stream that was still pumping), and a
synthetic 10-min publish from the same home IP ran clean the moment
`readTimeout` went from the 10s default to 30s while the YouTube download
leg tested clean throughout. If it recurs, look at upstream/uplink health
(the stalls are the disease; the timeout only decides whether they're fatal).

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

**`brew upgrade yt-dlp` silently uninstalls the PO-token plugin.** The plugin
lives in brew's yt-dlp virtualenv (`/opt/homebrew/opt/yt-dlp/libexec`), and an
upgrade rebuilds that venv from scratch — the server on :4416 keeps running, so
nothing looks wrong. Check with `yt-dlp -v --simulate <url> 2>&1 | grep "PO Token
Providers"`: `none` means the plugin is gone. After every yt-dlp upgrade,
reinstall it at the server's version (`curl -s http://127.0.0.1:4416/ping`
reports it):
`/opt/homebrew/opt/yt-dlp/libexec/bin/python -m pip install bgutil-ytdlp-pot-provider==<ver>`,
then kickstart the restreamer. (Hit 2026-11-20 and again 2026-11-25.)

**"No video formats found" on every cam, no 403s: yt-dlp is out of date, not
bot-walled** (2026-11-24 18:01 → 11-25 07:50). YouTube rotated its player JS
(`b485e332`) and yt-dlp 2026.10.26's n-challenge solver crashed on it — `yt-dlp -v`
shows `WARNING: [youtube] [jsc] Error solving n challenge … a.addOnDisposeCallback
is not a function` then `n challenge solving failed`, and without the solved
challenge no formats come back. A bot wall looks different: segment 403s or "Sign
in to confirm you're not a bot". Fix, in order:
1. `brew upgrade yt-dlp` (2026.11.23 fixed this one; `curl -s
   https://pypi.org/pypi/yt-dlp/json` shows the latest if brew lags).
2. Reinstall the PO-token plugin (the paragraph above — the upgrade removes it) and
   confirm `PO Token Providers: bgutil:http-…` plus `Retrieved a gvs PO Token` in `-v`.
3. `launchctl kickstart -k gui/$(id -u)/com.donwb.cam-restreamer` — otherwise the
   cams sit out the 30-min backoff — then `make restreamer-status` until 200s.

**Segments 403 on every client even with a PO token** (2026-11-20; resolved
2026-11-23 by a new home IP): yt-dlp resolves, the token is retrieved ("Retrieved a gvs PO
Token for mweb client" in `-v`), the manifest loads, and every media segment
returns 403 — all five cams, all player clients (mweb/android_vr 403;
web/web_safari/ios "No video formats found"; tv "page needs to be reloaded").
Upgrading yt-dlp (→ 2026.10.26) and bgutil (→ 2.0.2) did not fix it. Suspected
IP-level flagging after a night of retries; the restreamer's backoff caps at
30 min, so waiting is cheap. Next steps if it doesn't clear: the cookies
fallback above, then a yt-dlp nightly.
*Outcome:* it was the IP. A cellular hotspot pulled segments fine with the
same yt-dlp, and the block on 38.59.7.224 held all weekend at the 30-min backoff.
Wire3 (the home ISP, DHCP) rotated the address to 38.59.35.233 on 2026-11-23,
and four cams came straight back. Ormond-by-the-Sea kept 403ing on frozen
segment numbers, which means its broadcast is dead upstream, not blocked. If it
happens again: confirm with a one-cam pull from a different network, ask Wire3
for a new IPv4, and the stills fallback covers viewers meanwhile. The quiet hours
above came out of this.

**Some cams 403 on segments while others stream, from the same IP** (2026-11-23):
check for **IPv6**. yt-dlp resolves over IPv4 (`-4`, because YouTube bot-walls
IPv6 resolves), and the googlevideo URLs are locked to that IPv4 address
(`/ip/<v4>/` in the URL). But yt-dlp's internal downloader ffmpeg has no
IPv4-only option and connects over IPv6 whenever the edge host has an AAAA
record and the Studio has a global v6 address. The segment then arrives from
the wrong address and gets a 302/403. Whether a given cam works depends on
which edge it lands on, so it looks random. Diagnose with
`ffmpeg -loglevel verbose -i "$(yt-dlp -4 --extractor-args youtube:player_client=mweb -f 'best[protocol^=m3u8]' -g <url>)"`:
the `Starting connection attempt to 2607:…` lines give it away. A
`curl -4` fetch of the same segment returns 200, so plain-curl tests
mislead. **Fix: IPv6 off on the Studio's active interface** (Wi-Fi, en1):
`sudo networksetup -setv6off Wi-Fi` (undo: `-setv6automatic`). Done
2026-11-23; all five cams streamed within two minutes. If IPv6 comes back
(macOS update, interface change, new network service), this comes back.

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
`hlsAlwaysRemux: yes` — without it the first viewer after an idle spell waits
5–9s for the muxer to spin up, which reads as "offline" to impatient players —
`readTimeout`/`writeTimeout: 30s` so publishers ride out brief network stalls
instead of dying at the 10s default,
publisher auth), systemd unit, `/etc/caddy/Caddyfile` → ufw allow 22/80/443/1935.
New publisher password goes in the Studio's `~/.cam-restreamer.env`.
**The Caddyfile must keep the `/erddap/*` proxy route** — the beach API's wave
data rides through it (see `docs/WAVE-DATA.md`); a rebuilt droplet without it
silently starves the prediction model.

## Caveats

- **The Studio is a single point of failure** for video (not for ramp/tide data).
  If it's off, streams stop; the relay and stable URLs stay up.
- **ToS**: this restreams YouTube-delivered content outside their player. It's the
  county's own public cameras at personal scale, but if the county or its camera
  vendor ever exposes a direct feed, point the restreamer at that instead.
- **yt-dlp bit-rots.** When YouTube changes things, `brew upgrade yt-dlp` on the
  Studio is the first fix to try (then reinstall the PO-token plugin — see "No
  video formats found" above); the second is testing other
  `player_client` values (see the sustain-test method in the git history of this
  file's original session: download with `-o -` to a file and confirm it grows
  past ~60s).
