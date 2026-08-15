---
app: Beach Ramp Status
repo: /Users/donwb/dev/newbeach
one_liner: Real-time Volusia County beach access ramp status, tides, weather, and live beach cams across web, Apple platforms, and TRMNL e-ink displays.
version: Apple targets 1.0 (build 16), single source of truth apple/BeachRamp/Config/Version.xcconfig; API/web unversioned — continuous deploy from main, no git tags
lifecycle: live+iterating
platforms: web (PWA) / iOS / iPadOS / watchOS / tvOS / TRMNL e-ink (OG + X)
distribution: |
  Web+API: live at https://beach.donwb.com (verified 2026-08-12, INTAKE dossier).
  Apple apps: `make flight` (apple/scripts/flight.sh) archives iOS + tvOS and uploads both to TestFlight in one command. Consolidated onto the "Beach Ramp Status" record (Apple ID 6761724123, bundle ID com.donwb.BeachRampTV for BOTH platforms); build 1.0 (16) uploaded 2026-08-15. The stale "Beach Ramp iOS App" record still needs deleting.
  TRMNL: two private plugin templates in trmnl/, active devices.
app_review_state: |
  iOS: Prepare for Submission, never submitted. Build 1.0 (16) uploaded to TestFlight 2026-08-15 — first iOS build ever to reach the record. Old "Beach Ramp iOS App" record still to be deleted.
  tvOS: Prepare for Submission, never submitted. Record "Beach Ramp Status" (Apple ID 6761724123) is the keeper; its bundle ID is frozen at com.donwb.BeachRampTV by upload history reaching build 15. Build 1.0 (16) uploaded 2026-08-15 alongside iOS.
  watchOS: out of scope for 1.0 — target builds but is excluded from the iOS archive.
mission_dates: |
  none found — no deadlines in REQUIREMENTS.md, README, or intake dossier
last_verified: 2026-08-15 (Apple record cleanup + first dual-platform flight as 1.0 (16) to the one com.donwb.BeachRampTV record; repo repointed to beach.donwb.com and verified against live endpoints with both apps rebuilt and run in simulator; design handoff boards committed. Remaining: delete the stale "Beach Ramp iOS App" ASC record, update TRMNL plugin polling URLs, restart the cam restreamer.)
---

