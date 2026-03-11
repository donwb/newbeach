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
| `/api/v2/ramps` | GET | Versioned API — same data with filtering by city/status |
| `/api/v2/ramps/:id` | GET | Individual ramp detail |
| `/api/v2/ramps/:id/history` | GET | Historical status changes for a specific ramp (`?limit=100`) |
| `/api/v2/activity` | GET | Recent status changes across all ramps (`?limit=50`, max 200) |
| `/api/v2/tides` | GET | Enhanced tide data with high/low predictions + hourly curve |
| `/api/v2/tides/chart` | GET | Dedicated chart endpoint: hourly curve, H/L markers, current time |
| `/api/v2/weather` | GET | Current conditions (incl. wind speed/gust) + forecast from NWS API (api.weather.gov) |
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
- Universal app (iPhone + iPad)
- Support both landscape and portrait orientations
- Match web app color scheme and visual design (sand/cream tones, teal accents, status colors)

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
- Shares networking/model code with iOS via shared `BeachStatus` package

### 9.2 Features

- **Glance-style main screen** — shows NSB ramps with color-coded status indicators at a glance (optimized for 2-second wrist check)
- **Drill-down list** — ability to browse all Volusia County ramps with scrollable list
- **Ramps only** — no tide or weather data on watch (phone/iPad handles that)
- **Complications (both styles):**
  - Count-based: show open/closed/limited counts (e.g., "8 Open")
  - Single ramp: show a favorite ramp's name and current status
- **Background refresh** — update data on a schedule (every 15 min)
- **Works independently** — does not require iPhone nearby (uses WiFi/cellular)

### 9.3 Design Considerations

- Large, legible text
- Minimal interaction — glance first, drill-down second
- Green/yellow/red color coding should be distinguishable on small display
- Use SF Symbols for status icons (checkmark.circle, exclamationmark.triangle, xmark.circle)

---

## 10. Apple TV App Requirements

### 10.1 Technology

- SwiftUI
- tvOS 17+
- Shares networking/model code via shared `BeachStatus` package

### 10.2 Features

- **Ambient dashboard mode** — auto-refreshing full-screen status board designed to stay on screen (beach house / surf shop display)
- **Full-screen layout** showing all data:
  - Ramp status grid with large color-coded status indicators
  - Tide chart with current direction and percentage
  - Weather: current conditions and forecast
  - Current time
- **Default to New Smyrna Beach** — matches phone/web behavior, with Siri Remote navigation to switch cities
- **Auto-refresh** — data updates every 60 seconds
- **Screensaver prevention** — keeps display active while app is foregrounded
- **Minimal remote interaction** — Siri Remote can switch between cities
- **No Top Shelf extension** — just the main dashboard app
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

### Phase 2 — Website
- Rebuild website with Tailwind CSS
- All existing features + dark mode, favorites, tide chart
- Weather conditions display (including wind speed/gusts)
- Historical analytics dashboard (ramp open/close patterns)
- PWA support

### Phase 3 — Production Deploy & CI/CD
- Dockerfile validation and optimization
- GitHub Actions CI pipeline (lint, test, build on every PR)
- GitHub Actions CD pipeline (build and push Docker image on merge to main)
- Deploy to DigitalOcean App Platform
- Verify migrations run automatically at startup in production
- Validate all environment variables in production
- Smoke test: v1 endpoints (Tidbyt compatibility), v2 endpoints, website

### Phase 4 — iOS App
- Universal SwiftUI app (iPhone + iPad), landscape + portrait
- Shared Swift package (`BeachStatus/`) for models, networking, utilities
- Match web app look/feel (sand/cream, teal header, status colors)
- All carry-forward features + city/status filtering, favorites
- Weather + wind display, tide chart, webcam
- MVVM architecture, async/await networking, SwiftData caching
- Xcode project scaffolding created manually; all Swift code written by Claude Code

