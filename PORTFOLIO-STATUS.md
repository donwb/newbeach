---
app: Beach Ramp Status
repo: /Users/donwb/dev/newbeach
one_liner: Real-time Volusia County beach access ramp status, tides, weather, and live beach cams across web, Apple platforms, and TRMNL e-ink displays.
version: Apple targets 1.0 (build 17), single source of truth apple/BeachRamp/Config/Version.xcconfig; API/web unversioned — continuous deploy from main, no git tags
lifecycle: live+iterating
platforms: web (PWA) / iOS / iPadOS / watchOS / tvOS / TRMNL e-ink (OG + X)
distribution: |
  Web+API: live at https://beach.donwb.com (verified 2026-08-12, INTAKE dossier).
  Apple apps: `make flight` (apple/scripts/flight.sh) archives iOS + tvOS and uploads both to TestFlight in one command. Consolidated onto the "Beach Ramp Status" record (Apple ID 6761724123, bundle ID com.donwb.BeachRampTV for BOTH platforms); build 1.0 (17) uploaded 2026-08-15 (the full iOS/iPadOS redesign + widgets, on beach.donwb.com).
  TRMNL: two private plugin templates in trmnl/, active devices; polling URLs moved to beach.donwb.com 2026-08-15.
app_review_state: |
  iOS: Prepare for Submission, never submitted. Build 1.0 (17) on TestFlight 2026-08-15 — the redesign build, first with the widget extension.
  tvOS: Prepare for Submission, never submitted. Record "Beach Ramp Status" (Apple ID 6761724123) is the keeper; its bundle ID is frozen at com.donwb.BeachRampTV by upload history reaching build 15. Build 1.0 (17) uploaded 2026-08-15 alongside iOS.
  watchOS: out of scope for 1.0 — target builds but is excluded from the iOS archive.
mission_dates: |
  none found — no deadlines in REQUIREMENTS.md, README, or intake dossier
last_verified: 2026-08-15 (iOS/iPadOS redesign SHIPPED to main: sky-ground boards, ramp detail, landscape cam, widget family, ramp_metadata backend deployed. Flighted as 1.0 (17) same day. Live Activity + watch refresh deferred by decision. ASC consolidation complete; cam restreamer still pending `make deploy-restreamer` on the Studio.)
---

## Top open items
1. DONE 2026-08-15 — iOS/iPadOS redesign shipped to main (commits e6689ce…7ab6210):
   sun-following sky boards on iPhone + iPad, verdict hero, field-carried status,
   ramp detail (push on iPhone, 760×762 panel on iPad), forced-landscape live cam,
   and the widget extension (small/medium/large + Lock Screen accessories, App Group
   snapshot pipeline, per-instance city config). AppTheme/WatchTheme… note: WatchTheme
   still has its own palette (watch deferred). REMAINING from the handoff, by
   decision (Don, 2026-08-15): Live Activity/Dynamic Island (needs an APNs
   ActivityKit push sender — pair with 1c), watch refresh + complications, and
   stat-strip cell push-throughs to tide/water/wind detail screens. Flighted as 1.0 (17)
   the same day.
1a. Populate ramp_metadata values — the table, admin endpoint
   (PUT /api/v2/admin/ramps/:id/metadata, X-Api-Key), and nullable fields on
   /api/v2/ramps are LIVE (migration 008, deployed 2026-08-15) with NSB sort_order
   seeded. Closure heights, addresses, driving hours, and short names are NULL until
   Don curates them; the iOS detail facts, dashed threshold line, forward-looking
   closure line (ClosureProjector), and web facts row all light up as values land.
1c. Predictive closure features (Don, 2026-08-15: "def want to come back to that").
   Client-side projection now ships on iOS: ClosureProjector turns closure_height_ft
   + the tide curve into "Expect full closure near high tide 11:07 PM." / reopen
   lines — blocked only on curated heights (1a). Next steps: (a) calibrate heights
   from ramp_status_history (each real closure pairs a status change with a
   computable tide height; the 2026-08-15 10:16 AM all-five closure is a clean first
   data point); (b) server-side threshold math to feed a future APNs Live Activity
   push sender; (c) carry the projection to web.
2. One physical-remote pass on the Apple TV — remote navigation (focus order, Recent
   changes button, Menu open/close, overlay focus restore) is now covered by
   BeachRampTVUITests via XCUIRemote in the simulator; a real Siri-remote sanity pass
   is still wanted before calling it done.
3. Web multi-camera switcher — backend roster (5 cams, /api/v2/cameras) and iOS/tvOS
   switchers shipped; website still plays the single default stream. INTAKE §6.
4. Finish domain move to beach.donwb.com — repo repointed 2026-08-15 (c5eb5b9) and verified
   against live endpoints; TRMNL plugin polling URLs updated by Don the same day. TWO THINGS
   REMAIN: (a) the cam restreamer on the Studio was still logging fetches from the old
   hostname as of 12:23 — launchd runs a COPY at ~/bin/cam-restreamer.sh, and an API_BASE in
   ~/.cam-restreamer.env overrides the script default, so both need checking; `make
   deploy-restreamer` (a1c1f05) now handles the copy + kickstart and warns about the env
   override. (b) DONE — build 1.0 (17), flighted 2026-08-15, ships beach.donwb.com.
5. DONE 2026-08-15 — App Store Connect records consolidated. Both platforms flight as
   1.0 (16) to the single "Beach Ramp Status" record (Apple ID 6761724123, bundle ID
   com.donwb.BeachRampTV); the stale "Beach Ramp iOS App" record was deleted by Don. Only
   cosmetic leftovers: the orphaned App IDs (com.donwb.BeachRamp, .BeachRampiOS and its
   watchkitapp) may now delete in the portal, having been blocked by that record.
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
- 2026-08-15 (latest): iOS/iPadOS redesign from design-review/design_handoff_ios/ —
  the sixteen-phase SkyPalette moved into BeachStatus (tvOS unchanged) with the
  day/night TokenSet, StatusField colors, GroundModel (dayness/veil/scrim, 30s tick),
  ClosureProjector, App Group BoardSnapshot store, and bundled Archivo (OFL).
  iPhone: sky-hero board with verdict, count-carrying filters, field-status rows,
  12h tide section, stale state, 60s foreground poll; pushed ramp detail (today
  band from /intervals, facts grid, dashed threshold chart, 48h feed, in-place ramp
  flip); forced-landscape live cam with scrims + roster chips. iPad: wide board
  (city tabs, 1.55fr/1fr verdict row, 372pt rail landscape, dissolved-rail
  portrait) + 760×762 detail panel. New BeachRampWidgetsExtension target (first
  embed phase + entitlements in the project) with small/medium/large and Lock
  Screen widgets on the snapshot-first timeline. Backend: ramp_metadata table +
  admin upsert + /api/v2/activity city/ramp/since filters, all additive, deployed
  and verified against web + TRMNL. QA hooks: --sky-minutes, --simulate-stale,
  --force-wide.
- 2026-08-15: Apple release plumbing — unified iOS+tvOS on one App Store Connect
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
