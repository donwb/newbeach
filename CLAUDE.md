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

The site is served at `https://beach.donwb.com` (custom domain declared in `.do/app.yaml`); the DigitalOcean default hostname `beach-ramp-status-kff7g.ondigitalocean.app` also works and is what the Apple apps, TRMNL plugins, CI, and the camera-refresh cron are pinned to.

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
- Minimum targets: iOS 17, watchOS 10, tvOS 17
- Swift 5.9+
- Shared Swift package `BeachStatus/` contains: Models, Networking, Utilities
- All three app targets depend on the shared package — no duplicated model or networking code
- MVVM architecture
- Networking: async/await with URLSession, no third-party HTTP libraries
- Local caching: SwiftData
- Use SF Symbols for icons
- Previews: every view should have a working Xcode preview with mock data

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

- **Why it exists:** In August 2026 YouTube's googlevideo HLS URLs became IP-locked and client-checked — manifests still load from any IP, but media segment fetches 403 for everyone except the resolving host, so the old model (home cron resolves URLs via yt-dlp, viewers play them directly) shows a black player on every platform.
- **Architecture:** the home Mac runs `scripts/cam-restreamer.sh` (launchd job `scripts/com.donwb.cam-restreamer.plist`): per roster camera, yt-dlp (mweb player client — its URLs sustain; the default web client's cut off after the ~40s DVR window) downloads the live stream and pipes to ffmpeg, which remuxes (`-c copy`, no transcode) and publishes over authenticated RTMP to the relay droplet.
- **Relay:** DigitalOcean droplet `beach-cam-relay` (68.183.149.152, nyc3, $6/mo) running MediaMTX — RTMP ingest on :1935 (publisher password), HLS out through Caddy auto-TLS at `https://cams.donwb.com` (sslip.io fallback hostname also configured). Config at `/opt/mediamtx/mediamtx.yml`; systemd services `mediamtx` and `caddy`; HLS variant is classic mpegts for maximum hls.js/AVPlayer compatibility.
- **Stable URLs:** each camera serves at `https://cams.donwb.com/<camera-id>/index.m3u8` — stream URLs no longer rotate, so the roster's `stream_url` values are effectively permanent.
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