### Phase 5 — Apple Watch & Apple TV ✅
- Watch glance-first app with NSB default and drill-down to all cities
- TV ambient dashboard with ramps, tide chart, weather, auto-refresh
- Programmatic app icons for all three platforms (iOS, watchOS, tvOS)

### Phase 6 — TRMNL Device ✅
- TRMNL e-ink template rewrite for 800×480 monochrome display
- Uses existing v2 endpoints via TRMNL multi-URL namespaced webhooks
- Abbreviated status strings + monochrome visual differentiation (bold/italic/strikethrough)

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

**Deferred:** Weather integration (moved to Phase 2), CI/CD pipeline and production deploy (moved to Phase 3)

### Phase 2 — Website ✅ Complete (March 10, 2026)

**Backend additions:**
- NWS weather client (`internal/weather/client.go`) — current conditions + forecast from api.weather.gov, cached grid/station lookups, concurrent fetches, Celsius→Fahrenheit and km/h→mph conversion, wind gust support
- Hourly tide predictions (`FetchHourlyPredictions` in NOAA client) — `interval=h` for ~24 data points per day, enabling smooth tide chart rendering
- History endpoint (`/api/v2/ramps/:id/history`) — per-ramp status change history from `ramp_status_history` table
- Activity feed endpoint (`/api/v2/activity`) — recent changes across all ramps with joined ramp name/city
- Tide chart endpoint (`/api/v2/tides/chart`) — dedicated endpoint returning hourly curve, H/L markers, and server time
- Weather endpoint (`/api/v2/weather`) — current conditions + 6-period forecast

**Website delivered (6 files in `web/`):**
- `index.html` — Tailwind CSS via CDN (Play CDN for JIT), responsive layout, all sections
- `app.js` — ~500 lines vanilla JS: API fetching, DOM rendering, canvas tide chart, filters, favorites, dark mode, auto-refresh
- `styles.css` — minimal custom CSS (card animation, scrollbar styling)
- `manifest.json` + `sw.js` — PWA support with network-first API caching and cache-first static assets
- `icons/icon.svg` — SVG app icon

**Features delivered:**
- Header bar with tide direction/percentage, water temperature, weather conditions, wind speed/gusts pill, dark mode toggle
- Summary cards with color-coded counts (total/open/limited/closed)
- City filter pills (title case display, New Smyrna Beach pre-selected)
- Status filter pills (All/Open/Limited/Closed)
- Ramp cards in two-column responsive grid with color-coded left borders, status badges, favorite stars
- Favorites persisted in localStorage, favorited ramps sorted to top
- Dark mode with system preference detection + manual toggle (persisted)
- Canvas-rendered tide chart with hourly curve, H/L markers, "NOW" indicator, axis labels
- Live webcam with 60-second auto-refresh
- 6-period weather forecast cards with wind speed/direction and gust warnings (NWS data)
- Recent activity feed with relative timestamps and color-coded status dots
- Mobile-first responsive design (tested at 390px iPhone width)
- PWA installable with offline-capable service worker
- Auto-refresh all data every 60 seconds
- Last updated timestamp in footer

**Key decisions made:**
- Tailwind via CDN (no build step) — `@apply` not supported, all classes applied inline via JS
- Canvas API for tide chart (no charting library)
- NWS API (api.weather.gov) chosen over OpenWeatherMap — free, no API key required, already in NOAA ecosystem
- GIS city names arrive uppercase; `titleCase()` utility converts for display while preserving exact-match filtering
- Weather client caches grid point and station lookups (they never change for fixed coordinates)

**Not yet built from Phase 2 requirements:** Historical analytics dashboard (ramp open/close pattern visualization), PWA offline page

### Phase 3 — Production Deploy & CI/CD ✅ Complete (March 10, 2026)

