# Beach Ramp Status — Rebuild Requirements

**Version:** 1.0 (Draft)
**Date:** March 9, 2026
**Author:** Don Browning + Claude

---

## 1. Project Overview

Beach Ramp Status is an application that provides real-time beach access ramp status, tidal information, and water temperature data for Volusia County, Florida — with a primary focus on New Smyrna Beach. The system collects data from Volusia County GIS and NOAA, stores it in a database, and serves it across multiple platforms: a website, iOS app, Apple Watch, Apple TV, and legacy IoT devices.

This document defines the requirements for a complete ground-up rebuild of the application using modern tooling while maintaining backward compatibility for legacy devices.

---

## 2. Current System Summary

The existing system is a monorepo (`donwb/beach`) containing:

- **Python data ingester** (`ramps/`) — cron job polling Volusia County GIS every minute, upserting ramp status into PostgreSQL
- **Go API service** (`svc/`) — Echo framework REST API serving ramp status, tide predictions, and water temperature; also serves the website as server-rendered HTML
- **iOS app (UIKit)** (`BeachInfo/`) — mature app showing 5 NSB ramps, tide table, water temp, and webcam
- **iOS app (SwiftUI)** (`BeachLife/`) — newer prototype, simpler feature set
- **Tidbyt display** (`tidbyt/`) — Pixlet script for Tidbyt IoT display (discontinued hardware)
- **Website** (`svc/view/`) — vanilla HTML/JS/CSS dashboard at donwb.com
- **TRML device** — separate codebase (not in repo), to be provided and rewritten

### What works well and should be preserved

- The data pipeline concept: GIS polling → database → API → clients
- NOAA integration for tides and water temperature
- The color-coded status system (green/yellow/red)
- City and status filtering on the website
- Backward compatibility with the Tidbyt device API

### What should be improved

- Two separate iOS apps should be unified into one SwiftUI app
- The website is functional but dated — needs a modern responsive redesign
- Hardcoded NOAA station IDs and API URLs should be configurable
- No Apple Watch or Apple TV support exists
- No push notifications for ramp status changes
- No historical data or trends
- Error handling is minimal in the Python ingester
- No automated tests
- No CI/CD pipeline

---

## 3. System Architecture (Rebuild)

### 3.1 High-Level Architecture

```
┌─────────────────────┐
│  Volusia County GIS  │
│  (ArcGIS MapServer)  │
└──────────┬──────────┘
           │ poll every 60s
           ▼
┌──────────────────────────────────────┐
│  Go Service (single binary)         │
│  ┌──────────────┐ ┌───────────────┐ │    ┌──────────────┐
│  │ API Server   │ │ Data Ingester │ │───▶│  PostgreSQL   │
│  │ (HTTP)       │ │ (goroutine)   │ │    │  (DO Managed) │
│  └──────────────┘ └───────────────┘ │    └──────┬───────┘
│         ▲                           │           │
│         │    ┌──────────────────┐   │           │
│         └────│  NOAA Tides &    │   │           │
│              │  Currents API    │   │           │
│              └──────────────────┘   │           │
└──────────────────┬──────────────────┘           │
                   │         ┌────────────────────┘
     ┌─────┬──────┬┘────┬────┘
           │
     ┌─────┼─────┬──────────┬──────────┐
     │     │     │          │          │
     ▼     ▼     ▼          ▼          ▼
   Web   iOS   Watch       TV       Legacy
   App   App   App         App      (Tidbyt/
                                    TRMNL)
```

### 3.2 Technology Decisions

| Component | Current | Rebuild |
|-----------|---------|---------|
| API | Go (Echo) | Go (Echo v4) |
| Data ingester | Python | Go (consolidate into one language) |
| Database | PostgreSQL | PostgreSQL (schema improvements) |
| Website | Vanilla HTML/JS/CSS | Vanilla HTML/JS + Tailwind CSS |
| iOS app | UIKit + SwiftUI (two apps) | SwiftUI only (single unified app) |
| Apple Watch | N/A | SwiftUI (new) |
| Apple TV | N/A | SwiftUI (new) |
| Tidbyt | Pixlet/Starlark | Frozen — no changes |
| TRMNL display | Liquid template + plugin webhook | Rewrite template + add `/api/v2/trmnl` endpoint |

---

## 4. Data Sources

### 4.1 Volusia County GIS (Ramp Status)

