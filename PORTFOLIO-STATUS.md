---
schema: 2
app: Volusia Beach Info
repo: /Users/donwb/dev/newbeach
one_liner: Real-time Volusia County beach access ramp status, tides, weather, and live beach cams across web, Apple platforms, and TRMNL e-ink displays.
lifecycle: live+iterating
last_verified: 2026-10-08
summary: All platforms live; 1.4 (44) on TestFlight for iOS + tvOS (Ask with voice, widget push, watch app + widget back, dark-cam auto-recovery), What's New drafted, not yet submitted; Ormond-by-the-Sea cam flapping
versions:
  ios: 1.2 (28) live since 2026-09-02
  ipados: 1.2 (28) live since 2026-09-02
  tvos: 1.3 (30) live since 2026-09-17
  testflight: 1.4 (44) testflight since 2026-10-08
  watchos: 1.4 (44) testflight since 2026-10-08, embedded in the iOS build with its Smart Stack widget
  web: live
review: none
next_dates: []
blockers:
  - Ormond-by-the-Sea cam flapping online/offline every ~30 s (relay hook, seen 2026-10-01 23:08Z onward); viewers see it as offline [restreamer/relay]
dispatches:
  - 2026-09-26-newbeach-status-schema-2.md: done 2026-09-26
---

