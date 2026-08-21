# Beach Ramp Status — Project Conventions

## What This Project Is

A multi-platform application showing real-time beach access ramp status, tide data, and water temperature for Volusia County, Florida. See `REQUIREMENTS.md` for the full specification.

## Repository Structure

```
api/          → Go API service + data ingester (the backend)
web/          → Vanilla HTML/JS + Tailwind website (served by the API)
apple/        → Xcode workspace: iOS, watchOS, tvOS targets + shared Swift package
trmnl/        → TRMNL e-ink display Liquid template
```

The site is served at `https://beach.donwb.com` (custom domain declared in `.do/app.yaml`), and everything in this repo points there as of 2026-08-15 — Apple apps, TRMNL templates, CI, and the cam restreamer. The DigitalOcean default hostname `beach-ramp-status-kff7g.ondigitalocean.app` still resolves, but nothing should depend on it. **The TRMNL polling URLs live in the TRMNL plugin settings, not in `trmnl/*.html`** — the URLs in those templates are comments, so changing them here does not change what the devices fetch.

## Go (API + Ingester)

- Go 1.22+
- Use `internal/` for all non-exported packages
- Entry point: `api/cmd/server/main.go`
- HTTP framework: Echo v4
- Use structured logging (slog or zerolog), never fmt.Println in production code
- All configuration via environment variables — never hardcode URLs, credentials, or station IDs
- Error handling: always wrap errors with context (`fmt.Errorf("fetching ramps: %w", err)`)
- Tests: table-driven tests, use `testify` for assertions
- Naming: use standard Go conventions (camelCase unexported, PascalCase exported)
- Database queries: use `pgx` directly or `sqlc` for type-safe queries — no heavy ORMs
- Run `go vet` and `staticcheck` before committing
- API versioning: v1 endpoints (`/rampstatus`, `/tides`, `/ramps`) are legacy (the Tidbyt that required them is retired) — keep them stable unless there's a reason not to. New work goes on `/api/v2/*` endpoints.

## Website (Vanilla + Tailwind)

- No frameworks — plain HTML, CSS, JavaScript
- Tailwind CSS via CDN or built stylesheet
- Single `index.html` served by the Go API at `/`
- JavaScript in `app.js` — vanilla ES modules, no build step required
- Mobile-first responsive design
- Support dark mode via `prefers-color-scheme` + manual toggle
- All API calls go to relative paths (`/api/v2/ramps`, not absolute URLs)

## Swift (iOS / watchOS / tvOS)

- SwiftUI only — no UIKit
- Minimum targets: iOS 18, watchOS 11, tvOS 18 (per-target deployment settings in the Xcode project; `BeachStatus/Package.swift` declares the same floors)
- Swift 5.9+
- Shared Swift package `BeachStatus/` contains: Models, Networking, Utilities
- All three app targets depend on the shared package — no duplicated model or networking code
- MVVM architecture
- Networking: async/await with URLSession, no third-party HTTP libraries
- Local caching: SwiftData
- Use SF Symbols for icons
- Previews: every view should have a working Xcode preview with mock data

## Apple Releases