**Source:** Volusia County ArcGIS MapServer endpoint
**Host:** `maps5.vcgov.org` (configured via `GIS_HOST` environment variable)
**Endpoint:** `https://{GIS_HOST}/arcgis/rest/services/Beaches/MapServer/7/query`
**Polling frequency:** Every 60 seconds
**Data returned per ramp:** AccessName, AccessStatus, OBJECTID, City, AccessID, GeneralLoc

**Status values:**

| Status | Category | Color |
|--------|----------|-------|
| OPEN | Open | Green |
| 4X4 ONLY | Limited | Yellow |
| CLOSING IN PROGRESS | Limited | Yellow |
| OPEN - ENTRANCE ONLY | Limited | Yellow |
| CLOSED | Closed | Red |
| CLOSED FOR HIGH TIDE | Closed | Red |
| CLOSED - AT CAPACITY | Closed | Red |
| CLOSED - CLEARED FOR TURTLES | Closed | Red |

**Cities covered:** Daytona Beach, Daytona Beach Shores, New Smyrna Beach, Ormond Beach, Ponce Inlet

### 4.2 NOAA Tides & Currents

**Base URL:** `https://api.tidesandcurrents.noaa.gov/api/prod/datagetter`

**Tide predictions:**
- Station: 8721164
- Product: predictions
- Datum: MLLW
- Timezone: lst_ldt (local)
- Units: english

**Water temperature:**
- Station 8721604 (Canaveral)
- Station 8720218 (Jacksonville)
- Product: water_temperature
- Displayed as average of both stations

### 4.3 Webcam Feed

**Current source:** WESH Orlando tower camera
**URL:** `https://kubrick.htvapps.com/htv-prod-media.s3.amazonaws.com/images/dynamic/wesh/CAM13.jpg`
**Note:** This URL may change. The rebuild should make the webcam URL configurable rather than hardcoded.

---

## 5. API Service Requirements

### 5.1 Existing Endpoints (v1 — must maintain exact backward compatibility)

These endpoints are consumed by the Tidbyt device and the current website. The JSON field names, casing, and structure must remain identical.

| Endpoint | Method | Response | Notes |
|----------|--------|----------|-------|
| `/rampstatus` | GET | JSON array of ramp objects | Used by Tidbyt, iOS apps, website |
| `/tides` | GET | JSON tide/temp response | Used by Tidbyt, iOS apps |
| `/ramps` | GET | Plain text ramp status | Legacy text format |
| `/` | GET | HTML website | Serves the rebuilt website |

**`/rampstatus` — exact response contract:**

```json
[
  {
    "id": 1,
    "rampName": "BEACHWAY AV",
    "accessStatus": "OPEN",
    "objectID": 123,
    "city": "New Smyrna Beach",
    "accessID": "NSB-001",
    "location": "1400 N ATLANTIC AV"
  }
]
```

All fields required. Field names are camelCase. The Tidbyt device filters by exact `rampName` match: "CRAWFORD RD", "BEACHWAY AV", "FLAGLER AV", "3RD AV".

**`/tides` — exact response contract:**

```json
{
  "currentTideHighOrLow": "Rising",
  "tideLevelPercentage": 54,
  "waterTemp": 72,
  "tideInfo": [
    {
      "tideDateTime": "2026-03-09T11:24:00Z",
      "highOrLow": "H"
    },
    {
      "tideDateTime": "2026-03-09T17:48:00Z",
      "highOrLow": "L"
    }
  ],
  "waterTemps": [
    {
      "stationID": "8721604",
      "stationName": "Canaveral",
      "waterTemp": 73
    },
    {
      "stationID": "8720218",
      "stationName": "Jacksonville",
      "waterTemp": 71
    }
  ]
}
```

Field name notes: `currentTideHighOrLow` values are "Rising" or "Dropping" (derived from the direction to the next high/low). `tideLevelPercentage` is 0–100. `waterTemp` at the top level comes from Canaveral station. `highOrLow` is "H" or "L".

**`/ramps` — plain text format:**
```
BEACHWAY AV is : OPEN
CRAWFORD RD is : CLOSED
```

### 5.2 New/Enhanced Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v2/ramps` | GET | Versioned API — same data with pagination, filtering by city/status |
| `/api/v2/ramps/:id` | GET | Individual ramp detail |
| `/api/v2/tides` | GET | Enhanced tide data with more prediction points |
| `/api/v2/health` | GET | Health check endpoint for monitoring |
| `/api/v2/config` | GET | Client configuration (webcam URL, feature flags) |

### 5.3 Response Models

