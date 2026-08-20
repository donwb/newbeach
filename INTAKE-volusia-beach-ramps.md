---
app: Beach Ramp Status
slug: volusia-beach-ramps
version: >
  Apple apps: 1.0 (MARKETING_VERSION = 1.0 on all targets,
  apple/BeachRamp/BeachRamp.xcodeproj/project.pbxproj). The API/web service is
  unversioned — continuous deploy from main (no git tags in repo).
status: >
  live (web + API verified 2026-08-12: GET https://beach.donwb.com/api/v2/ramps
  returned HTTP 200 with 27 ramps; auto-deploy on push to main per .do/app.yaml).
  App Store presence of the Apple apps could NOT be verified from this repo — see
  distribution.
platforms: [web, iOS (iPhone + iPad), watchOS, tvOS, TRMNL e-ink (OG + X)]
distribution:
  app_store_url: none — neither Apple app has been submitted. Two App Store
    Connect records exist, both in Prepare for Submission ("Beach Ramp Status"
    tvOS, "Beach Ramp iOS App" iOS); they are being consolidated onto one
    record. Unified bundle ID as of 2026-08-15: com.donwb.BeachRampTV for BOTH
    the iOS and tvOS app targets (that shared ID is what allows a single ASC
    record to carry both platforms), plus com.donwb.BeachRampTV.watchkitapp for
    the watch app, which is out of scope for 1.0. Release automation:
    `make flight` → apple/scripts/flight.sh.
  other: https://beach.donwb.com (primary domain, .do/app.yaml:14; donwb.com is
    an ALIAS during transition, .do/app.yaml:16). Web app is an installable PWA
    (web/manifest.json, web/sw.js).