**Infrastructure fixes:**
- Aligned Go version to 1.24 across `go.mod`, Dockerfile (`golang:1.24-alpine`), and GitHub Actions
- Fixed repo name in `.do/app.yaml` (`donwb/beach` → `donwb/newbeach`)
- Fixed `GIS_HOST` in `docker-compose.yml` (`maps5.vcgov.org`)
- Merged separate `ci.yml` and `deploy.yml` into single workflow with dependency chain

**CI/CD pipeline (`.github/workflows/ci.yml`):**
- Single workflow with two jobs: `lint-test-build` → `deploy`
- `lint-test-build` runs on all pushes to main + PRs: go vet, staticcheck, `go test -race`, go build (with PostgreSQL 16 service for integration tests)
- `deploy` runs only on push to main, only after CI passes: doctl deploy to DigitalOcean App Platform + 30-second smoke test of `/api/v2/health`
- PR-triggered runs skip the deploy job entirely

**DigitalOcean App Platform (`.do/app.yaml`):**
- Service: `beach-api` — Dockerfile build, 1x basic-xxs instance, health check at `/api/v2/health`
- Database: external AWS RDS (PostgreSQL) — `DATABASE_URL` set as encrypted secret in DO dashboard
- Auto-deploy on push to main via GitHub integration
- Production URL: `https://beach-ramp-status-kff7g.ondigitalocean.app`

**Production verification:**
- v1 endpoints (`/rampstatus`, `/tides`) — working, Tidbyt compatible
- v2 endpoints (`/api/v2/ramps`, `/api/v2/weather`, `/api/v2/tides/chart`, `/api/v2/activity`) — all returning live data
- Website served at root (`/`) with all Phase 2 features
- Migrations run automatically at startup
- GIS ingester polling every 60 seconds, ramp data populating

**Key decisions made:**
- External AWS RDS database instead of DO managed PostgreSQL (same instance for dev and prod)
- Single GitHub Actions workflow file (not separate CI and deploy files) — deploy job uses `needs:` to depend on CI passing
- Smoke test uses DO app ingress URL (not custom domain) for reliability
- Docker image validated locally before first push (`docker build -f api/Dockerfile`)

### Phase 4 — iOS App ✅ Complete (March 11, 2026)

**BeachStatus shared Swift package (`apple/BeachRamp/BeachStatus/`):**
- SPM package targeting iOS 17, watchOS 10, tvOS 17, macOS 13
- Models: `Ramp`, `TideInfo`, `TideChartData`, `WaterTempReading`, `TidePrediction`, `WeatherInfo`, `CurrentConditions`, `ForecastPeriod`, `AppConfig` — all Codable/Sendable with snake_case CodingKeys matching API
- Networking: `APIClient` actor with async/await, custom date decoding (ISO 8601 + fractional seconds + time-only), all five v2 endpoints
- Utilities: `String.titleCased` for GIS data normalization (uppercase → Title Case)

**App architecture:**
- SwiftUI with `@Observable` view model (MVVM)
- Universal app (iPhone + iPad) with adaptive layout: single-column scroll on iPhone, two-column split on iPad
- Landscape and portrait orientation support
- `BeachViewModel` fetches all data concurrently via `TaskGroup`
- Foreground refresh: `scenePhase` observer triggers data reload when app becomes active
- Pull-to-refresh support

**Views created:**
- `HeaderView` — ocean gradient header with weather/wind/tide info pills and water temp badge
- `FilterBarView` — horizontal scrolling city picker + status filter pills with count badges
- `RampCardView` — card with status icon, ramp name, location, and colored status badge
- `TideChartView` — Swift Charts tide graph with area fill, high/low point markers, "now" rule line, and prediction labels
- `WeatherSectionView` — horizontally scrolling forecast cards with SF Symbol weather icons, temperature, wind, and gust display
- `WaterTempView` — NOAA station temperature readings with average
- `WebcamView` — AsyncImage webcam feed with loading/error states
- `ContentView` — main view orchestrating layout, data loading, and refresh