## Top open items
1. Carry the 2026-08 design language to iPadOS → iPhone (web shipped 2026-08-15; tvOS
   named the tokens). Includes migrating iOS AppTheme + WatchTheme to the BeachStatus
   StatusColors (coastal retune 2026-08-14: #29C97A/#E8A23C/#C64B38) and retiring the
   old statusOpen/#10B981 family. Handoff specs:
   "August design_handoff_tvos_board/README.md", design-review/design_handoff_web/.
1b. Web detail-screen facts row deferred: per-ramp metadata (closure heights, address,
   driving hours, nearest-cam distance) doesn't exist anywhere yet — needs a
   ramp_metadata table + admin endpoints; the dashed closure line on the detail tide
   chart is built (renderTideChartSVG closureFt) and dormant until then.
1c. Predictive closure features (Don, 2026-08-15: "def want to come back to that" —
   after the redesign work finishes). Reopen prediction already ships: when a ramp
   closes on the rising tide, the estimate is the falling curve's return to the
   closure-time height (web/js/verdict.js reopenFromClosureHeight). Next steps:
   (a) per-ramp closure heights in ramp_metadata unlock predicting closures BEFORE
   they happen ("Expect full closure near high tide 11:35 AM") plus the dashed
   threshold line in 1b; (b) calibrate those heights from ramp_status_history —
   each real closure pairs a status change with a computable tide height (the
   2026-08-15 10:16 AM all-five closure is a clean first data point); (c) carry the
   same prediction to the Apple targets via BeachStatus VerdictBuilder.
2. One physical-remote pass on the Apple TV — remote navigation (focus order, Recent
   changes button, Menu open/close, overlay focus restore) is now covered by
   BeachRampTVUITests via XCUIRemote in the simulator; a real Siri-remote sanity pass
   is still wanted before calling it done.
3. Web multi-camera switcher — backend roster (5 cams, /api/v2/cameras) and iOS/tvOS
   switchers shipped; website still plays the single default stream. INTAKE §6.
4. Finish domain move to beach.donwb.com — repo side done 2026-08-15 (commit c5eb5b9):
   Apple apps, CI health check, cam restreamer, and TRMNL template docs all repointed,
   verified against live endpoints. Two things remain OUTSIDE the repo: (a) the TRMNL
   polling URLs live in the TRMNL plugin settings, not trmnl/*.html, so both devices still
   fetch the old hostname until Don edits the plugin config; (b) scripts/cam-restreamer.sh
   reads API_BASE from ~/.cam-restreamer.env first, so the running launchd job needs an env
   check + restart. Also: TestFlight build 16 predates the change and still ships the old
   hostname — needs a re-flight.
5. Consolidate the App Store Connect records — repo side done and both platforms flighted
   as 1.0 (16) to the one com.donwb.BeachRampTV record (Apple ID 6761724123). Remaining:
   delete the stale "Beach Ramp iOS App" record in ASC, then the three orphaned App IDs
   (com.donwb.BeachRamp, .BeachRampiOS, and its watchkitapp) will finally delete — they
   refuse while that record still holds them. Cleanup only; nothing is blocked on it.
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
- Neither Apple app has ever been submitted — no "live on iOS/tvOS" claim is available yet.
- The tvOS record's bundle ID is frozen at com.donwb.BeachRampTV, so that identifier is
  permanent for every platform including iOS and watch. Confirmed 2026-08-15 by the upload
  itself: ASC rejected build 2 with "bundle version must be higher than the previously
  uploaded version: 15", proving real history behind the freeze. Accepted deliberately —
  the alternative was deleting and recreating both records, risking the reserved name
  "Beach Ramp Status" to fix a purely cosmetic identifier that users never see.
- Waiting on Don personally: home-cron host maintenance and any App Store Connect actions.

## Recently shipped
- 2026-08-15 (latest): Apple release plumbing — unified iOS+tvOS on one App Store Connect
  record and one bundle ID (com.donwb.BeachRampTV), Config/Version.xcconfig as the single
  source of truth for version/build/display name/export-compliance, deployment floors
  corrected from Xcode's 26.2/26.5 defaults to iOS 18/tvOS 18/watchOS 11, committed shared
  schemes, watchOS excluded from the 1.0 archive, and `make flight` (apple/scripts/flight.sh,
  ported from bkmks) archiving + uploading both platforms. First dual flight: 1.0 (16).
  Also repointed everything at beach.donwb.com and committed the previously untracked design
  handoff boards. Commits b4b0a06, b213c0c, 0f1d248, c5eb5b9, 91cb27a.
- 2026-08-15 (later): Height-based reopen prediction — a rising-tide closure's reopen
  estimate is now the falling curve's return to the closure-time tide height
  (bisected on the cosine curve; next-low+90m stays as the falling-side fallback),
  verified live against the real 10:16 AM all-five NSB closure (predicted 12:56 PM
  vs the old heuristic's 7:19 PM). Plus three post-deploy fixes: zero-time poll
  stamp read as a billion-minute outage, hls.js preferred over Chromium's "maybe"
  native-HLS probe, [hidden] beaten by display:flex on the cam-offline overlay.
- 2026-08-15: Web redesign shipped (from design-review/design_handoff_web/): verdict
  band, status carried by card fields, sun-following ground (16 tvOS sky phases, JS
  ports of SolarCalculator/SkyPalette/VerdictBuilder/TideCurve with 46 Node smoke
  checks), new /ramp/:id detail screen (status band, midnight-to-midnight intervals
  band, per-ramp 48h feed), /tide /water /wind stat routes, SVG tide chart, ES-module
  rewrite of app.js, Tailwind Play CDN + dark-mode toggle removed, self-hosted Archivo,
  sw v3 with navigation fallback. API: /api/v2/ramps/:id/intervals + Echo HTML5 SPA
  fallback (migration 007 index). Facts row + closure line deferred (no metadata yet).
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