pricing:
  model: free
  amount: $0 — no StoreKit, purchase, or subscription code anywhere in apple/
    (grep for StoreKit/purchase/subscription returns nothing); no payment
    provider config in the repo. Note this proves absence of in-app payment
    code, not the App Store price field — that lives in App Store Connect.
  free_tier: everything is free; there is no gate. The only key-protected
    surface is the operator admin API (/api/v2/admin/*, X-Api-Key,
    api/internal/handlers/routes.go:74-82), which is not a user feature.
account_required: no — no sign-in, auth, or user identity anywhere in web/ or
  apple/; all public v2 endpoints are unauthenticated
  (api/internal/handlers/routes.go:60-72).
---

## 1. The mechanism (one paragraph)

A single Go binary (Echo v4) is both the API and the ingester: at startup it
spawns a background goroutine that polls the Volusia County ArcGIS server
(`maps5.vcgov.org`) every 60 seconds — one query per known status string, eight
of them — and upserts the results into Postgres, keeping an append-only history
of every status change (api/cmd/server/main.go:56,143-152,
api/internal/ingester/ingester.go:80-101, api/internal/ingester/gis.go:13-22,
api/migrations/002). Tides and water temperature come from NOAA CO-OPS
(tide predictions from station 8721164 in prod, water temp averaged across
Trident Pier and Mayport, .do/app.yaml:65-70); current conditions and forecast
come from the National Weather Service API for New Smyrna Beach coordinates
(api/internal/weather/client.go:14-21). The same binary serves the vanilla
JS + Tailwind website at `/` and JSON at `/api/v2/*` to the iPhone, iPad,
Apple Watch, Apple TV, and two TRMNL e-ink displays. Live beach cams are
YouTube streams whose HLS URLs are resolved by yt-dlp running on a cron on a
residential-IP home machine — because YouTube blocks datacenter IPs — and
pushed back into the database (scripts/update-stream-url.sh:1-6,
api/cmd/server/main.go:131-135).

## 2. Shipped features

- Live ramp board: 27 county beach ramps with raw status + open/limited/closed
  category, filterable by city and status (live API count; web/app.js:170-260,
  api/internal/models/ramp_status.go:49-60).
- Status change history: per-ramp history endpoint + recent-activity feed
  (routes.go:63-64, migrations/002).
- Tide chart with high/low predictions, tide direction, and rise percentage
  (web/index.html:139-150, /api/v2/tides + /api/v2/tides/chart, routes.go:65-66).
- Water temperature from two NOAA stations plus average (live /api/v2/tides
  response; .do/app.yaml:68-70).
- NWS current conditions + multi-day forecast (api/internal/weather/client.go,
  routes.go:67).
- Live beach cam on the web (HLS via hls.js, Safari native;
  web/app.js:350-372, web/index.html:188-189).
- Multi-camera switcher on iOS and tvOS — 5 cameras seeded south-to-north
  (New Smyrna Beach, Ponce Inlet, Dunlawton, Ormond Beach, Ormond-By-The-Sea;
  api/migrations/004_create_cameras.up.sql;
  apple/.../Views/CameraSwitcherView.swift wired in ContentView.swift:123;
  tvOS "coastline rail" switcher, BeachRampTV/ContentView.swift:121-128,708-716).
- Apple Watch app: glance-style New Smyrna Beach ramp list with drill-down to
  all ramps ("BeachRampWatch Watch App/ContentView.swift:11").
- Two TRMNL e-ink templates: OG (800×480, 1-bit, abbreviated statuses) and X
  (1872×1404, 16-level grayscale, server-rendered tide curve)
  (trmnl/template.html, trmnl/template-x.html, CLAUDE.md TRMNL section).
- Installable PWA with service worker (web/manifest.json, web/sw.js).
- Dark mode on the web via prefers-color-scheme + manual toggle
  (web/index.html, CLAUDE.md).
- Ingestion health surfaced at /api/v2/health — reports starting/ok/degraded,
  degraded after 5 missed clean polls (api/internal/ingester/ingester.go:42-53).

## 3. Numbers worth quoting

- 60 seconds between county GIS polls (default in api/cmd/server/main.go:56;
  explicitly set to "60" in prod, .do/app.yaml:56-58).
- 27 ramps currently tracked (live /api/v2/ramps, 2026-08-12).
- 5 cities on the board: Daytona Beach, Daytona Beach Shores, New Smyrna
  Beach, Ormond Beach, Ponce Inlet (live API city values).
- 8 distinct county status strings polled, mapped to 3 categories
  (open/limited/closed) (gis.go:13-22, ramp_status.go:49-60).
- 5 live beach cams, ordered south-to-north along the coast (migrations/004).
- 2 NOAA water-temperature stations averaged (Trident Pier, Port Canaveral +
  Mayport; .do/app.yaml:68-70).
- 1 Go binary runs everything — API, ingester, and static site, on a single
  basic-xxs DigitalOcean instance (.do/app.yaml:45-46, main.go).
- 7 screens fed by that one service: browser, iPhone, iPad, Apple Watch,
  Apple TV, TRMNL OG, TRMNL X (see V3 below re: "six").
- 12 characters — the max status length the OG e-ink display can fit, so the
  API ships pre-abbreviated statuses (ramp_status.go:62-64, CLAUDE.md).
- 1.8× — the TRMNL X firmware upscale factor; templates render at 1040×780 CSS
  px for a 1872×1404 panel (CLAUDE.md TRMNL section).
- 6 numbered SQL migrations, embedded in the binary and run at startup
  (api/migrations/, main.go:87-96).
- 0 frameworks on the web — vanilla HTML/JS, Tailwind via CDN, hls.js for
  video (web/index.html:15-16,188-189).

## 4. Privacy & data flow

- No account, no analytics SDK, no tracking code in web/ or apple/ (no
  analytics/telemetry imports anywhere; web has only Tailwind CDN + hls.js CDN
  script tags, web/index.html:15-16,188-189).
- Data flow is one-directional: clients GET public JSON from beach.donwb.com
  (Apple apps are pinned to the DigitalOcean hostname,
  BeachStatus/Sources/BeachStatus/Networking/APIClient.swift:14). Nothing
  user-generated is uploaded; the only POSTs are an unauthenticated
  video-refresh trigger and key-protected admin endpoints (routes.go:72,74-82).
- Third-party fetches happen server-side (county GIS, NOAA, NWS), not from
  the user's device. Browser loads two CDN scripts (jsdelivr, tailwindcss) and
  the HLS video segments from YouTube/Google CDN — so Google sees video-viewer
  IPs, as with any embedded stream.
- iOS caching is local (SwiftData per CLAUDE.md conventions).
- Strongest supportable sentence: "No account, no sign-in, no analytics —
  the apps only ever download public beach data; nothing about you is
  collected or uploaded." (Avoid claiming zero third-party contact: watching
  the beach cam streams video from YouTube's CDN, and the website loads two
  public CDN scripts.)

## 5. Site-claim audit

- **V1 tagline** ("A live look at the beach, tides, and if the ramps to the
  beach are open") — **TRUE.** Live cam (web/app.js:350), tides
  (routes.go:65-66), ramp status (routes.go:61). 
- **V2** (ramps + tide, water temp, weather from NOAA and NWS) — **TRUE.**
  Tides/water temp from NOAA CO-OPS (api/internal/noaa/client.go), weather
  from api.weather.gov (api/internal/weather/client.go:14-21). Both sources
  verified live 2026-08-12.
- **V3** ("One Go service polls the county every sixty seconds and feeds six
  screens…") — **NEEDS NUANCE.** "One Go service" is literally true — a single
  binary/process (main.go:143-152), and 60 s is the exact prod interval
  (.do/app.yaml:56-58). But the screen count is now **seven**: browser,
  iPhone, iPad, Watch, TV, and **two** TRMNL e-inks (OG + X are separate
  devices with separate templates, trmnl/template.html + template-x.html).
  Suggested wording: "…and feeds seven screens, from a browser tab to an
  Apple Watch to a pair of e-ink displays." (Six is defensible only if
  "e-ink" is counted as one category.)
- **V4 platforms** ("Web · iPhone · iPad · Watch · TV · e-ink") — **TRUE.**
  Web (served at /), iOS target with TARGETED_DEVICE_FAMILY "1,2,7"
  (iPhone + iPad; 7 = runs on Apple Vision as "Designed for iPad"),
  watch target (family 4), TV target (family 3) — project.pbxproj; two e-ink
  templates in trmnl/.
- **V5** ("Free" / "Free · no account") — **TRUE** as far as this repo can
  prove: no StoreKit/IAP code, no auth, public unauthenticated API. (Final
  App Store price field lives in App Store Connect, outside this repo.)
- **V6 status chip** ("LIVE · IOS") — **NEEDS NUANCE.** The web + API are
  verifiably live (HTTP 200, auto-deploy from main). The iOS App Store
  listing is **UNVERIFIED from this repo** — no store URL or metadata exists
  here. If the chip means "live, on iOS," confirm the listing outside the
  repo; "LIVE · WEB + APPS" may be safer if store status is uncertain.
- **V7 feature cards** — **TRUE.** "Every ramp, every status": open/limited/
  closed categories (ramp_status.go:49-60) filtered by city (web/app.js:170,
  web/index.html:111-114). "Tides and water temp": routes.go:65-66 + live
  response. "Live beach cam": web/app.js:350-372 — and undersold: iOS/tvOS
  now have a 5-camera switcher (see §2).
- **V8 sample ramp names** (Granada, Dunlawton, Hartford, Milsap, Beville) —
  **NEEDS NUANCE.** Granada Blvd, Dunlawton Blvd, Hartford Av, and Milsap Rd
  are all real ramps in the live feed. **"Beville" is not** — no such ramp
  exists in the current 27. Swap it for a real one: Cardinal Dr, Flagler Av,
  Seabreeze Blvd, Beach St, or Rockefeller Dr (all live 2026-08-12).
  Plausibility note: statuses flip a lot — at night the whole board reads
  CLOSED (beach driving hours), so a sample board mixing open/limited/closed
  reads like daytime.
- **V9 public API** — **TRUE, better than asked.** /api/v2/ramps exists and
  returned 200 live. CORS isn't just configurable — it's already wide open:
  `AllowOrigins: ["*"]` on all routes (routes.go:23-27). A live board on
  donwb.com would work today with a plain fetch().
- **V10 screenshot scenes** — all three exist; see §8.

## 6. In progress / near future

- Web multi-camera switcher: SHIPPED 2026-08-16 (b3c9817). The board renders cam
  chips off the /api/v2/cameras roster — `updateCamTabs()` builds a `.cam-tab`
  button per camera into the `#cam-tabs` container, hidden until the roster has a
  second cam and disabled for cams with no stream_url (web/js/views/board.js:609-627,
  container at :131), and a click handler sets `selectedCameraId` on the store
  (web/js/views/board.js:222-225); the roster is fetched in web/js/api.js:33,52.
  Verified live: beach.donwb.com serves the same board.js with `updateCamTabs`, and
  /api/v2/cameras returns the roster with cams.donwb.com stream URLs. Multi-cam is
  safe to claim on ALL platforms — web, iOS, and tvOS.
- No feature flags, WIP branches with commits, or TODO/FIXME markers found in
  api/, web/, or trmnl/ (grep clean; only branch is an empty worktree).
- Working copy note: only `.claude/` local config was dirty at intake time —
  everything cited above is committed on main (HEAD 23d5ab2, 2026-08-12).

## 7. Surprises

- **The tide curve on the e-ink display is drawn by the server.** The Go API
  renders the tide chart as Catmull-Rom-smoothed cubic Bézier SVG path
  strings and ships them as JSON, so the TRMNL's Liquid template stays
  near logic-free (api/internal/handlers/trmnl.go:309-311,55-62).
- **The beach cams are kept alive by a Mac at home.** YouTube blocks yt-dlp
  from datacenter IPs, so a cron on a residential-IP home machine resolves
  every camera's HLS URL and pushes it to the API — the cloud literally can't
  refresh its own video streams (scripts/update-stream-url.sh:1-6,
  main.go:131-135).
- **The county once renumbered every ramp under the app's feet.** Volusia's
  GIS renumbered its OBJECTIDs, stranding stale statuses; fixed with a
  migration and upsert change (commit ff3a353, migrations/006).
- **The Tidbyt is dead but its API isn't.** The device was powered off in
  August 2026, yet the v1 endpoints it required (/rampstatus, /tides, /ramps)
  are still served for compatibility (routes.go:52-56, CLAUDE.md).
- **The tvOS camera switcher is a map, not a menu.** Cameras are pins placed
  along a stylized stretch of coastline ("coastline rail"), positioned
  geographically south-to-north (BeachRampTV/ContentView.swift:708-716).
- **It's a rebuild with a paper trail.** REQUIREMENTS.md documents the
  ground-up rewrite of a decade-old system: a Python-cron-plus-two-iOS-apps
  monorepo unified into one Go binary and one SwiftUI codebase
  (REQUIREMENTS.md §2).

## 8. Assets located

Generated exports (this session, untracked, repo root `intake-assets/`):

- `intake-assets/icon-124.png` — 124×124 app icon, from
  apple/BeachRamp/generated_icons/AppIcon-1024.png.
- `intake-assets/scene-ramps-600.png` — 600px-wide iPhone ramps list
  (filters, open/limited/closed counts), from slides/screenshots/"Simulator
  Screenshot - iPhone 17 Pro Max - 2026-03-11 at 08.45.07.png".
- `intake-assets/scene-tides-600.png` — 600px-wide iPhone tide chart +
  weather forecast + water temp, from the 08.45.17 simulator screenshot.
- `intake-assets/scene-cam-600.png` — 600px-wide desktop dashboard including
  the live webcam panel, from slides/screenshots/"desktop web.png".
- `intake-assets/hero-460.png` — 460px-wide desktop dashboard for the card.

Other masters available: slides/screenshots/ also holds Apple TV, Apple
Watch, TRMNL, iPad (M5 Pro 11") and mobile-web screenshots at full
resolution; SVG icon master at web/icons/icon.svg; TV/watch icon masters in
apple/BeachRamp/generated_icons/. Screenshots are from March 2026 — the
iOS/tvOS camera switcher shipped after them, so a fresh cam-scene capture
would show the newer multi-camera UI.
