---
app: Beach Ramp Status
repo: /Users/donwb/dev/newbeach
one_liner: Real-time Volusia County beach access ramp status, tides, weather, and live beach cams across web, Apple platforms, and TRMNL e-ink displays.
version: Apple targets 1.0 (build 1) (apple/BeachRamp/BeachRamp.xcodeproj); API/web unversioned — continuous deploy from main, no git tags
lifecycle: live+iterating
platforms: web (PWA) / iOS / iPadOS / watchOS / tvOS / TRMNL e-ink (OG + X)
distribution: |
  Web+API: live at https://beach.donwb.com (verified 2026-08-12, INTAKE dossier).
  Apple apps: build-from-Xcode only as far as this repo proves — no fastlane/store metadata; store presence UNVERIFIED — App Store Connect.
  TRMNL: two private plugin templates in trmnl/, active devices.
app_review_state: |
  iOS (+ watch companion): UNVERIFIED — no submission evidence in repo; check App Store Connect
  tvOS: UNVERIFIED — no submission evidence in repo; check App Store Connect
mission_dates: |
  none found — no deadlines in REQUIREMENTS.md, README, or intake dossier
last_verified: 2026-08-14 (evening: cam-relay droplet built, awaiting cutover)
---

## Top open items
1. Web multi-camera switcher — backend roster (5 cams, /api/v2/cameras) and iOS/tvOS
   switchers shipped; website still plays the single default stream. INTAKE §6.
2. Finish domain move to beach.donwb.com — Apple apps, TRMNL plugins, CI, and the
   camera-refresh cron are still pinned to the DigitalOcean hostname. CLAUDE.md; commit 4e4cc13.
3. Establish/verify App Store presence — bundle IDs exist but nothing proves a listing;
   all Apple distribution state is unverified. INTAKE frontmatter.
4. Historical analytics dashboard — ramp_status_history has been collecting since March,
   but the trends UI (web + iOS) was in-scope and never built. REQUIREMENTS.md §16.1.
5. Refresh marketing screenshots — slides/screenshots/ are from March 2026, predating the
   multi-camera switcher. INTAKE §8.
6. Site-copy fixes from the claim audit — "Beville" ramp doesn't exist in the live feed;
   "six screens" is now seven. INTAKE §5 (V3, V8).

## Blockers & risks
- Beach cams broke in Aug 2026: YouTube IP-locked its HLS URLs, so the resolve-at-home
  URL-push model shows black video on every platform. Fix is built (2026-08-14): a
  MediaMTX relay droplet + home restreamer (scripts/cam-restreamer.sh); NOT yet live —
  Don must install the launchd job on the Mac Studio and flip roster URLs (admin key).
- Beach cams still depend on a home machine (residential IP) — now as the stream
  publisher rather than URL resolver; still a single point of failure.
- Ormond Beach cam offline upstream — its YouTube video ID no longer exists; roster
  youtube_url needs updating when the county restarts the broadcast.
- County GIS is an unstable upstream: Volusia renumbered every OBJECTID once already
  (fixed in ff3a353 + migration 006); could recur.
- App Store state unknown from the repo — blocks any "live on iOS" claim (INTAKE §5 V6).
- Waiting on Don personally: home-cron host maintenance and any App Store Connect actions.

## Recently shipped
(all 2026-08-12)
- Fixed stale ramp statuses caused by the county GIS OBJECTID renumbering (migration 006).
- Ingestion health now surfaced at /api/v2/health (starting/ok/degraded after 5 missed polls).
- Domain move prepped: beach.donwb.com is primary, donwb.com aliased; Tidbyt retirement
  documented and v1 endpoints downgraded from frozen to stable-by-default.
- .do/app.yaml synced with the live App Platform spec.
Earlier in July: multi-camera switcher (tvOS coastline rail + iPad), rotated YouTube URLs.

## Pointers
- REQUIREMENTS.md — full rebuild spec; §17–18 phase plan and per-phase completion status.
- INTAKE-volusia-beach-ramps.md — evidence-audited dossier (2026-08-12): shipped features,
  site-claim audit, privacy, assets.
- CLAUDE.md — platform conventions, env vars, deploy notes.
- .do/app.yaml — production deployment spec (DigitalOcean App Platform).
