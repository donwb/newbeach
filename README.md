# Beach Ramp Status

Real-time beach access ramp status, tide data, and weather for Volusia County, Florida — across six platforms from a single codebase.

**Live:** [beach-ramp-status-kff7g.ondigitalocean.app](https://beach-ramp-status-kff7g.ondigitalocean.app)

## What It Does

Volusia County operates ~30 vehicle beach access ramps that open and close throughout the day based on tides, weather, capacity, and turtle nesting. This app polls the county GIS system every 60 seconds and serves that data alongside NOAA tide predictions, water temperature, and NWS weather — so you can check conditions before you load up the truck.

## Platforms

| Platform | Tech | What You See |
|----------|------|--------------|
| **Website** | Vanilla JS + Tailwind | Responsive dashboard with ramp grid, tide chart, weather, webcam, dark mode |
| **iOS / iPad** | SwiftUI | Universal app with adaptive layout, city/status filtering, pull-to-refresh |
| **Apple Watch** | SwiftUI | Glance-first ramp status — check your wrist before heading out |
| **Apple TV** | SwiftUI | Ambient dashboard for the beach house — leave it on all day |
| **TRMNL** | Liquid template | Monochrome e-ink display (4 NSB ramps + tide + temp) |
| **Tidbyt** | Pixlet (frozen) | Legacy IoT pixel display — still works, never touched |

## Architecture

```
Volusia County GIS ──poll 60s──▶ Go Service ◀── NOAA Tides
                                    │          ◀── NWS Weather
                                    │
                                    ├── PostgreSQL (ramp_status + history)
                                    │
                                    ▼
                          REST API (v1 + v2)
                     ╱    │    │     │      ╲
                   Web   iOS  Watch  TV    TRMNL
                                            ▲
                   Tidbyt ──── v1 ──────────┘
```

One Go binary does everything: HTTP API, data ingestion, and static file serving. The Apple apps share a Swift package (`BeachStatus`) for models, networking, and utilities — no duplicated code across iOS, watchOS, and tvOS. The TRMNL e-ink display polls the v2 API directly; the legacy Tidbyt device still consumes v1.

## Repository Structure

```
api/          Go API + data ingester (Echo v4, pgx, NOAA/NWS clients)
web/          Website (vanilla HTML/JS + Tailwind CSS, served by the API)
apple/        Xcode workspace — iOS, watchOS, tvOS targets + shared Swift package
trmnl/        TRMNL e-ink display template
tidbyt/       Frozen — legacy Tidbyt Pixlet script
```

## Local Development

```bash
# Prerequisites: Go 1.24+, PostgreSQL, Make

cp api/.env.example api/.env    # fill in DATABASE_URL
cd api && make dev               # starts with hot reload (Air)
```

The API serves the website at `localhost:8080` and starts polling GIS data immediately.

## Deployment

Hosted on DigitalOcean App Platform. Push to `main` triggers CI (lint, test, build) then auto-deploys via the app spec in `.do/app.yaml`. Migrations run at startup — no separate migration step.

## Data Sources

- **Ramp status:** Volusia County ArcGIS MapServer (8 status types across ~30 ramps in 5 cities)
- **Tides:** NOAA Tides & Currents API — Station 8721164 (Ponce Inlet)
- **Water temp:** NOAA stations 8721604 (Canaveral) + 8720218 (Jacksonville), averaged
- **Weather:** NWS api.weather.gov — current conditions + 6-period forecast

## API

v1 endpoints maintain backward compatibility for the Tidbyt device:

| Endpoint | Purpose |
|----------|---------|
| `GET /rampstatus` | All ramps (Tidbyt format) |
| `GET /tides` | Tide + water temp (Tidbyt format) |

v2 endpoints power the website, Apple apps, and TRMNL display:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v2/ramps` | Ramps with filtering |
| `GET /api/v2/tides/chart` | Hourly tide curve + H/L markers |
| `GET /api/v2/weather` | Current conditions + forecast |
| `GET /api/v2/activity` | Recent status changes feed |
| `GET /api/v2/config` | Client configuration |
| `GET /api/v2/health` | Health check |

## Built With

Go 1.24 · Echo v4 · pgx · PostgreSQL · SwiftUI · Swift Charts · Tailwind CSS · GitHub Actions · DigitalOcean App Platform

---

*Built for checking the ramps before you hitch up the boat.*