**RampStatus (v2):**
```json
{
  "id": 1,
  "ramp_name": "BEACHWAY AV",
  "access_status": "OPEN",
  "status_category": "open",
  "object_id": 123,
  "city": "New Smyrna Beach",
  "access_id": "NSB-001",
  "location": "1400 N ATLANTIC AV",
  "last_updated": "2026-03-09T14:30:00-04:00"
}
```

**TideInfoResponse (v2):**
```json
{
  "tide_direction": "Rising",
  "tide_percentage": 54,
  "water_temp_avg": 72,
  "water_temps": [
    { "station_id": "8721604", "station_name": "Canaveral", "temp_f": 73 },
    { "station_id": "8720218", "station_name": "Jacksonville", "temp_f": 71 }
  ],
  "predictions": [
    { "time": "2026-03-09T11:24:00-04:00", "type": "H" },
    { "time": "2026-03-09T17:48:00-04:00", "type": "L" }
  ],
  "retrieved_at": "2026-03-09T14:30:00-04:00"
}
```

### 5.4 Non-Functional Requirements

- Response time: < 200ms for cached data
- Availability: 99.5% uptime target
- CORS: Allow all origins (public API)
- Rate limiting: 100 requests/minute per IP
- Graceful degradation: If NOAA is unreachable, serve last-known tide/temp data
- Structured logging (JSON format)
- Environment-based configuration (no hardcoded values)

---

## 6. Database Requirements

### 6.1 Schema (Revised)

**Table: `ramp_status`**

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGSERIAL | PRIMARY KEY | Auto-increment |
| ramp_name | VARCHAR(255) | NOT NULL | Display name |
| access_status | VARCHAR(100) | NOT NULL | Raw status string |
| status_category | VARCHAR(20) | NOT NULL | open, limited, closed |
| object_id | BIGINT | NOT NULL, UNIQUE | GIS object ID |
| city | VARCHAR(100) | NOT NULL | City name |
| access_id | VARCHAR(50) | NOT NULL, UNIQUE | GIS access ID (upsert key) |
| location | VARCHAR(255) | NOT NULL | Street address |
| updated_at | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last status change |

**Table: `ramp_status_history`** (new)

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGSERIAL | PRIMARY KEY | Auto-increment |
| access_id | VARCHAR(50) | NOT NULL, FK | References ramp_status |
| access_status | VARCHAR(100) | NOT NULL | Status at this point in time |
| recorded_at | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | When this was recorded |

**Rationale:** The history table enables future features like "how long has this ramp been closed?" and trend analysis, without complicating the primary table.

### 6.2 Migration Strategy

- Provide SQL migration scripts (up/down)
- Maintain backward compatibility: the old `rampstatus` table query pattern must still work for the v1 endpoints

---

## 7. Website Requirements

### 7.1 Technology

- Vanilla HTML, CSS, JavaScript (no framework)
- Tailwind CSS for styling
- Served by the Go API (same as today)

### 7.2 Features (carry forward)

- **Header bar** showing: app title, default city, current tide info (direction, percentage), water temperature
- **Summary cards** showing counts: total ramps shown, open, limited, closed
- **City filter** — pill/chip buttons for each city, with "All Cities" default or user preference
- **Status filter** — pill/chip buttons: All Statuses, Open, Limited, Closed, Other
- **Ramp cards** — two-column responsive grid, each card showing:
  - Ramp name (bold, uppercase)
  - City
  - Status badge (color-coded: green/yellow/red)
  - Location address
  - Left border color matching status
- **Default city** — New Smyrna Beach pre-selected on load

### 7.3 Features (new)

- **Responsive mobile-first design** — works well on phones without needing the native app
- **Dark mode** — respects system preference, with manual toggle
- **Last updated timestamp** — visible in the header or footer
- **Webcam embed** — optional section showing the live webcam image (configurable URL)
- **Tide chart** — simple visual showing today's tide curve with current position marked
- **Favorites** — allow users to star/pin specific ramps (stored in localStorage)
- **PWA support** — installable on mobile home screens, offline-capable with cached last-known data

### 7.4 Design Direction

The current warm gradient (cream/sand tones) with teal header is pleasant and beach-appropriate. The rebuild should refine this aesthetic with Tailwind — cleaner typography, better card shadows, smoother transitions — while keeping the overall feel.

---

## 8. iOS App Requirements

### 8.1 Technology

- SwiftUI exclusively
- Minimum deployment target: iOS 17
- Swift 5.9+
- SwiftData for local persistence/caching

### 8.2 Features (carry forward from BeachInfo + BeachLife)

