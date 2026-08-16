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

- PostgreSQL 15+
- Migrations in `api/migrations/` as numbered SQL files (e.g., `001_create_ramp_status.up.sql`)
- Always provide both up and down migrations
- Primary table: `ramp_status` — upsert on `access_id`
- History table: `ramp_status_history` — append-only log of status changes
- Settings table: `settings` — key-value store for runtime config (e.g., `video_stream_url`)
- Use `TIMESTAMPTZ` for all timestamps
- Connection via `DATABASE_URL` environment variable

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
| `NOAA_TIDE_STATION` | API | NOAA tide station ID (default: 8721147) |
| `NOAA_TEMP_STATIONS` | API | Comma-separated NOAA temp station IDs |
| `NDBC_STATION` | Conditions logger | NDBC wave buoy ID (default: 41113, Ponce Inlet) |
| `CONDITIONS_INTERVAL` | Conditions logger | Minutes between beach_conditions snapshots (default: 30) |
| `CONDITIONS_ENABLED` | Conditions logger | Set `false` to disable snapshotting |
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
