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
last_verified: 2026-08-14 (tvOS focus-order fix + coastal status colors shipped, remote nav covered by UI tests; cam relay live)
---

## Top open items
1. Carry the 2026-08 design language to iPadOS → iPhone → web (agreed sequence; tvOS
   shipped first and named the tokens). Includes migrating iOS AppTheme + WatchTheme to
   the BeachStatus StatusColors (coastal retune 2026-08-14: #29C97A/#E8A23C/#C64B38) and
   retiring the old statusOpen/#10B981 family. Handoff spec:
   "August design_handoff_tvos_board/README.md".
2. One physical-remote pass on the Apple TV — remote navigation (focus order, Recent
   changes button, Menu open/close, overlay focus restore) is now covered by
   BeachRampTVUITests via XCUIRemote in the simulator; a real Siri-remote sanity pass
   is still wanted before calling it done.
3. Web multi-camera switcher — backend roster (5 cams, /api/v2/cameras) and iOS/tvOS
   switchers shipped; website still plays the single default stream. INTAKE §6.
4. Finish domain move to beach.donwb.com — Apple apps, TRMNL plugins, CI, and the
   camera-refresh cron are still pinned to the DigitalOcean hostname. CLAUDE.md; commit 4e4cc13.
5. Establish/verify App Store presence — bundle IDs exist but nothing proves a listing;
   all Apple distribution state is unverified. INTAKE frontmatter.
6. Historical analytics dashboard — ramp_status_history has been collecting since March,
   but the trends UI (web + iOS) was in-scope and never built. REQUIREMENTS.md §16.1.
7. Refresh marketing screenshots — slides/screenshots/ are from March 2026, predating the
   multi-camera switcher and the tvOS redesign. INTAKE §8.
8. Site-copy fixes from the claim audit — "Beville" ramp doesn't exist in the live feed;
   "six screens" is now seven. INTAKE §5 (V3, V8).

## Blockers & risks
- Beach cams still depend on a home machine (residential IP): YouTube IP-locked its
  HLS URLs in Aug 2026, killing the old URL-push cron; since 2026-08-14 the Mac Studio
  restreams all cams (scripts/cam-restreamer.sh, launchd) to a MediaMTX relay droplet
  (beach-cam-relay, 68.183.149.152, $6/mo) serving stable HLS at cams.donwb.com —
  live and verified on all 4 online cams; the Studio remains a single point of failure.
  Same night, YouTube's bot-check began blocking anonymous yt-dlp resolves from the
  home IP (nsb went dark ~1h); fixed with the bgutil PO-token provider on the Studio
  (com.donwb.bgutil-pot launchd job, no Google account) + exponential backoff for
  failed resolves (commits 5ac4920/f83314a/40e5d16, runbook in docs/CAM-RELAY.md);
  all 4 online cams verified re-resolving and publishing post-deploy.
- Ormond Beach cam offline upstream — its YouTube video ID no longer exists; roster
  youtube_url needs updating when the county restarts the broadcast.
- County GIS is an unstable upstream: Volusia renumbered every OBJECTID once already
  (fixed in ff3a353 + migration 006); could recur.
- App Store state unknown from the repo — blocks any "live on iOS" claim (INTAKE §5 V6).
- Waiting on Don personally: home-cron host maintenance and any App Store Connect actions.

## Recently shipped
- 2026-08-14 (evening): tvOS remote-navigation fix — cam banner swapped from AVKit
  VideoPlayer to a bare AVPlayerLayer (it was a giant focusable that swallowed
  directional + Menu presses), row focus sections (top bar / verdict band / rail),
  "Recent changes" promoted from static label to focusable button, and overlays now
  return focus to the tile that opened them. Covered by 4 XCUIRemote UI tests.
- 2026-08-14 (evening): status colors retuned to the coastal family (open #29C97A,
  limited #E8A23C, closed #C64B38) and tvOS board surfaces now mute them toward the
  night sky after sunset — closed tiles no longer glow fire-red all night.
- 2026-08-14: tvOS ambient-board redesign (from "August design_handoff_tvos_board/"):
  verdict band answering "can I get on?" in one line, status carried by solid tile
  fields instead of tinted text, 16 sun phases (three twilights each side), designed
  stale/cam-offline states, three focusable stat tiles opening tide/water-air/wind
  detail overlays, Recent Activity behind Menu. Server: /api/v2/ramps now carries
  status_since; tide extremes carry heights. Shared: VerdictBuilder/SinceFormatter/
  TideCurve/StatusColors in BeachStatus with 36 tests. All 12 board states verified
  against the design contact sheets in the tvOS simulator.
- 2026-08-14: Beach-cam relay architecture — diagnosed YouTube's new IP-locked HLS
  enforcement (black players everywhere), built a MediaMTX relay droplet + home
  restreamer, cut all camera URLs over to stable relay HLS. Verified on all platforms'
  fetch path; old update-stream-url.sh cron retired.
(below: 2026-08-12)
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