- **Ramp status list** — shows ramps with color-coded status indicators
- **Default view** — 5 NSB ramps (Beachway, Crawford, Flagler, 3rd Ave, 27th Ave)
- **Tide information** — current direction (rising/dropping), percentage, next high/low times
- **Water temperature** — display from both stations plus average
- **Webcam view** — live image with tap-to-fullscreen
- **Pull-to-refresh**
- **Last refreshed timestamp**

### 8.3 Features (new)

- **All cities view** — browse all Volusia County ramps (matching website)
- **City filtering** — same filter pills as website
- **Status filtering**
- **Favorites** — pin ramps, shown at top
- **Push notifications** — alert when a favorited ramp changes status (requires backend support)
- **Widgets** — iOS home screen widgets showing favorite ramp status
- **Live Activities** — show ramp status on Dynamic Island / Lock Screen (when at the beach)
- **Haptic feedback** on status changes
- **Settings screen** — default city, notification preferences, units (°F/°C)

### 8.4 App Architecture

- MVVM pattern
- Networking layer with async/await
- Shared Swift package for models and networking (used by iOS, watchOS, tvOS)

---

## 9. Apple Watch App Requirements

### 9.1 Technology

- SwiftUI
- watchOS 10+
- Shares networking/model code with iOS via shared Swift package

### 9.2 Features

- **Glanceable ramp status** — show favorite ramps with color-coded status dots
- **Tide info** — current direction, percentage to next change
- **Water temperature** — single number display
- **Complications:**
  - Corner: ramp count (e.g., "4/5 open")
  - Circular: tide percentage ring
  - Rectangular: next tide time + direction
- **Background refresh** — update data on a schedule (every 15 min)
- **Works independently** — does not require iPhone nearby (uses WiFi/cellular)

### 9.3 Design Considerations

- Large, legible text
- Minimal interaction — optimized for quick glances
- Green/yellow/red color coding should be distinguishable on small display
- Use SF Symbols for tide direction (arrow.up / arrow.down)

---

## 10. Apple TV App Requirements

### 10.1 Technology

- SwiftUI
- tvOS 17+
- Shares networking/model code via shared Swift package

### 10.2 Features

- **Ambient dashboard mode** — designed to run continuously as a living room beach monitor
- **Full-screen layout** showing:
  - All favorite ramps with large status indicators
  - Current tide direction and percentage (large visual arc or wave graphic)
  - Water temperature (prominent display)
  - Webcam feed (large image, auto-refreshing)
  - Current time
  - Next tide time countdown
- **Auto-refresh** — data and webcam both update every 60 seconds
- **Screensaver prevention** — keeps display active while app is foregrounded
- **Minimal remote interaction** — Siri Remote can switch between cities or toggle webcam view
- **Beautiful typography** — designed to be viewed from across the room

### 10.3 Design Considerations

- Optimized for 1080p / 4K displays
- Large fonts, high contrast
- Beach-themed ambient aesthetic (gradients, subtle wave animations)
- Safe area awareness for TV overscan
- No small text or dense information — everything readable from 10 feet away

---

## 11. Data Ingester Requirements (Rebuild)

### 11.1 Technology

- Rewritten in Go (consolidating from Python)
- Runs as a standalone binary or within the same service binary

### 11.2 GIS Query Details

**URL pattern:**
```
https://{GIS_HOST}/arcgis/rest/services/Beaches/MapServer/7/query?where=AccessStatus='{status}'&outFields=*&f=json
```

**URL encoding note:** The GIS server requires spaces in the status value to be URL-encoded as `%20`, but single quotes must remain as raw literal characters (not percent-encoded). For example: `where=AccessStatus='closed%20for%20high%20tide'`. Using standard URL encoding libraries will break the query because they encode single quotes as `%27`.

The ingester queries for each status value separately in a loop. The status values are **lowercase** in the query (the GIS server handles case matching):

```
open, closed, closed for high tide, 4x4 only, closing in progress,
closed - cleared for turtles, closed - at capacity, open - entrance only
```

**Note:** Not all status values will have ramps at any given time. A query returning zero features is normal (the GIS server returns `{"features": []}` with HTTP 200), not an error. The ingester must continue processing all remaining statuses even if some return empty results or fail.

**GIS response fields extracted:** `AccessName`, `AccessStatus`, `OBJECTID`, `City`, `AccessID`, `GeneralLoc` — found in `features[].attributes`.

### 11.3 Behavior