**Theme (`AppTheme.swift`):**
- Ocean palette (teal): ocean50–ocean900 matching web Tailwind config
- Sand palette: sand50–sand300 for warm backgrounds
- Status colors: emerald/amber/red for open/limited/closed
- Tide chart colors: ocean-600 high, indigo-500 low, amber-600 now marker
- `StatusCategory` extensions for color, label, and SF Symbol icon name

**Key decisions:**
- Default city filter set to "New Smyrna Beach" on first launch (matching web app behavior, driven by `/api/v2/config` `default_city`)
- No UIKit dependency — pure SwiftUI + Color extensions for adaptive colors
- Xcode project scaffolding managed manually; all Swift source written by Claude Code (pbxproj never edited by agent)
- `Item.swift` (SwiftData template) left in project for user to remove in Xcode
- `.gitignore` updated with Xcode/Swift exclusions (xcuserdata, DerivedData, .build, .swiftpm, Package.resolved)

**Not yet built from Phase 4 requirements:** Favorites system, push notifications, widgets, Live Activities, haptic feedback, settings screen, SwiftData caching

### Phase 5 — Apple Watch & Apple TV ✅ Complete (March 11, 2026)

**watchOS app (`BeachRampWatch Watch App/`):**
- Glance-first design — main screen shows NSB ramp count summary (colored status dots) with scrollable ramp list below
- Drill-down toggle: "Show All Cities" expands from NSB-only to all Volusia County ramps
- `WatchViewModel` fetches ramps + config only (no tide/weather — phone handles that)
- `WatchTheme.swift` with watch-specific color definitions and `StatusCategory` extensions (`watchColor`, `label`, `iconName`)
- NavigationStack with List-based UI: `WatchRampRow` cards with SF Symbol status icons, ramp name, location, and colored status text
- `StatusDot` summary row at top for quick open/limited/closed counts
- Foreground refresh on app activation
- Works independently via WiFi/cellular (no iPhone dependency)

**tvOS app (`BeachRampTV/`):**
- Ambient dashboard — full-screen status board designed to stay on screen (beach house / surf shop display)
- Ocean gradient background (ocean800 → ocean700 → ocean600)
- Top bar: "Beach Ramp Status" title + live clock (Eastern time, updated every 30s)
- Left panel: ramp grid (2-column `LazyVGrid`) with `TVRampCard` showing status icon, ramp name, location, and colored status text
- Right panel: tide section with Swift Charts area/line chart, current direction arrow, percentage, H/L predictions; weather section with current temp, conditions, wind/gusts, and 4-period forecast row
- City header with `TVStatusBadge` counts (open/limited/closed) and navigation hint
- Siri Remote navigation: left/right `onMoveCommand` cycles through cities
- Default to New Smyrna Beach on first load (via `/api/v2/config`)
- Auto-refresh every 60 seconds via `Task.sleep` loop with cancellation support
- `TVViewModel` loads all data concurrently via `TaskGroup` (ramps, tides, tideChart, weather, config)
- `TVTheme.swift` with TV-optimized color palette and `StatusCategory` extensions (`tvColor`, `tvLabel`, `tvIcon`)
- No Top Shelf extension

**App icons (all three platforms):**
- Programmatic icon generation via Swift/AppKit scripts (`generate_icons.swift`, `generate_tv_icons.swift`)
- Design: teal ocean wave on sand/cream background with white wave crests
- iOS: 1024×1024 single icon in `AppIcon.appiconset` (Xcode auto-generates all sizes)
- watchOS: 1024×1024 single icon in `AppIcon.appiconset`
- tvOS: layered imagestack with landscape icons — Back layer at 400×240 (1x), 800×480 (2x) for home screen; 1280×768 for App Store