## Top open items
0. **Check the watch app and the cam fix on 1.4 (44).** The watch app and its Smart Stack widget are back in the iOS archive (confirmed in `Watch/`); confirm it installs from the iPhone Watch app. On the Apple TV, a cam that goes dark should now come back on its own within ~10 s of the feed returning, without switching cams.
1. **Submit 1.4 (44) for review** when Don wants it public (iOS + tvOS, uploaded 2026-10-08, tag `flight/build-44`). It carries the watch app + widget, the dark-cam auto-recovery, Ask (typed, the mic, four Siri shortcuts, the widget Ask button), widget push + the quarter-hourly refresh plan, the tvOS tide-wave captions and tomorrow overlay, and the tvOS idle-reset fix. What's New for both platforms is drafted in `docs/APP-STORE-LISTING.md` (§1.4). Update reviews on this record have cleared in under a day. Authority: `apple/BeachRamp/Config/Version.xcconfig`.
2. **Watch the first real county flip reach the Home Screen.** Widget push verified on device 10/1 via the admin trigger (4 sent, 0 failed); the live trace is `ramp status changed` → `widget push` in `doctl apps logs`. Then the day-to-day question: does Siri stay a coin flip while the widget mic and in-app mic hold up?
3. **Ormond-by-the-Sea cam is flapping** (see blockers). Check the restreamer job on the Studio (`make restreamer-status`) and the relay's health hook before assuming the county side.
4. **tvOS gallery truncation (open since the 9/16 submission).** In the lead Apple TV shot `design/app-store-screenshots/appletv/01-board.png`, the surf headline is cut off right above "Every ramp open". f95b1c7 (9/26) removed that clause from the server's surf line, so the next reshoot (`apple/scripts/screenshots.sh tv`, which now also captures `04-ask.png`) should come out clean. Reshoot before the 1.4 tvOS submission. Authority: `docs/APP-STORE-LISTING.md`.
5. **Physical Siri-remote pass on the Apple TV.** Simulator XCUIRemote tests cover navigation, but a pass with the real remote is still wanted — the Ask surface's text field and dictation hint in particular.
6. **County outreach is on hold.** Sent 2026-08-17; one county-network reader opened it and nobody replied. Don pivoted (8/26) to a portfolio-level messaging campaign run from the hub. The beach-traffic-check skill still flags any new county visitor.
7. **Long-standing backlog:** populate `ramp_metadata` values (optional now that thresholds are learned; a curated `closure_height_ft` overrides the model); the historical analytics dashboard (REQUIREMENTS.md §16.1); TRMNL consumption of the outlook; the Live Activity sender (the APNs client now exists in `api/internal/widgetpush` — what's left is the Live Activity push type, token registration, and the activity UI); stale `slides/screenshots/` (INTAKE §8).

## Blockers & risks
- **Ormond-by-the-Sea cam flaps.** The relay health hook reports it online then offline every ~30 s (observed 2026-10-01 23:08Z → 2026-10-02 01:46Z, dozens of flips); the roster shows it `online: false`. NSB, Ponce Inlet, Dunlawton, Ormond Beach are steady. Likely the restreamer's yt-dlp stream for that camera cutting out and restarting; runbook `docs/CAM-RELAY.md`.
- **NSB cam came back 2026-10-01** after being dark upstream since 9/19 (county encoder). Nothing was migrated; the restreamer self-recovered as designed. Keep the Ormond playbook (new ID → migration → deploy) for the day a broadcast goes private or is replaced.
- **Cams depend on the home Mac Studio** (residential IP restreaming to the cams.donwb.com relay), which is a single point of failure. It has had sleep outages. Runbook: `docs/CAM-RELAY.md`.
- **The county rotates YouTube broadcast IDs without notice.** Ormond Beach has rotated twice: fixed by migration 013 and back since 2026-09-16. Expect it to happen again.
- **County GIS is an unstable upstream.** It renumbered every OBJECTID once (ff3a353 + migration 006), and that could recur.
- **Ask spends money per question** (`claude-opus-5` typed, `claude-sonnet-5` spoken; the common shapes cost nothing via the quick path). The only gate is the chat key, which only Don's devices hold. `chat.done` logs usage per request.
- **The bundle ID is permanently frozen at `com.donwb.BeachRampTV`** for every platform. This was accepted deliberately and users never see it.

## Recently shipped
- 2026-10-08: 1.4 (44) on TestFlight for iOS + tvOS. The watch app and its four-ramp Smart Stack widget ship again (inside the iOS build). Cams that go dark now recover on their own on Apple TV and iOS (aac127a, 879b322), and the restreamer no longer hangs a camera when a pipeline breaks.
- 2026-10-01: Widget push (iOS 26) live end to end — ingester flips → coalesced APNs `content-changed` pushes → Home Screen widgets reload in seconds. Verified on device with 1.4 (42): 4 sent, 0 failed.
- 2026-09-30: Widget refresh cadence follows the driving day (`WidgetRefreshPlan`, 945571c); flighted as 1.4 (41).
- 2026-09-29: The website now points people at the apps: Safari Smart App Banner, a "Get the app ›" link in the top bar, and an iPhone/iPad + Apple TV tile section between Ask and the cam (0dc501d). Web only.
- 2026-09-29: Voice for Ask, end to end: server quick path (common questions from engine copy, no model) + spoken replies; iOS mic in the Ask bar; four Siri shortcuts (free-form, city, ramp-by-name, best day) with clarifying exchanges kept inside the shortcut; widget Ask mic button as the reliable one-tap path. Flighted through 1.4 (40). Jev spike punted (code stays off).
- 2026-09-29: **Jev spike (TypeSafe System One) in Ask, behind `JEV_MODE`.** A second quick-path router (one calibrated Choice call for intent/city/ramp/day/clock parts, code assembles the instant) and the copy guard's promise rule as a Noul; ramp questions can go quick for the first time. Off in prod (no key yet); default `shadow` logs Jev beside the pattern router. Evals: tuning set 49/64 quick vs 19/64 for the regexes with no wrong plan; held-out 16/25 vs 2/25; guard Noul 10/10 vs regex 6/10; ~180 ms, $0.0001/question. Write-up `docs/JEV-SPIKE.md`. Server-side only, not switched on.
- 2026-09-29: Web weekend grid fits the seven-day outlook on one row (one column per day sent, b0e85b6). Web only.
- 2026-09-27: **"Ask" — a chat over the prediction engine, on iOS and tvOS.** `POST /api/v2/chat` (`api/internal/chat`) gives a Claude model three deterministic tools (resolve a ramp name, one ramp at one future instant, the weekend outlook) and it relays the engine's copy verbatim; a copy guard backstops the hedging rules; `sources` are server-built facts for the client card. New `predict.Service.OutlookAt` replays the engine at a target instant, keeping the surge anomaly (a future clock silently dropped it) and the target day's schedule. Locked behind a dedicated `CHAT_API_KEY`; route absent without `ANTHROPIC_API_KEY`. Apple: shared `ChatSession` + Keychain store; iOS chat sheet from the board and ramp detail; tvOS `TVSurface.chat` with suggested questions + TextField from a header "Ask ›". Live on the API and website since 9/28; native since build 34.
- 2026-09-26: Prediction handles morning highs. Before the open, a high tide around it now reads "Opens around 8am, but the ~9am high tide could keep it closed until ~11am"; walk-forward catches 64% of held-at-open mornings (0% before). Closures posted at the open after the high quote peak + 4.5h (error 5.05h → 3.29h). Server-side only.
- 2026-09-26: High-water days: reopen estimates floored at peak + 3.5h when water runs ≥ 0.9 ft over normal ("said open too early" on Sep 24–26: 50% → 25%), and the evening window stretches 30 min per foot. Server-side only.
- 2026-09-26: Surf report is surf-only (f95b1c7). The ramp/tide clause that truncated the tvOS Surf Now row is gone. Server-side only.
- 2026-09-26: 1.4 (33) is on TestFlight for iOS + tvOS: the tvOS tide wave captions each high/low with its time and overlays tomorrow's curve as a dashed line. `/api/v2/tides/chart` gains `tomorrow_high_low`.
- 2026-09-26: The outlook now warns ahead of evening high tides, capped at "possible". Walk-forward 9am misses 157 → 38.
- 2026-09-25: The water-level anomaly (params v7) went into prediction. Misses 111 → 21, and "likely" precision 0.59 → 0.74.
- 2026-09-25: 1.4 (31) uploaded to TestFlight. It was the first flight through the shared `~/dev/flight` tool on an ASC API key, which ended the Apple ID re-auth blocker.
- 2026-09-19: tvOS idle no longer flips the cam back to New Smyrna (8127e53). The web board no longer opens on an offline camera (eb23fc4, sw v28).
- 2026-09-17: tvOS 1.3 (30) released on the App Store. Every Apple platform is now public on the parity design.
- 2026-09-16: The repo moved to direct-to-main commits (no PRs), and merged branches were pruned.
- 2026-09-13: The Ormond Beach cam is back (migration 013, new ID p1s7EdZgGvU). Restreamer log rotation deployed (logs had reached 6.7 GB).

## Pointers
- STATUS-LOG.md: all history, including the full schema-1 file moved verbatim by date.
- REQUIREMENTS.md: the full rebuild spec, including the §17–18 phase plan.
- INTAKE-volusia-beach-ramps.md: evidence-audited dossier (2026-08-12).
- CLAUDE.md: platform conventions, prediction rules, env vars, release and deploy notes.
- docs/APP-STORE-LISTING.md: ASC metadata as submitted, plus What's New drafts.
- docs/CAM-RELAY.md, docs/WAVE-DATA.md: cam relay and wave-data pipelines and runbooks.
- docs/ASK-SETUP.md: Ask keys, switch-on, Siri phrases, smoke tests. docs/WIDGET-PUSH.md: APNs key, widget push flow, admin trigger. docs/JEV-SPIKE.md: the Jev evaluation and verdict.
- apple/BeachRamp/Config/Version.xcconfig: the single source of truth for version/build.
- .do/app.yaml: production deployment spec (DigitalOcean App Platform).