- Poll Volusia County GIS endpoint every 60 seconds
- Query each status type separately (loop through all known status values)
- Upsert into `ramp_status` table on `access_id` conflict
- On status change, insert a row into `ramp_status_history`
- Log all polling activity with structured logging
- Retry on GIS endpoint failure (3 attempts, exponential backoff)
- Report health status to the API health endpoint

### 11.3 Configuration

All values via environment variables:

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Full PostgreSQL connection string |
| `GIS_HOST` | Volusia County GIS server hostname (default: `maps5.vcgov.org`) |
| `POLL_INTERVAL` | Seconds between polls (default: 60) |
| `LOG_LEVEL` | Logging verbosity: debug, info, warn, error (default: info) |
| `WEB_DIR` | Path to web static files directory (auto-detected in dev, set to `/web` in Docker) |

---

## 12. IoT Device Support

### 12.1 Tidbyt (Legacy — Frozen)

**Status:** Discontinued hardware. No new development.

**Requirements:**
- The existing `/rampstatus` and `/tides` endpoints must continue to return the same JSON shape
- The Tidbyt Pixlet script (`tidbyt/main.star`) remains in the repo unchanged
- No testing or CI coverage needed for the Tidbyt code

### 12.2 TRMNL E-Ink Display (Active Platform — Rewrite)

**Status:** Active platform under continuous development. Existing Liquid template provided. To be rewritten for the new API.

**Device:** TRMNL — a low-power e-ink dashboard display that renders HTML/CSS via Liquid templates. The TRMNL platform fetches data from a configured API endpoint (a "plugin webhook") and injects it as Liquid variables into the template for rendering.

**Current implementation:**
- Liquid template (HTML + CSS) rendered by the TRMNL platform
- Monochrome design optimized for e-ink (no color, high contrast)
- Shows NSB-only: 4 ramps (3rd Ave, Crawford, Flagler, Beachway)
- Displays: current local time, tide direction, tide percentage, water temperature
- Status styling: normal text (open), underline (closed), lighter weight (limited)
- Time calculated from `trmnl.user.utc_offset` (TRMNL platform variable)

**Data contract — current template variables:**

| Variable | Type | Source | Example |
|----------|------|--------|---------|
| `tide_dir` | string | API | "Rising" |
| `tide_pct` | number | API | 54 |
| `water_temp` | number | API | 72 |
| `r_3rd.accessStatus` | string | API | "OPEN" |
| `r_crawford.accessStatus` | string | API | "OPEN" |
| `r_flagler.accessStatus` | string | API | "4X4 ONLY" |
| `r_beachway.accessStatus` | string | API | "CLOSED" |

**Status abbreviation (applies to all IoT devices):**

Ramp status strings from GIS can be long (e.g., "CLOSED - CLEARED FOR TURTLES", "OPEN - ENTRANCE ONLY"). On space-constrained IoT displays, statuses longer than 12 characters must be abbreviated. The API should return both `access_status` (full) and `access_status_short` (≤12 chars) in IoT-targeted responses. Suggested abbreviations:

| Full Status | Abbreviated (≤12 chars) |
|-------------|------------------------|
| OPEN | OPEN |
| CLOSED | CLOSED |
| 4X4 ONLY | 4X4 ONLY |
| CLOSED FOR HIGH TIDE | CLOSED-TIDE |
| CLOSED - AT CAPACITY | CLOSED-FULL |
| CLOSED - CLEARED FOR TURTLES | CLOSED-TRTL |
| CLOSING IN PROGRESS | CLOSING |
| OPEN - ENTRANCE ONLY | ENTER ONLY |

**Rebuild requirements:**

- **New API endpoint:** `/api/v2/trmnl` — a dedicated endpoint that returns JSON shaped exactly for the TRMNL plugin webhook, mapping ramp data into the named variables the template expects
- **Template rewrite:** Modernize the Liquid template while preserving the monochrome, high-contrast e-ink aesthetic
- **Design improvements:**
  - Cleaner typography hierarchy (the current 58-62px sizes are appropriate for e-ink readability)
  - Better status differentiation without color (bold/normal/strikethrough or icons)
  - Consider adding "last updated" timestamp
  - Maintain the compact 4-ramp NSB-focused layout
- **TRMNL plugin configuration:** The plugin webhook URL will point to the new `/api/v2/trmnl` endpoint
- **Template file location:** `trmnl/template.html` in the monorepo
- **No server-side rendering needed** — TRMNL handles rendering; we just provide the data endpoint and the template file

---

## 13. Monorepo Structure (Rebuild)

