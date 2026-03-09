# Beach Ramp Status — Project Conventions

## What This Project Is

A multi-platform application showing real-time beach access ramp status, tide data, and water temperature for Volusia County, Florida. See `REQUIREMENTS.md` for the full specification.

## Repository Structure

```
api/          → Go API service + data ingester (the backend)
web/          → Vanilla HTML/JS + Tailwind website (served by the API)
apple/        → Xcode workspace: iOS, watchOS, tvOS targets + shared Swift package
trmnl/        → TRMNL e-ink display Liquid template
tidbyt/       → FROZEN — legacy Tidbyt Pixlet script, do not modify
```

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
- API versioning: v1 endpoints (`/rampstatus`, `/tides`, `/ramps`) must maintain exact backward compatibility for Tidbyt. New work goes on `/api/v2/*` endpoints.

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
- Use `TIMESTAMPTZ` for all timestamps
- Connection via `DATABASE_URL` environment variable

## TRMNL (E-Ink Display)

- Template is a Liquid/HTML file at `trmnl/template.html`
- Monochrome only — design for e-ink (no color, high contrast, no gradients)
- Data comes from `/api/v2/trmnl` endpoint shaped for TRMNL plugin webhook
- Status strings > 12 chars must use abbreviated form (`access_status_short`)
- This is an active platform — expect frequent iteration

## Tidbyt (Legacy)

- **DO NOT MODIFY** any files in `tidbyt/`
- The Pixlet script depends on the v1 API response shape
- If you change v1 endpoints, verify the response JSON is identical

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
| `NOAA_TIDE_STATION` | API | NOAA tide station ID (default: 8721164) |
| `NOAA_TEMP_STATIONS` | API | Comma-separated NOAA temp station IDs |
| `WEB_DIR` | API | Path to web static files (auto-detected in dev, `/web` in Docker) |

## Agent Team Notes

When working as part of an agent team on this project:

- **Always read `REQUIREMENTS.md` first** — it's the single source of truth for what to build
- **v1 API compatibility is sacred** — the Tidbyt device cannot be updated, so `/rampstatus` and `/tides` must return the exact same JSON shape as today
- **Coordinate on shared types** — if you're defining Go structs or Swift models that others will use, message the team before finalizing the shape
- **Don't touch `tidbyt/`** — it's frozen
- **Test your work** — write tests as you go, don't leave them for later