**Key decisions:**
- Separate theme files per platform (AppTheme, WatchTheme, TVTheme) with platform-specific `StatusCategory` extensions to avoid UIKit/AppKit cross-compilation issues
- Watch created as "Watch-only App" (not companion) since it fetches data directly from the API — no iPhone dependency
- TV auto-refresh uses structured concurrency (`Task` with `while !Task.isCancelled` loop) instead of `Timer` for better lifecycle management
- `NSImage(size:)` creates Retina (2x) images on macOS — icons resized to correct pixel dimensions via `sips`
- tvOS icons are landscape (5:3 ratio), not square — separate generation script for correct aspect ratios

**Not yet built from Phase 5 requirements:** Watch complications (count-based and single-ramp), watch background refresh (15-min schedule), screensaver prevention on tvOS

### Phase 6 — TRMNL Device ✅ Complete (March 11, 2026)

**TRMNL e-ink template (`trmnl/template.html`):**
- Clean monochrome design for 800×480 e-ink display
- NSB-focused: 4 ramps ordered top-to-bottom: 3rd Ave, Flagler Ave, Crawford Rd, Beachway Ave
- Header: title + water temperature (rounded from `water_temp_avg`) + local clock (via `trmnl.user.utc_offset`)
- Tide bar: direction arrow (↑/↓) + label + visual percentage bar (CSS fill) + numeric percentage
- Ramp rows: human-readable name + abbreviated status with visual differentiation
- Footer: location label + app name

**Status differentiation (no color — e-ink monochrome):**
- Open → **bold** (font-weight 800)
- Limited → *italic* (font-weight 600, font-style italic)
- Closed → ~~strikethrough~~ (font-weight 300, text-decoration line-through)
- Category determined from `status_category` field (not string matching)

**Status abbreviation (Liquid logic in template):**
- Long GIS strings abbreviated to ≤12 characters per requirements table
- `CLOSED FOR HIGH TIDE` → `CLOSED-TIDE`, `CLOSED - AT CAPACITY` → `CLOSED-FULL`, `CLOSED - CLEARED FOR TURTLES` → `CLOSED-TRTL`, `CLOSING IN PROGRESS` → `CLOSING`, `OPEN - ENTRANCE ONLY` → `ENTER ONLY`
- Short statuses (`OPEN`, `CLOSED`, `4X4 ONLY`) pass through unchanged

**TRMNL plugin webhook configuration (two namespaced URLs):**
- `ramps` → `https://beach-ramp-status-kff7g.ondigitalocean.app/api/v2/ramps?city=NEW%20SMYRNA%20BEACH`
- `tides` → `https://beach-ramp-status-kff7g.ondigitalocean.app/api/v2/tides`

**Variable paths used in template:**
- `ramps[]` — array of ramp objects, looped and matched by `ramp_name`
- `ramps[].access_status` — raw status string (abbreviated in template)
- `ramps[].status_category` — `"open"`, `"limited"`, `"closed"` (drives CSS class)
- `tides.tide_direction` — `"Rising"` or `"Dropping"`
- `tides.tide_percentage` — 0–100
- `tides.water_temp_avg` — float, rounded in template with `| round`
- `trmnl.user.utc_offset` — TRMNL platform variable for local time calculation

**Key decisions:**
- No dedicated `/api/v2/trmnl` endpoint — uses existing v2 endpoints with TRMNL's multi-URL namespaced webhook
- City filtering done via query parameter (`?city=NEW%20SMYRNA%20BEACH`) rather than template-side filtering
- Template loops through ramps array and matches by `ramp_name` to assign display variables — avoids hardcoded array indices
- Uses `status_category` field for CSS class selection (cleaner than string-matching `access_status`)
- All status abbreviation handled in Liquid template logic (no backend changes needed)
- Template pasted into TRMNL dashboard (not served from URL)
- Pure CSS layout (flexbox), no JavaScript — e-ink displays don't execute JS
- 27th Ave removed for space — 4 ramps displayed (3rd Ave, Flagler, Crawford, Beachway)

---

*This is a living document. It will be updated as architectural decisions are finalized during implementation.*