```
beach/
├── api/                    # Go API service
│   ├── cmd/
│   │   └── server/
│   │       └── main.go     # Entry point
│   ├── internal/
│   │   ├── handlers/       # HTTP handlers
│   │   ├── models/         # Data models
│   │   ├── services/       # Business logic
│   │   ├── ingester/       # GIS data polling
│   │   ├── noaa/           # NOAA API client
│   │   └── database/       # DB connection & queries
│   ├── migrations/         # SQL migration files
│   ├── Dockerfile
│   ├── Makefile
│   └── go.mod
├── web/                    # Website (served by API)
│   ├── index.html
│   ├── app.js
│   └── styles.css          # Tailwind
├── apple/                  # Xcode workspace
│   ├── BeachStatus/        # Shared Swift package
│   │   ├── Models/
│   │   ├── Networking/
│   │   └── Utilities/
│   ├── BeachStatusApp/     # iOS app target
│   ├── BeachStatusWatch/   # watchOS app target
│   ├── BeachStatusTV/      # tvOS app target
│   └── BeachStatus.xcworkspace
├── trmnl/                  # TRMNL e-ink display
│   └── template.html       # Liquid template for TRMNL plugin
├── tidbyt/                 # Frozen — legacy Tidbyt code
│   └── main.star
├── .do/
│   └── app.yaml            # App Platform app spec
├── .github/
│   └── workflows/
│       ├── ci.yml          # Lint, test, build on every PR
│       └── deploy.yml      # Deploy to App Platform on push to main
├── docker-compose.yml      # Local dev environment
├── README.md
├── REQUIREMENTS.md         # This document
└── LICENSE
```

---

## 14. DevOps & Infrastructure

### 14.1 Local Development

