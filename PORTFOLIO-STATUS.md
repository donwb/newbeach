---
schema: 2
app: Volusia Beach Info
repo: /Users/donwb/dev/newbeach
one_liner: Real-time Volusia County beach access ramp status, tides, weather, and live beach cams across web, Apple platforms, and TRMNL e-ink displays.
lifecycle: live+iterating
last_verified: 2026-09-29
summary: All platforms live; 1.4 (36) on TestFlight for iOS + tvOS (Ask, spoken: mic + Siri, verified on device), not yet submitted; "Ask" live on the API and website since 9/28; NSB cam dark upstream since 9/19 (county-side)
versions:
  ios: 1.2 (28) live since 2026-09-02
  ipados: 1.2 (28) live since 2026-09-02
  tvos: 1.3 (30) live since 2026-09-17
  testflight: 1.4 (36) testflight since 2026-09-29
  watchos: 1.4 (36) dev
  web: live
review: none
next_dates: []
blockers:
  - NSB cam offline upstream since 2026-09-19 (county encoder, YouTube LIVE_STREAM_OFFLINE); restreamer self-recovers when the county restarts it [external]
dispatches:
  - 2026-09-26-newbeach-status-schema-2.md: done 2026-09-26
---

## Top open items
0. **1.4 (36) is on TestFlight** (iOS + tvOS, uploaded 2026-09-29, tag flight/build-36). Siri verified by Don on 35: the two parameterless shortcuts answered and a spoken follow-up kept context. 36 adds the city shortcut ("Is the beach open in ⟨city⟩ with Beach Info" — needed the explicit registration call), phrases that avoid a leading "Ask" (newer iOS treats "Ask ⟨name⟩" as a chat hand-off and says "can't find the app"), and alternative spoken app names. Check the Shortcuts app shows three entries, then submit for review when ready — supersedes 35.
1. **Submit 1.4 (36) for review** when Don wants it public. It carries Ask (typed and spoken), the tvOS idle-reset fix (8127e53), the tide-wave time captions, and the tomorrow overlay. Update reviews on this record have cleared in under a day. Authority: `apple/BeachRamp/Config/Version.xcconfig`, tag `flight/build-36`.
2. **tvOS gallery truncation (open since the 9/16 submission).** In the lead Apple TV shot `design/app-store-screenshots/appletv/01-board.png`, the surf headline is cut off at "…but ramps are tide-closed…" right above "Every ramp open", so it reads as a contradiction. f95b1c7 (9/26) removed that clause from the server's surf line, so the next reshoot (`apple/scripts/screenshots.sh tv`) should come out clean. Check the headline fits before the next tvOS submission. Authority: `docs/APP-STORE-LISTING.md`, STATUS-LOG 2026-09-19.
3. **Physical Siri-remote pass on the Apple TV.** Simulator XCUIRemote tests cover navigation, but a pass with the real remote is still wanted.
4. **County outreach is on hold.** It was sent 2026-08-17. One county-network reader opened it and nobody replied. Don pivoted (8/26) to a portfolio-level messaging campaign run from the hub. The beach-traffic-check skill still flags any new county visitor.
5. **Long-standing backlog:** populate `ramp_metadata` values (optional now that thresholds are learned; a curated `closure_height_ft` overrides the model). Also: the historical analytics dashboard (REQUIREMENTS.md §16.1), TRMNL consumption of the outlook, the APNs Live Activity sender, and stale `slides/screenshots/` (INTAKE §8).

## Blockers & risks
- **NSB cam:** YouTube reports 550p9smwjPM as LIVE_STREAM_OFFLINE on every player client, but the video is not private and has not been replaced, so no migration is needed. Switch to the Ormond playbook (new ID → migration → deploy) only if it goes private or a replacement broadcast appears. Still offline as of 2026-09-26 (roster `online: false`, relay 404). Web already skips offline cams on first load (eb23fc4).
- **Cams depend on the home Mac Studio** (residential IP restreaming to the cams.donwb.com relay), which is a single point of failure. It has had sleep outages. Runbook: `docs/CAM-RELAY.md`.
- **The county rotates YouTube broadcast IDs without notice.** Ormond Beach has rotated twice: fixed by migration 013 and back since 2026-09-16. Expect it to happen again.
- **County GIS is an unstable upstream.** It renumbered every OBJECTID once (ff3a353 + migration 006), and that could recur.
- **Agents can't yet flight without Don.** CLAUDE.md allows `make flight` when Don or a dispatch asks, but auto mode blocked an agent's run on 9/25, so Don ran builds 31 and 33 himself.
- **The bundle ID is permanently frozen at `com.donwb.BeachRampTV`** for every platform. This was accepted deliberately and users never see it.

## Recently shipped
- 2026-09-29: Ask can be spoken: server quick path (no model for the common questions) + `spoken` replies; iOS mic + Siri intents; tvOS dictation hint; web mic. Server + web live; native in source until the next flight.
- 2026-09-29: Web weekend grid fits the seven-day outlook on one row (one column per day sent, b0e85b6). Web only.
- 2026-09-27: **"Ask" — a chat over the prediction engine, on iOS and tvOS.** `POST /api/v2/chat` (`api/internal/chat`) gives a Claude model three deterministic tools (resolve a ramp name, one ramp at one future instant, the weekend outlook) and it relays the engine's copy verbatim; a copy guard backstops the hedging rules; `sources` are server-built facts for the client card. New `predict.Service.OutlookAt` replays the engine at a target instant, keeping the surge anomaly (a future clock silently dropped it) and the target day's schedule. Locked behind a dedicated `CHAT_API_KEY`; route absent without `ANTHROPIC_API_KEY`. Apple: shared `ChatSession` + Keychain store; iOS chat sheet from the board and ramp detail; tvOS `TVSurface.chat` with suggested questions + TextField from a header "Ask ›". Tests: Go (at, resolver, tools, runner via fake API, guard, handler auth), Swift package (decoding, suggestions, session), one tvOS UI test. Not live yet — see open item 0.
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
- apple/BeachRamp/Config/Version.xcconfig: the single source of truth for version/build.
- .do/app.yaml: production deployment spec (DigitalOcean App Platform).