- **`make flight`** — bumps the build number, archives iOS + tvOS Release, and uploads
  both to TestFlight. `make flight-ios` / `make flight-tv` for one platform;
  `make flight-check` archives without uploading. Implementation:
  `apple/scripts/flight.sh` (ported from the bkmks project's equivalent).
- **Flighting is deliberately outside the commit/push/test loop** — it is bandwidth-heavy
  and account-bound. **Don runs this**; agents must not flight as part of finishing work.
- **`apple/BeachRamp/Config/Version.xcconfig` is the single source of truth** for
  `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, the display name, and the
  export-compliance key. It is the project-level base configuration, so every target
  inherits it. **Never re-declare those settings on an individual target** — a per-target
  value silently wins and the build bump becomes a no-op for that target.
- **One App Store Connect record, one bundle ID.** The iOS and tvOS app targets both build
  as `com.donwb.BeachRampTV`; that shared identifier is what lets a single ASC record carry
  both platforms. The watch app is `com.donwb.BeachRampTV.watchkitapp`. The "TV" in the
  identifier is historical and deliberate: the surviving ASC record ("Beach Ramp Status",
  Apple ID 6761724123) had already taken a build, which permanently freezes its bundle ID,
  so the project moved to the record rather than gambling the reserved app name on a
  delete-and-recreate. Bundle IDs are never user-visible; the apps display as "Beach Ramps".
- **watchOS is out of scope for 1.0** — the target still exists and builds, but the
  "Embed Watch Content" phase was removed from the iOS app so it does not ride into the
  archive. Re-adding that phase is how it ships later.
- **Shared schemes are committed** at `BeachRamp.xcodeproj/xcshareddata/xcschemes/`.
  Without them `xcodebuild -scheme` is not reproducible across machines.
- **Auth: flight uses Xcode's signed-in Apple ID session, and it expires.** The export
  step re-signs with cloud-managed distribution signing, which only the Apple ID session
  can do — an App Store Connect API key fails here with "Cloud signing permission error /
  No signing certificate iOS Distribution found." Symptoms of a stale session are
  misleading ("Failed to Use Accounts", keychain "missing Xcode-Username"), and **Xcode's
  Accounts pane lies** — it shows signed-in while dead. Fix: remove the Apple ID with the
  − button and re-add with password/2FA, **at the Mac, not over a remote session**.
  Recovery is cheap — the archive survives, so rerun `apple/scripts/flight.sh --no-bump --yes`.
- **Hostname tripwire**: flight refuses (with a confirm) if `APIClient.swift` still points
  at the `ondigitalocean.app` hostname instead of `beach.donwb.com`.

## Database

- PostgreSQL 16+ (raised from 15 on 2026-08-18: the page_views exclude_ip filter
  uses `pg_input_is_valid`, which is 16+. Dev docker runs 16, prod RDS runs 17.)
- Migrations in `api/migrations/` as numbered SQL files (e.g., `001_create_ramp_status.up.sql`)
- Always provide both up and down migrations
- Primary table: `ramp_status` — upsert on `access_id`
- History table: `ramp_status_history` — append-only log of status changes
- Settings table: `settings` — key-value store for runtime config (e.g., `video_stream_url`)
- Use `TIMESTAMPTZ` for all timestamps
- Connection via `DATABASE_URL` environment variable

## Prediction ("Outlook")

- `api/internal/predict` learns per-ramp tide-closure behavior from `ramp_status_history`
  joined to NOAA high-tide peaks: a nightly trainer (03:30 ET, plus boot when stale)
  persists per-ramp threshold/lead/lag/close-rate to the `prediction_params` settings key
  (inspect: `GET /api/v2/admin/prediction/params`).
  `GET /api/v2/admin/prediction/scorecard?date=YYYY-MM-DD` (default yesterday ET) grades a
  past day: each daytime peak replayed through the risk rules vs. actual closures —
  outcomes hit/covered/miss/false_alarm/hedged/quiet, plus window-hit accuracy. Caveat:
  it grades with current params, which already include the graded day's history. `GET /api/v2/outlook` (bulk, 10-min
  TTL cache) and `/api/v2/ramps/:id/outlook` serve risk + **server-built casual copy** —
  clients must render the strings verbatim, never compute their own predictions. Copy
  rules: approximate clock times only — rounded to the half hour and hedged with
  "around"/"by"/"~" ("possible around 1:30pm"), never minute-precise promises; a tide
  closure is always **"possible"** — never "likely" or "will", the county's call is
  genuinely theirs; **every string names the reason** (tide / end of day / overnight) so a
  reader is never told "closure possible" with no cause. The `short` field is the compact
  board-card hint.
- **The voice layer (`predict/voice.go`, 2026-08-21) rotates only the quiet lines** — the
  surf read and an all-open city verdict — through small pools of local-lingo phrases
  (the Inlet, the break, the lineup, groms, Beachway, NSB's sharks). The pick is seeded by
  ET date + daypart (morning <11 / midday <16 / evening), so every device shows the same
  phrase and it changes at most three times a day — never between 10-min refreshes (the
  tvOS verdict bar flashes on headline change, and that flash must mean news). Closure
  copy never rotates. `TestVoicePoolsFitTheirSlots` pins length budgets (surf ≤52 chars
  with "overhead" filled in, verdict ≤28) — add phrases freely, keep them inside.
- **This line always looks forward** — it predicts the next thing that will happen and is
  never a place to report what already did (the since line does that). Every hour of the
  clock has an answer: overnight and pre-open → "opens around 8am"; tide risk live → the
  tide copy; otherwise → the day's close.
- **`risk` grades the tide, conditioned by the sea state — nothing else.**
  `none`/`possible`/`likely` are read that way by `backtest_test.go` and the scorecard,
  so no other feature may borrow them.
  `closed_now` (shut right now — tide or overnight, carries a reopen label) and
  `scheduled` (the only closure coming is the day ending) are factual states, not
  gambles. `reason` says which: `high_tide`, `end_of_day`, `overnight`.
- **The wave model (2026-08-18) shifts thresholds, asymmetrically.** The same tide peak
  closes ramps under a wind swell and passes quietly over a flat ocean, so training
  learns a county-wide calm/rough regime split from NDBC buoy WVHT (`trainWaveParams`:
  boundary + threshold shift per side, chosen jointly by a closed-form scan that weights
  a missed closure double a false alarm, mirroring the outcome taxonomy). Serving reads
  the latest `wave_observations` row (ignored past 6h — buoy adrift = tide-only) and
  applies one county-wide shift in `riskForPeak`. Three deliberate asymmetries: the hard
  cutoffs never move (extreme tides close ramps whatever the surf); a swell widens the
  `possible` band downward but **never promotes to `likely`** (only tide evidence
  promises); nil anywhere — no data, unlearned params, kill switch — reproduces the
  tide-only engine exactly. `PREDICT_WAVES_ENABLED=false` is the serve-side kill switch.
  The outlook echoes what it saw in a `surf` block (height, period, regime); the
  scorecard annotates every graded peak with the nearest observation.
- **`wave_observations` is the canonical wave series** (buoy-timestamped, unique per
  station+time, all writers idempotent): the conditions logger dual-writes each 30-min
  observation, and the nightly trainer self-heals from NDBC — the realtime2 window
  (45 days) plus monthly/yearly stdmet archives back to the start of ramp history
  (`conditions.BackfillWaves`, a no-op once populated). Backtest fixture:
  `testdata/waves.json`, regenerated by `cmd/gen-waves-fixture`.
- **www.ndbc.noaa.gov hard-blocks datacenter IPs** — 403 for every user agent from
  DigitalOcean egress (verified 2026-08-18 from the cam-relay droplet; residential IPs
  are fine, which is why local dev never sees it). Every NDBC fetch path therefore
  falls back to NOAA CoastWatch's ERDDAP mirror (`cwwcNDBCMet`, `conditions/erddap.go`)
  — same buoy data, ~30-min lag, full history. CoastWatch in turn tarpits the app's
  own egress IP, so **prod's wave data routes through the cam-relay droplet's Caddy**
  (`NDBC_ERDDAP_URL` → `cams.donwb.com/erddap/*`) — the prediction model depends on
  camera infrastructure. Full pipeline, evidence, and runbook: `docs/WAVE-DATA.md`.
  Don't "simplify" the fallback away, and don't debug missing prod wave data by
  fetching NDBC from a home machine — it will work there and prove nothing.
- **The end-of-day close is learned, not posted.** The county clears the beach before the
  posted time — turtle-season 7pm has been running ~6:30 — so the trainer learns the
  median offset from history into `day_close_offset_min` and `buildSchedule` applies it
  (clamped to ±90 min). Never hard-code a close time; the posted hours live in
  `postedHours` and the offset corrects them.
- **The copy is time-aware.** Peaks stay in play until their learned lag expires, and a
  predicted close time the clock has passed is never quoted back at a ramp that is still
  open ("possible around 11am" at noon): it becomes "any time now", then softens past the
  peak, then hands off to the day's close. `decayRisk` + the phases in `tideText`.
- **A non-NULL `ramp_metadata.closure_height_ft` overrides the learned threshold** — only
  curate it deliberately.
- `api/internal/predict/backtest_test.go` replays five months of checked-in real history
  and pins recall/calibration floors — engine changes that degrade real-world behavior
  fail tests. Refresh fixtures from `/api/v2/ramps/:id/history` + NOAA hilo when needed.
- **Weekend outlook (`GET /api/v2/outlook/weekend`, 2026-08-18)** answers "when
  should I go this weekend": the next 6 days, each graded `verdict:
  great|good|mixed|tough|no_call` + `closure_pressure: none|some|high` — a
  **separate vocabulary from `risk` on purpose**; the weekend feature must never
  borrow the fenced risk enum. Inputs: the existing per-ramp tide engine run
  over future peaks, plus NWS gridpoint forecasts (`api/internal/nwsfc`: land
  hourly + marine waves, TTL-cached, serve-stale, retry). Verdict thresholds are
  **experiential and live-tunable**: `weekend_verdict_params` settings key
  (defaults in `DefaultVerdictParams`, from Don's 2026-08-18 calibration —
  storms block hours not days, wind ≥15 sustained degrades / ≥25 gusts caps at
  tough, heat advisory or index ≥105 downgrades + biases windows to morning,
  day high <65°F downgrades). Edit via `/api/v2/admin/settings`, no redeploy.
  Degradation: no NWS coverage → honest tide-only verdicts with `basis` saying
  so; `WEEKEND_OUTLOOK_ENABLED=false` unregisters the route. All copy in
  `weekendtext.go` follows the text.go voice rules.
- **Surf report (2026-08-19): the surf info is an adjective, not a feature.** One
  casual line (`surf_report` block on both outlook endpoints, `predict/surfreport.go`):
  a deterministic classifier over buoy height/period + NWS wind direction
  (flat/blown/choppy/clean_small/good/firing, surfer-terms heights), with the
  ramp-access clause appended only when the surf is worth driving to — reusing
  the already-built ramp outlooks, never recomputing tide risk. **Rip current
  risk is relayed verbatim from the KMLB Surf Zone Forecast (`weather/srf.go`),
  never computed here**; elevated rip enters the prose, Low stays in the field.
  No dedicated surf page anywhere — surfers have Surfline; the unique angle is
  surf × ramp access. `surf_report` never touches `risk` or `SurfContext`
  (the model echo), and `SURF_REPORT_ENABLED=false` removes the block while
  leaving wave-conditioned predictions alone.
- `api/internal/conditions` snapshots tide/wind/NDBC-buoy waves + ramp counts to
  `beach_conditions` every 30 min. Originally the seed data for the wave-aware model
  (now shipped, fed by `wave_observations`); still valuable as the joint
  tide/wind/wave/closure record for future refinements (e.g. period-aware runup — an
  11s groundswell carries more energy than its height suggests) — don't turn it off
  casually.
- `api/internal/solar` is the Go port of `web/js/solar.js` (itself ported from
  SolarCalculator.swift) — three ports exist; keep reference values in their tests aligned.

## TRMNL (E-Ink Display)

- Two devices, two templates:
  - `trmnl/template.html` — TRMNL OG (800×480, 1-bit). Polls `/api/v2/ramps` + `/api/v2/tides`. Status strings > 12 chars use abbreviated form (`access_status_short`).
  - `trmnl/template-x.html` — TRMNL X (1872×1404 panel, 16-level grayscale). **Templates render on a 1040×780 CSS pixel canvas** (the `screen--v2` size) and the firmware upscales 1.8× — size all CSS for 1040×780, not the panel resolution. Polls the `/api/v2/trmnl` aggregate endpoint, which pre-formats everything (display names, since-times, SVG tide curve paths) so the Liquid stays near logic-free. Full status strings fit — no abbreviations.
- `trmnl/preview-x.html` — local dev harness: renders the X template with sample data via liquidjs (serve the `trmnl/` dir with any static server)
- No color — design for e-ink (high contrast; grays are fine on the X for secondary text and fills, never for small thin type)
- This is an active platform — expect frequent iteration

## Beach Cam Relay

Full architecture + runbook: `docs/CAM-RELAY.md`. Summary:

- **Why it exists:** In August 2026 YouTube's googlevideo HLS URLs became IP-locked and client-checked — manifests still load from any IP, but media segment fetches 403 for everyone except the resolving host, so the old model (home cron resolves URLs via yt-dlp, viewers play them directly) shows a black player on every platform.
- **Architecture:** the home Mac runs `scripts/cam-restreamer.sh` (launchd job `scripts/com.donwb.cam-restreamer.plist`): per roster camera, yt-dlp (mweb player client — its URLs sustain; the default web client's cut off after the ~40s DVR window) downloads the live stream and pipes to ffmpeg, which remuxes (`-c copy`, no transcode) and publishes over authenticated RTMP to the relay droplet.
- **Relay:** DigitalOcean droplet `beach-cam-relay` (68.183.149.152, nyc3, $6/mo) running MediaMTX — RTMP ingest on :1935 (publisher password), HLS out through Caddy auto-TLS at `https://cams.donwb.com` (sslip.io fallback hostname also configured). Config at `/opt/mediamtx/mediamtx.yml`; systemd services `mediamtx` and `caddy`; HLS variant is classic mpegts for maximum hls.js/AVPlayer compatibility.
- **Stable URLs:** each camera serves at `https://cams.donwb.com/<camera-id>/index.m3u8` — stream URLs no longer rotate, so the roster's `stream_url` values are effectively permanent.
- **Deploying restreamer changes: `make deploy-restreamer` (on the Studio).** launchd runs a
  *copy* at `~/bin/cam-restreamer.sh`, not the repo file — editing `scripts/cam-restreamer.sh`
  alone changes nothing on the running system. The target copies, warns if
  `~/.cam-restreamer.env` sets `API_BASE` (an env value silently overrides the script's
  default), kickstarts the job, and tails the log. `make restreamer-status` shows launchd
  state plus cam endpoint health; `make restreamer-diff` shows whether the deployed copy has
  drifted. The targets refuse to run on any machine where the launchd job isn't loaded.
- **Retired:** `scripts/update-stream-url.sh` (the URL-push cron). Remove its crontab entry wherever the restreamer gets installed.

## Tidbyt (Retired)

- The Tidbyt device was powered off in August 2026 and its Pixlet script was never checked into this repo
- The v1 endpoints (`/rampstatus`, `/tides`, `/ramps`) remain live but no longer have a hard compatibility constraint — prefer not to change their shape without checking for remaining consumers

## Local Development Credentials

- **Never commit credentials** — all sensitive config lives in `api/.env` (git-ignored)
- Copy `api/.env.example` to `api/.env` and fill in real values
- The Makefile auto-loads `.env` via `include .env` + `export`
- `.env.example` is committed with placeholder values so devs know what to set
- For production (DigitalOcean App Platform), env vars are set in the app spec or platform UI

## Git & CI

- Branch naming: `feature/description`, `fix/description`
- Commit messages: imperative mood, concise (e.g., "Add tide percentage to v2 response")
- PR-based workflow — no direct pushes to main
- GitHub Actions for CI: lint, test, build on every PR
- Docker build on merge to main

## Deployment

- Hosted on DigitalOcean App Platform — app spec lives at `.do/app.yaml`
- Database migrations run automatically at startup (not in CI)
- Website files served from filesystem via `WEB_DIR` env var (set to `/web` in Docker)
- Migration SQL files are embedded into the Go binary via `go:embed`
- Pushing to `main` triggers auto-deploy — never push broken code to main
- If you change environment variables, update both `.do/app.yaml` and this doc

## Environment Variables

| Variable | Used By | Purpose |
|----------|---------|---------|
| `DATABASE_URL` | API, Ingester | PostgreSQL connection string |
| `GIS_HOST` | Ingester | Volusia County GIS server (default: maps5.vcgov.org) |
| `POLL_INTERVAL` | Ingester | Seconds between GIS polls (default: 60) |
| `LOG_LEVEL` | API, Ingester | Logging verbosity (default: info) |
| `PORT` | API | HTTP listen port (default: 8080) |
| `WEBCAM_URL` | API | Configurable webcam image URL |
| `NOAA_TIDE_STATION` | API | NOAA tide station ID (code default: 8721147; **prod runs 8721164** per `.do/app.yaml` — a different height scale, which is why prediction cutoffs are learned, not hard-coded) |
| `NOAA_TEMP_STATIONS` | API | Comma-separated NOAA temp station IDs |
| `NDBC_STATION` | Conditions logger, prediction | NDBC wave buoy ID (default: 41113, Ponce Inlet) |
| `PREDICT_WAVES_ENABLED` | API | Set `false` to serve tide-only outlooks (wave series keeps accumulating) |
| `WEEKEND_OUTLOOK_ENABLED` | API | Set `false` to remove `/api/v2/outlook/weekend` entirely (clients hide the section) |
| `NWS_BASE_URL` | Weekend outlook | NWS API base override; unset = api.weather.gov. If the app egress ever gets blocked, point at a cams.donwb.com Caddy proxy route (`NDBC_ERDDAP_URL` precedent) |
| `NWS_LAND_GRIDPOINT` | Weekend outlook | NWS land gridpoint `OFFICE/x,y` (default `MLB/42,92`, New Smyrna) |
| `NWS_MARINE_GRIDPOINT` | Weekend outlook | NWS marine gridpoint (default `MLB/46,93`, zone AMZ550) |
| `SURF_REPORT_ENABLED` | API | Set `false` to drop the `surf_report` block from outlook payloads (independent of `PREDICT_WAVES_ENABLED`) |
| `NWS_SRF_OFFICE` | Surf report | Surf Zone Forecast issuing office (default `KMLB`) |
| `NWS_SRF_ZONE` | Surf report | SRF zone section to parse (default `FLZ141`, Coastal Volusia) |
| `NDBC_ERDDAP_URL` | Conditions logger, prediction | ERDDAP mirror base URL; **prod points at the cam-relay droplet's `/erddap/*` Caddy proxy** because NOAA tarpits the app's egress IP |
| `CONDITIONS_INTERVAL` | Conditions logger | Minutes between beach_conditions snapshots (default: 30) |
| `CONDITIONS_ENABLED` | Conditions logger | Set `false` to disable snapshotting |
| `CAM_HEALTH_INTERVAL` | Cam health poller | Seconds between relay stream probes (default: 60) |
| `CAM_HEALTH_ENABLED` | Cam health poller | Set `false` to disable the reconcile poller |
| `CAM_HOOK_KEY` | API | Shared secret for relay hooks (`/api/v2/hooks/*`); matches the key in the droplet's `/opt/mediamtx/health-hook.sh` |
| `WEB_DIR` | API | Path to web static files (auto-detected in dev, `/web` in Docker) |
| `ADMIN_API_KEY` | API | Secret key for admin endpoints (`/api/v2/admin/*`) |

## Agent Team Notes

When working as part of an agent team on this project:

- **Always read `REQUIREMENTS.md` first** — it's the single source of truth for what to build
- **v1 endpoints are legacy** — the Tidbyt device that required exact JSON compatibility was retired in August 2026; keep v1 stable by default but it is no longer frozen
- **Coordinate on shared types** — if you're defining Go structs or Swift models that others will use, message the team before finalizing the shape
- **Test your work** — write tests as you go, don't leave them for later

## Portfolio Status

**Portfolio status:** At the end of any session that changes status-relevant facts —
version/build, App Review state, punch-list items, target dates, blockers — update
`PORTFOLIO-STATUS.md` to match and bump its `last_verified` date. The portfolio control
tower in `~/atc` reads this file; a stale one is worse than none.