- `docker-compose.yml` providing PostgreSQL for local development (optional — can also use an external database by setting `DATABASE_URL`)
- Single `make dev` command to start the API with hot reload
- Hot reload via [Air](https://github.com/air-verse/air) with `.air.toml` config in `api/`
- **Credentials:** All environment variables live in `api/.env` (git-ignored). Copy `api/.env.example` to `api/.env` and fill in real values. The Makefile auto-loads `.env` via `include` + `export` — no credentials are hardcoded in committed files.
- Seed data for local testing

### 14.2 CI/CD — GitHub Actions

**Workflow: `ci.yml`** (runs on every PR and push to `main`)

| Step | What It Does |
|------|-------------|
| Lint | `go vet ./...` + `staticcheck ./...` |
| Test | `go test ./...` with race detector enabled |
| Build | `go build -o beach-api ./cmd/server` to verify compilation |

**Workflow: `deploy.yml`** (runs on push to `main` only, after CI passes)

| Step | What It Does |
|------|-------------|
| Build Docker image | Multi-stage build from `api/Dockerfile` |
| Run migrations | Execute pending SQL migrations against production DB |
| Deploy | Trigger App Platform deployment (auto-deploy on push, or via `doctl` CLI) |
| Smoke test | Hit `/api/v2/health` and verify 200 response |

### 14.3 Dockerfile

The Dockerfile lives at `api/Dockerfile` and uses a multi-stage build:

```
Stage 1 (builder): golang:1.22-alpine
  - Copy go.mod, go.sum → download dependencies
  - Copy api/ source + web/ directory → build static binary

Stage 2 (runtime): alpine:latest
  - Copy binary from builder
  - Copy migrations/ directory
  - Copy web/ directory to /web
  - Set WEB_DIR=/web
  - Expose $PORT
  - ENTRYPOINT: the single Go binary
```

**Static file serving:** Website files (`web/`) live at the project root and are served from the filesystem at runtime. The Go binary locates them via the `WEB_DIR` environment variable (defaulting to auto-detection of `./web`, `../web`, or `../../web` for local dev). In Docker, the Dockerfile copies `web/` to `/web` and sets `WEB_DIR=/web`. Database migration SQL files are embedded into the Go binary via `go:embed` (defined at the `api/` module root in `embed.go`).

### 14.4 Database Migrations

Migrations run automatically at application startup, before the HTTP server begins accepting traffic. This keeps the deployment model simple — no separate migration step or CI job needed.

**How it works:**
- Migration files live in `api/migrations/` as numbered pairs: `001_create_ramp_status.up.sql` / `001_create_ramp_status.down.sql`
- On boot, the Go binary checks a `schema_migrations` table to see which migrations have run
- Pending migrations execute in order inside a transaction
- If a migration fails, the transaction rolls back and the service exits with an error (App Platform will show this in logs and not route traffic to the failed instance)
- Custom lightweight migration runner in `api/internal/database/migrate.go` — reads embedded SQL files from `go:embed`, tracks applied versions in `schema_migrations` table, runs pending migrations in transactions. No external migration library needed.

**Safety rules for migrations:**
- Never drop columns or tables that v1 endpoints depend on
- Always provide both up and down scripts
- Test migrations against a local Docker PostgreSQL before pushing to main
- For destructive changes, use a two-phase approach: Phase A deploys code that stops using the column; Phase B (next deploy) drops it

### 14.5 Hosting — DigitalOcean App Platform

**Current:** App Platform (API service) + Managed PostgreSQL. Domain: donwb.com

**Rebuild — same platform, refined configuration:**

The rebuild architecture maps directly to App Platform components:

| App Platform Component | Type | What It Runs |
|------------------------|------|-------------|
| `beach-api` | Web Service | Go API binary — serves REST endpoints + website |
| (managed) | Database | DigitalOcean Managed PostgreSQL 15+ |

**Deployment model:** The Go API binary is a single service that includes the data ingester as an internal goroutine. This keeps the App Platform configuration simple — one web service, one database — with no need for a separate worker component. The ingester starts its polling loop when the server boots.

**App spec file (`.do/app.yaml`):**

The App Platform app spec is a declarative YAML file checked into the repo that defines the entire deployment. This is the bridge between "code in GitHub" and "running on App Platform":

```yaml
# .do/app.yaml
name: beach-ramp-status
region: nyc
services:
  - name: beach-api
    github:
      repo: donwb/beach
      branch: main
      deploy_on_push: true
    dockerfile_path: api/Dockerfile
    source_dir: /
    http_port: 8080
    instance_count: 1
    instance_size_slug: basic-xxs
    health_check:
      http_path: /api/v2/health
    envs:
      - key: GIS_HOST
        value: "maps5.vcgov.org"
      - key: POLL_INTERVAL
        value: "60"
      - key: LOG_LEVEL
        value: "info"
      - key: WEBCAM_URL
        value: "https://kubrick.htvapps.com/htv-prod-media.s3.amazonaws.com/images/dynamic/wesh/CAM13.jpg"
      - key: NOAA_TIDE_STATION
        value: "8721164"
      - key: NOAA_TEMP_STATIONS
        value: "8721604,8720218"
databases:
  - name: beach-db
    engine: PG
    version: "16"
    size: db-s-dev-database
    production: false
```

Note: `DATABASE_URL` is automatically injected by App Platform when a managed database is attached — no need to set it manually.

**App Platform configuration notes:**
- Build: Dockerfile-based (from `api/Dockerfile`)
- HTTP port: `8080` (mapped to `$PORT` internally)
- Health check: `/api/v2/health`
- Environment variables: set via App Platform's encrypted env var UI or via the app spec
- Auto-deploy: enabled on push to `main` branch
- Domain: `donwb.com` (custom domain, same as today)
- Run command: single binary, no process manager needed

### 14.6 Deployment Flow — From Local to Production

**First-time setup (one-time):**

1. Create the App Platform app: `doctl apps create --spec .do/app.yaml`
2. App Platform provisions the managed PostgreSQL instance and injects `DATABASE_URL`
3. First deploy builds the Docker image, runs migrations (creating all tables from scratch), and starts the service
4. Configure custom domain `donwb.com` in App Platform dashboard
5. Verify v1 endpoints return expected JSON shape before pointing DNS

**Ongoing development cycle:**

```
Local machine                    GitHub                    DigitalOcean
─────────────                    ──────                    ────────────
1. Write code
2. Run locally
   (make dev)
3. Run tests
   (make test)
4. git push ──────────────────▶ 5. PR created
                                6. CI runs (lint,
                                   test, build)
                                7. Merge to main ───────▶ 8. Auto-deploy
                                                            triggered
                                                          9. Docker build
                                                         10. Migrations run
                                                         11. Health check
                                                             passes
                                                         12. Traffic routed
                                                             to new instance
```

**Rollback:** App Platform keeps previous deployments. Rolling back is one click in the dashboard or `doctl apps create-deployment --app-id <id> --force-rebuild`.

**What lives outside App Platform:**
- Apple apps → Apple App Store
- TRMNL template → hosted by TRMNL platform (calls back to `donwb.com/api/v2/trmnl`)
- Tidbyt script → runs on the local Tidbyt device (calls back to `donwb.com/rampstatus`)

---

## 15. Testing Requirements

### 15.1 API

- Unit tests for all business logic (tide calculations, status categorization)
- Integration tests for database operations
- API endpoint tests (request/response validation)
- Target: 80% code coverage

### 15.2 Website

- Manual testing across browsers (Chrome, Safari, Firefox)
- Mobile responsive testing (iPhone, Android viewport sizes)

### 15.3 iOS / watchOS / tvOS

- Unit tests for shared networking and model layer
- UI tests for critical flows (launch, refresh, filter)
- Preview-driven development in Xcode

---

## 16. In-Scope Additions & Future Considerations

### In scope for the rebuild

These items should be included in the initial rebuild:

1. **Historical analytics** — Dashboard (website + iOS) showing ramp open/close patterns over weeks/months. Enabled by the `ramp_status_history` table (Section 6.1). Visualize trends like busiest closure days, average open hours, seasonal patterns.
2. **Weather integration** — Current weather conditions, UV index, wind speed displayed alongside tide data. Source: NOAA Weather API or OpenWeatherMap. Show on website header, iOS detail view, and Apple TV dashboard.

### Deferred — consider in architecture but not built initially

These items are not in scope for the initial rebuild but the architecture should not preclude them:

1. **Multi-region support** — Could this expand beyond Volusia County to other beach areas?
2. **Surf conditions** — Integration with surf forecast APIs (Surfline, Magic Seaweed)?
3. **User accounts** — Would persistent favorites across devices (via iCloud or API) be valuable?
4. **Android app** — Is there interest in an Android version, or is Apple-only sufficient?
5. **Notification backend** — APNs infrastructure for push notifications (requires server-side work)

---

## 17. Implementation Phases (Suggested)

### Phase 1 — Foundation
- New Go API with v1 backward-compatible endpoints + v2 endpoints
- Go-based data ingester (replacing Python)
- Updated database schema with migrations (including `ramp_status_history`)
- Weather data integration (NOAA Weather API or OpenWeatherMap)
- `.do/app.yaml` App Platform spec
- Docker Compose local dev setup
- CI/CD pipeline (GitHub Actions)
- Deploy to DigitalOcean App Platform

### Phase 2 — Website
- Rebuild website with Tailwind CSS
- All existing features + dark mode, favorites, tide chart
- Weather conditions display
- Historical analytics dashboard (ramp open/close patterns)
- PWA support

### Phase 3 — iOS App
- Unified SwiftUI app
- Shared Swift package for models/networking
- All carry-forward features + new features
- Historical analytics view
- Home screen widgets

### Phase 4 — Apple Watch & Apple TV
- Watch app with complications
- TV ambient dashboard (including weather data)
- Background refresh

### Phase 5 — TRMNL Device & Polish
- TRMNL e-ink template rewrite + dedicated `/api/v2/trmnl` endpoint
- Push notifications infrastructure
- Performance optimization
- Documentation

---

---

## 18. Implementation Status

### Phase 1 — Foundation ✅ Complete (March 9, 2026)

**Delivered:**
- Go API service with Echo v4 — v1 backward-compatible endpoints (`/rampstatus`, `/tides`, `/ramps`) + v2 endpoints (`/api/v2/ramps`, `/api/v2/tides`, `/api/v2/health`, `/api/v2/config`)
- Go data ingester replacing Python — polls GIS every 60s with 3-retry exponential backoff, upserts to DB, tracks status changes in history table
- PostgreSQL schema with auto-running migrations (`ramp_status`, `ramp_status_history`, `schema_migrations`)
- NOAA client for tide predictions and water temperature with direction/percentage calculation
- Dockerfile (multi-stage), docker-compose.yml, `.do/app.yaml`, GitHub Actions CI/CD
- Makefile with `dev` (Air hot reload), `test`, `lint`, `build` targets
- Unit tests for models and ingester with table-driven tests and httptest mocks

**Key decisions made:**
- Echo v4 chosen as HTTP framework (over Chi)
- Custom migration runner (no external library) using `go:embed` for SQL files
- Web files served from filesystem (not embedded) — `WEB_DIR` env var controls path
- GIS host: `maps5.vcgov.org` (not `vcgis.vcgov.org`)
- Ingester runs as a goroutine inside the API binary (not a separate process)
- Database: pgx v5 with connection pool (max 10 conns, min 2)
- Credentials managed via `api/.env` (git-ignored) with `api/.env.example` committed as template

**Not yet started:** Weather integration (deferred from Phase 1 to Phase 2)

---

*This is a living document. It will be updated as architectural decisions are finalized during implementation.*
