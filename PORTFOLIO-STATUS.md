---
app: Volusia Beach Info
repo: /Users/donwb/dev/newbeach
one_liner: Real-time Volusia County beach access ramp status, tides, weather, and live beach cams across web, Apple platforms, and TRMNL e-ink displays.
version: Apple targets 1.4 (build 32 — iOS ONLY, uploaded 2026-09-25 by an accidental `make flight --only ios` run in this repo (meant for AirStory); same app code as 31, and it proved an API-key-only upload with no Xcode UI. tvOS stays on 31. Prior: build 31 — the tvOS idle-reset fix 8127e53; iOS + tvOS uploaded to TestFlight 2026-09-25 by Don via `make flight`, tag flight/build-31 — the first flight through the shared ~/dev/flight tool on an App Store Connect API key, no Apple ID session involved. Not yet submitted for review. Prior: 1.3 (build 30 — the tvOS tide-wave now-line fix, on TestFlight, tag flight/build-30, flighted by Don ~2026-08-26; Apple TV gallery recaptured 2026-09-09, listing copy drafted, RELEASED on the App Store 2026-09-17 16:33:58Z, verified 2026-09-19 via the iTunes lookup API — tvOS is now public on 1.3; supersedes build 29 which did upload 2026-08-24. PUBLIC App Store: iOS 1.2 (28) live 2026-09-02 01:49Z (the update review cleared in ~10h); tvOS 1.2 (28) live 2026-09-01; iOS 1.0 (18) was live 2026-09-01 for ~10h — see app_review_state. Prior: build 29 — tvOS sunrise/sunset header + verdict tide wave, commit 82e8835, archived 2026-08-23 evening. MARKETING_VERSION bumped 1.2 → 1.3 because ASC closed the 1.2 train on tvOS — tvOS 1.2 (28) APPROVED then released, see app_review_state. Prior: 1.2 (build 28 — the "Volusia Beach Info" rename, flighted 2026-08-23; MARKETING_VERSION bumped 1.1 → 1.2 because ASC closed the 1.1 train on tvOS, see app_review_state. Prior: 1.1 (build 26 — iOS/iPadOS flighted to TestFlight 2026-08-21 14:08 ET, tag flight/build-26: the parity pass + favorites→Pin to widget; tvOS is on 1.1 (25), flighted 08:39 ET, tag flight/build-25, submitted for review. MARKETING_VERSION bumped 1.0 → 1.1 on 2026-08-21 because App Store Connect closed the 1.0 train — see app_review_state), single source of truth apple/BeachRamp/Config/Version.xcconfig; API/web unversioned — continuous deploy from main, no git tags
lifecycle: live+iterating — web/API live at beach.donwb.com; BOTH Apple platforms RELEASED on the App Store (iOS 1.2 build 28 live 2026-09-02, tvOS 1.2 build 28 live 2026-09-01) — every Apple platform is public on the current parity design — iOS/iPadOS 1.2 (28), tvOS 1.3 (30) live 2026-09-17
platforms: web (PWA) / iOS / iPadOS / watchOS / tvOS / TRMNL e-ink (OG + X)
distribution: |
  Web+API: live at https://beach.donwb.com (verified 2026-08-12, INTAKE dossier).
  Apple apps: LIVE ON THE APP STORE as of 2026-09-01 — https://apps.apple.com/us/app/volusia-beach-info/id6761724123 ("Volusia Beach Info", free; verified 2026-09-09 via the iTunes lookup API: version 1.2, currentVersionReleaseDate 2026-09-02T01:49Z; 1.0 first went live 2026-09-01T15:56Z). beach.donwb.com links the listing from the board footer and /support (2026-09-09). `make flight` (apple/scripts/flight.sh) archives iOS + tvOS and uploads both to TestFlight in one command. Consolidated onto the single "Volusia Beach Info" record (Apple ID 6761724123, bundle ID com.donwb.BeachRampTV for BOTH platforms); build 1.0 (17) uploaded 2026-08-15 (the full iOS/iPadOS redesign + widgets, on beach.donwb.com).
  TRMNL: two private plugin templates in trmnl/, active devices; polling URLs moved to beach.donwb.com 2026-08-15.
app_review_state: |
  iOS 1.2 (28) RELEASED 2026-09-02 01:49Z — the update review cleared in roughly ten
  hours (submitted the evening of 9/1). The public iPhone/iPad app is now the parity
  design: "Volusia Beach Info" wordmark, weekend outlook, surf line, Pin to widget,
  redrafted description. Verified from this repo 2026-09-09 via the iTunes lookup API
  (version 1.2). The build-18 wording caution is OVER — the site may pair the store
  link with new-design screenshots.
  tvOS 1.3 (30) RELEASED 2026-09-17 16:33:58Z — APPROVED and LIVE. Don confirmed, and
  verified from this repo 2026-09-19 via the iTunes lookup API (id 6761724123,
  entity=tvSoftware: version 1.3, release date above, serving the What's New drafted in
  docs/APP-STORE-LISTING.md §tvOS 1.3). Submitted 2026-09-16, so the update review
  cleared in about a day — the second data point that update reviews on this record are
  fast (iOS 1.2 took ~10h), against the ~15 days iOS 1.0's initial review cost.
  EVERY APPLE PLATFORM IS NOW CURRENT: iOS/iPadOS 1.2 (28) and tvOS 1.3 (30), both the
  parity design. The App Store is no longer a source of open work on this repo; the next
  submission is whenever new client work earns one, not a backlog item.
  It shipped with the known gallery truncation below, accepted deliberately.
  KNOWN COSMETIC ISSUE, SUBMITTED DELIBERATELY (Don, 2026-09-16): in the lead gallery
  shot 01-board.png the one-row surf headline truncates to "…but ramps are tide-closed…"
  directly above "Every ramp open" and five Open rows, so it reads as a contradiction.
  The sentence is correct and city-scoped per 78e515c — 03-ramp-detail.png shows it in
  full, "…tide-closed right now in Daytona", a different city than the board's NSB — it
  is the tvOS single-row layout limit clipping it. Lifting it needs a client change plus
  a flight, so it could not be fixed for this submission. Options weighed and declined:
  reshoot the board on a day with no closure anywhere (costs a wait on weather), or lead
  the gallery with a different shot (the board is the app's home screen and the better
  first impression). Fix it in a later tvOS build, not by holding a gallery for weather.
  --- history below ---
  RELEASED 2026-09-01: iOS 1.0 (build 18) AND tvOS 1.2 (build 28) are LIVE on the App
  Store — the first public release ever for this record, both platforms. Both versions
  were on auto-release and released on approval; Don confirmed from an ASC screenshot
  2026-09-01, hub verified via the iTunes lookup API ("Volusia Beach Info", version 1.0,
  free, released 2026-09-01 15:56Z), re-verified from this repo the same day.
  What the public iOS build is: build 18 — the pre-parity design, "Beach Ramps" in-app
  wordmark, no weekend outlook, no surf line. That is the cost Don accepted 2026-08-23
  when he left 1.0 in the queue; the listing (name, 8/15 screenshots) matches build 18
  deliberately. The payoff is now claimable: the next iOS submission is an UPDATE
  review — typically much faster than the ~15-day initial review 1.0 just survived.
  iOS 1.2 (28) SUBMITTED 2026-09-01 (Don, in ASC, same day 1.0 released) — the first
  UPDATE review for this record: the parity design, "Volusia Beach Info" wordmark,
  weekend outlook, surf line, Pin to widget. Listing got the redrafted description
  (the live 1.0 copy still said "closure likely" — replaced per the possible-never-
  likely rule), the 1.0→1.2 What's New, and the 8/23 iPhone/iPad screenshot recaptures.
  When it clears: the public iOS app matches the current design, and the site's App
  Store badge can pair with new-design screenshots.
  --- history below ---
  tvOS 1.2 (28) APPROVED — learned 2026-08-23 ~18:58 ET the same way 1.1 and 1.0 were:
  the tvOS upload of 1.2 (29) was REJECTED with "previously approved version [1.2]" /
  "train '1.2' is closed for new build submissions". NOT YET CONFIRMED in ASC by a
  human. That approval is the rename + recaptured store shots going live on TV.
  Consequence acted on: MARKETING_VERSION bumped 1.2 → 1.3, tvOS re-archived as
  1.3 (29) (the sunrise/sunset header + verdict tide wave, commit 82e8835), but the
  UPLOAD IS STILL PENDING — the re-run was permission-blocked in the agent session;
  Don runs: apple/scripts/flight.sh --tv-only --yes --no-bump
  iOS is unaffected: trains are per-platform, iOS 1.2 (28) is still the build to
  submit the moment iOS 1.0 clears review.
  tvOS 1.1 (25) APPROVED — learned 2026-08-23 10:01 ET the same way 1.0 was: the tvOS
  upload of 1.1 (27) was REJECTED with "CFBundleShortVersionString [1.1] must contain a
  higher version than that of the previously approved version [1.1]" and "Invalid
  Pre-Release Train. The train version '1.1' is closed for new build submissions".
  NOT YET CONFIRMED in ASC by a human — Don should verify, and check whether it is
  Ready for Sale or Pending Developer Release. So the video-first tvOS board is
  approved and the store's TV screenshots are finally current.
  Consequence acted on the same hour: MARKETING_VERSION bumped 1.1 → 1.2 (Don's call)
  and BOTH platforms re-flighted under 1.2 to carry the "Volusia Beach Info" rename.
  iOS 1.1 (27) had already uploaded successfully minutes earlier and is now a dead
  build — ignore it in TestFlight.
  iOS has NEVER been approved. CONFIRMED IN ASC by Don 2026-08-23 (screenshot):
  "iOS 1.0 Waiting for Review" / "tvOS 1.1 Ready for Distribution". The 2026-08-21
  inference that "1.0 (18) is approved" was TRUE ONLY FOR tvOS — pre-release trains
  are per-platform, and the rejection that revealed it was a tvOS upload. iOS 1.0 (18)
  has sat in the initial-review queue since 2026-08-18; Apple's first-review queue is
  badly backed up right now. Nothing of this app is public on iOS yet.
  CONSEQUENCE, and it is not small: the ASC iOS version record says 1.0, so it can only
  carry a build whose CFBundleShortVersionString is 1.0 — i.e. build 18. Builds 26, 27,
  and 28 (1.1/1.2) CANNOT attach to the pending 1.0 submission.
  DECIDED 2026-08-23 (Don): LEAVE 1.0 IN THE QUEUE. Every submission while the app has
  never been approved is an *initial* review — the slow kind, already five days deep.
  Getting any version approved converts the next submission into an *update* review,
  which is typically much faster; pulling would discard five days of that tax and re-buy
  it at the same price. Accepted cost: for a window the public iOS app is build 18 —
  pre-parity design, "Beach Ramp Status" wordmark, no weekend outlook, no surf line.
  DO NOT touch the iOS 1.0 submission or its gallery; the 8/15 screenshots already on it
  match build 18. Submit iOS 1.2 (28) the moment 1.0 clears.
  Don notes initial review queues are slow right now (submission volume).
  How we learned 1.0 was approved: 2026-08-21 08:37 ET the tvOS TestFlight upload of 1.0 (25) was
  REJECTED by App Store Connect with "CFBundleShortVersionString [1.0] must contain a
  higher version than that of the previously approved version [1.0]" and "Invalid
  Pre-Release Train. The train version '1.0' is closed for new build submissions" —
  i.e. Apple has approved version 1.0 (build 18). NOT YET CONFIRMED in ASC by a human:
  Don confirmed 2026-08-21: 1.0 (18) is the only thing Apple has approved — the
  design that has since been replaced. NOTE (2026-08-23): that approval was the
  tvOS 1.0 train only; iOS 1.0 is still Waiting for Review. See above. Submitted 1.1 (25) the same morning (above).
  Consequence already acted on: MARKETING_VERSION is now 1.1 and build
  25 went up under 1.1; every future flight is a 1.1 build. The App Store listing still
  shows the build-18 design (pre-video-first) — the TV screenshots trail by four designs
  and a 1.1 submission is how the current app reaches the store.
  History: IN REVIEW as of 2026-08-17 — build 1.0 (18) flighted and submitted (Don), BOTH
  platforms: iOS/iPadOS and tvOS each submitted as their own platform version under
  the one record. First submission ever for this app; the record has never carried a
  released version.
  Listing name submitted as "Volusia Beach Info" (renamed off the reserved "Beach Ramp
  Status" the same day; "Volusia Beaches" was rejected as a candidate because it is the
  county's own Flutter app). Full submitted metadata — subtitle, keywords, descriptions,
  App Privacy answers, review notes — is checked in at docs/APP-STORE-LISTING.md.
  Required URLs went live the same day and are verified serving:
  https://beach.donwb.com/privacy and /support.
  Record: Apple ID 6761724123, bundle ID com.donwb.BeachRampTV, frozen by upload history
  reaching build 15; one record carries both iOS and tvOS.
  watchOS: out of scope for 1.0 — target builds but is excluded from the iOS archive.
mission_dates: |
  none found — no deadlines in REQUIREMENTS.md, README, or intake dossier
last_verified: 2026-09-25 (API: water-level anomaly shipped to the prediction model, params v7 — see Recently shipped. Earlier today: BUILD 1.4 (31) UPLOADED — iOS + tvOS on TestFlight, carrying
  the tvOS idle-reset fix 8127e53, the only app change since build 30. The surf-headline
  gallery truncation the 9/19 note expected to ride along was NEVER FIXED — still open,
  see app_review_state. Tag flight/build-31.
  THE APPLE ID RE-AUTH BLOCKER IS GONE, structurally: flighting moved to ONE shared tool
  for all of Don's Apple apps — github.com/donwb/flight (private), cloned at ~/dev/flight,
  symlinked ~/bin/flight. This repo keeps only flight.conf + apple/scripts/flight-preflight.sh
  (the hostname tripwire); apple/scripts/flight.sh and ExportOptions.plist are deleted.
  Auth is now an App Store Connect API key (F39TT64YFQ, in ~/.config/appstore/asc.env)
  passed to archive AND export, plus a local Apple Distribution identity in the keychain —
  so neither step touches Xcode's expiring Apple ID session. `flight doctor` passes on the
  Studio. Refrain (bkmks) and AirStory (DroneFlight) were ported to the same tool the same
  day. CLAUDE.md now lets agents flight when Don asks or a dispatch says to
  (.claude/settings.json allows `make flight*`) — but auto mode's classifier still blocked
  an agent's `make flight` as a production deploy on 9/25, so headless flighting by an
  agent is NOT yet proven; Don ran this upload himself. Prior 2026-09-19 midday state below.)
prior_2026_09_19_midday: (TVOS IDLE BUG FIXED ON MAIN, FLIGHT BLOCKED ON
  APPLE ID RE-AUTH. Don reported the tvOS board switching back to New Smyrna Beach
  after ~10 minutes on another camera. Cause: focus doubles as the cam selector
  (ContentView onChange(of: focus)) and the idle branch cleared focus outright —
  clearing it does not leave the board unfocused, tvOS re-seeds onto the first
  focusable view, the cam strip's first chip, firing a channel flip nobody asked for.
  FIXED 8127e53: idle parks focus on the cam already being watched (selectCamera
  no-ops on an unchanged id). REPRODUCED AND PINNED in the Apple TV 4K sim —
  testIdleKeepsTheWatchedCam fails on the old line, passes on the new one; a new
  DEBUG hook --idle-seconds N makes the ten-minute window reachable, alongside
  --sky-minutes and --stream-url. Full tvOS suite 9/9. Note the UI tests are FLAKY ON
  A COLD SIMULATOR: the 20s roster-load timeout in setUpWithError failed twice on a
  first boot and passed on every warm run — warm the sim before believing a failure.
  MARKETING_VERSION BUMPED 1.3 → 1.4 because the 1.3 train closed when tvOS 1.3 went
  live 9/17; a 1.3 (31) upload would be rejected like 1.0/1.1/1.2 were.
  FLIGHT ATTEMPTED AND FAILED at Don's explicit direction (he authorized flighting
  from this remote session, overriding the CLAUDE.md "Don runs this" rule): the
  archive died at CodeSign with "Invalid credentials in keychain for
  don.browning@gmail.com, missing Xcode-Token" and errSecInternalComponent. Confirmed
  `security find-identity -v -p codesigning` shows ONLY "Apple Development" — no
  distribution identity — which is the documented stale Apple ID session, and the
  documented fix (remove the Apple ID in Xcode Accounts with −, re-add with
  password/2FA) needs the console, not a remote session. So the fix is ON MAIN AND
  UNFLIGHTED. Don's press, at the Mac: re-auth, then
  `apple/scripts/flight.sh --tv-only --yes` (it will bump 30 → 31 itself; the build
  number was left at 30 because build 31 never existed). TWO tvOS fixes now ride that
  next flight — this one and the surf-headline truncation. Prior 2026-09-19 morning
  state below.)
prior_2026_09_19_am: (FOUR OF FIVE CAMS UP — nsb is dark upstream and
  that is the county's encoder, not us. Full diagnosis and the do-not-migrate reasoning
  are in Blockers; short version: YouTube says LIVE_STREAM_OFFLINE for 550p9smwjPM on
  every player client while this host resolves other cam IDs fine, the video is neither
  private nor replaced, and the restreamer recovers by itself on its 30-minute backoff
  when the county restarts the stream. Broke 02:25 ET mid-stream. SHIPPED the same
  morning (eb23fc4, deployed and verified live, sw v28): the web board no longer opens
  on a camera the health poller reports offline — nsb is the roster default, so until
  this landed every first-time visitor got a "Reconnecting" panel with four live cams
  sitting in the same payload. Repo: main clean, 0/0 vs origin/main, main is the only
  branch. APP STORE, learned later the same day: tvOS 1.3 (30) was APPROVED and went
  LIVE 2026-09-17 16:33:58Z — Don confirmed, verified here via the iTunes lookup API.
  That closes open item 0 and the App Store thread this repo has carried since the
  first submission on 2026-08-18; both platforms are public on the parity design and
  nothing store-side is outstanding. The nsb outage is now the only live issue, and it
  is the county's to fix. CORRECTS the 2026-09-16 entry below, which reads "EVERYTHING GREEN / all five
  cam endpoints 200" — true when written, overtaken by the nsb outage three days later.
  Prior 2026-09-16 state below.)
prior_2026_09_16: (QUIET, EVERYTHING GREEN. Repo: main clean, 0/0 vs
  origin/main, no stashes, no untracked files; last commits are both 9/13 (d26d398
  restreamer log rotation, 4e688d7 Ormond Beach URL rotation), both merged via PR.
  PRUNED the same session: fix/ormond-beach-youtube-url and
  fix/restreamer-log-rotation are gone locally and on origin (both were
  squash-merged, so their tips were not ancestors of main — confirmed
  patch-equivalent with `git cherry` before deleting). Only main remains.
  WORKFLOW CHANGE (Don, 2026-09-16): this repo does NOT use PRs — commit and
  push straight to main; CLAUDE.md §Git & CI corrected, which had told every
  session the opposite. Branch only to park work that must not auto-deploy.
  TWO ITEMS THE 9/13 ENTRY LEFT OPEN ARE NOW CLOSED, verified from the Studio this
  morning: (1) `make restreamer-diff` reports the deployed ~/bin copy matches the
  repo, so the log-rotation deploy happened; (2) `make restreamer-status` shows the
  launchd job running (pid 7462, all five cams respawned 09:24:15) and ALL FIVE cam
  endpoints returning 200 through the relay — INCLUDING ormond-beach, dark since
  2026-08-31, so migration 013 applied on the auto-deploy and the county's new
  broadcast (p1s7EdZgGvU) is publishing. That clears the long-standing "Ormond Beach
  cam offline upstream" blocker. APP STORE: Don submitted tvOS 1.3 (30) in ASC this
  session — see app_review_state; unconfirmed, verify next session. ENVIRONMENT
  (Don, reported not verified here): the Mac Studio is now set up to build and run
  the native Apple targets, not just web/API — which unblocks local iOS/tvOS builds
  and makes open item 2 (the physical Siri-remote pass) practical from this machine.
  Still watching, not fixing: Ormond-by-the-Sea is chronically flappy (~100 pipeline
  drops/day, source-side starvation upstream, not this host). Prior 2026-09-13 state
  below.)
prior_2026_09_13: (2026-09-13 morning — Studio rebooted for a flaky network; restreamer
  came back on its own — first roster fetch failed pre-network, 120s retry
  succeeded, nsb/ponce-inlet/dunlawton/ormond-by-the-sea publishing and served by
  the relay. Two PRs: (1) fix/ormond-beach-youtube-url MERGED (#9) — migration 013
  finally committed, applies on the auto-deploy; Ormond Beach has been dark since 2026-08-31 (first "Private
  video" in its log), new ID p1s7EdZgGvU verified live + streamable from the
  Studio; deploy applies it, then kickstart or the 6h refresh. (2)
  fix/restreamer-log-rotation OPEN at the time (#10, since MERGED — rebased over the 9/09 work) — per-cam logs had reached 6.7 GB (2 GB each for
  nsb/dunlawton, all yt-dlp's internal ffmpeg chatter): now run at -loglevel
  warning -nostats plus a 64 MB tail-and-truncate backstop (`rotate_log`), and
  the -4 IPv4 fix from 9/04 is committed at last; Makefile restreamer-status now
  probes ormond-by-the-sea too. NOT YET DEPLOYED to the Studio as of 9/13 — Don to run
  `make deploy-restreamer` after merge (agent was blocked from restarting the
  launchd job); the deployed copy was CONFIRMED matching 2026-09-16, see last_verified. Ormond-by-the-Sea is chronically flappy (~100 pipeline drops/day,
  source-side starvation, not this host) — watch, not fix. gh CLI installed on
  the Studio; origin pushurl switched to SSH because no https credential exists.
  Prior 2026-09-09 state below.)
prior_2026_09_09: (DISPATCH 2026-09-09-newbeach-tvos-13-and-listing-link
  executed: iOS 1.2 (28) confirmed LIVE since 2026-09-02 01:49Z via the iTunes lookup
  API and recorded here + REQUIREMENTS §19 + INTAKE + docs/APP-STORE-LISTING.md; the
  Apple TV gallery RECAPTURED for tvOS 1.3 (apple/scripts/screenshots.sh tv — the
  script's `tv` platform, Apple TV 4K (3rd gen) sim against prod, 3 shots at
  3840×2160 showing the sunrise/sunset header band and the verdict tide wave, each
  eyeballed); tvOS 1.3 What's New drafted; the App Store listing is now LINKED from
  beach.donwb.com — board footer (web/js/views/board.js, sw cache v27) and a "Get the
  app" section + footer link on /support, plain text links, zero JS. Don's press:
  submit tvOS 1.3 (30) in ASC with the new gallery. Follow-up the same hour, at Don's
  direction: the surf line's ramp-access clause was county-wide (surfreport.go: "…but
  ramps are tide-closed right now" while only DB-051 was tide-closed) and sat under
  the per-city "Every ramp open" verdict on the tvOS board. FIXED 78e515c — tideClause
  now names the affected cities in local shorthand, up the coast ("…tide-closed right
  now in Daytona", "closure's possible around 1pm in NSB"), county-wide wording only
  when every city has a ramp in the tier; server-side copy, so build 30 renders it.
  Deployed, verified live, Apple TV gallery RESHOT 12:03 ET on the fixed line (the
  ramp-detail shot shows it in full; the board shot's one-row surf headline still
  truncates at "tide-closed…" — a tvOS layout limit, would need a client change +
  flight to lift). Prior 2026-09-04 state below.)
prior_2026_09_04: (CAM OUTAGE FIXED: all five cams went dark at the
  13:20 ET roster refresh — YouTube now bot-walls live-stream resolves from the home
  connection's IPv6 egress ("Sign in to confirm you're not a bot" on every player
  client; PO tokens don't clear it; VODs and IPv4 are unaffected). Fix: `yt-dlp -4`
  in cam-restreamer.sh, deployed to the Studio via make deploy-restreamer, sustain-
  tested 90s+; nsb/ponce-inlet/dunlawton/ormond-by-the-sea verified back online end
  to end. Also upgraded yt-dlp 2026.7.4→2026.8.19 + bgutil provider/plugin
  1.3.1→1.3.2 (needed anyway, not sufficient alone), and dropped the stale
  ondigitalocean.app API_BASE override from ~/.cam-restreamer.env (backup kept).
  Ormond Beach (down since 8/16) is a SEPARATE issue: its YouTube video went
  private; new live ID p1s7EdZgGvU found on the county channel; migration
  013_update_ormond_beach_youtube_url staged UNCOMMITTED — needs PR + deploy, then
  a restreamer kickstart or the 6h refresh brings it back. Prior 2026-09-01 state below — this entry was never committed until 9/13.)
prior_2026_09_01: (iOS 1.2 (28) SUBMITTED in ASC by Don — the update
  review — with the redrafted description, 1.0→1.2 What's New, and the 8/23
  iPhone/iPad screenshots; all five shots eyeballed pre-submit, sky-label/clock
  mismatch on the golden+dawn pair noted and accepted, day shot leads the gallery.
  Earlier same day: RELEASED — iOS 1.0 (18) + tvOS 1.2 (28) LIVE on the App Store
  2026-09-01 15:56Z — first public release ever for the record, both platforms, both
  auto-released on approval. Confirmed by Don via ASC screenshot, verified from this
  repo via the iTunes lookup API ("Volusia Beach Info", 1.0, free, store URL in
  distribution). Public iOS build is 18 (pre-parity) by the 8/23 leave-it-in-the-queue
  decision. iOS 1.2 (28) submission assets verified undrifted since 8/23 (listing copy
  + 8 screenshots, commits 3c92894/d554001) — Don presses submit in ASC; it's an update
  review now. Staged behind: tvOS 1.3 (30) needs the Apple TV gallery recaptured first;
  beach.donwb.com can now link the store listing (wording caution until 1.2 clears).
  Docs swept: REQUIREMENTS §19 + INTAKE "in review / not released" claims corrected.
  Traffic note: expect an App-Store-referred bump in beach-traffic-check — don't read
  it as county interest. Prior 2026-08-26 state below.)
  prior: 2026-08-26 15:03 (COUNTY OUTREACH: outcome logged and strategy pivoted — one county-network reader (GIS-server /24) opened /county/ 4h after the 8/17 send and the live board the next day, then went silent; no reply as of 8/26. Don is stepping back to plan a portfolio-level messaging campaign for all apps instead of courting the county directly — see open item 0a. Earlier same day: API: stale county-data quarantine SHIPPED, params v6 — see Recently shipped 2026-08-26; county forgot the 8am flip on 8 ramps today, heuristic + manual prediction_excluded_days settings key keep such days out of training/prior/scorecard; deploys with a boot retrain. Earlier: tvOS BUG FIX awaiting flight: 1.3 (29) on Don's device drew the verdict tide wave's now-line frozen at app-launch time (Date() read inside the draw closure + SwiftUI render-skip; spotted on the wall TV at 5:19pm showing a ~10:45am line). Fixed 376b1d5 — now is a stored input ticked every 30s, --sky-minutes drives it for screenshots; verified in sim at two injected clock times. FLIGHTED by Don as tvOS 1.3 (30), tag flight/build-30 — the current TestFlight build. The 1.3 (29) upload did go up 2026-08-24 (Don ran it; the build is on his Apple TV via TestFlight) — 29 is superseded by the fix. Earlier: tvOS: sunrise/sunset added to the header band (SF Symbol glyphs, left of Water) and today's tide curve with a sand now-line drawn beside the verdict headline, left edge aligned to the surf/weekend column split — commit 82e8835, verified on the Apple TV 4K sim against live data. FLIGHT: tvOS 1.2 (28) turned out APPROVED (closed-train rejection on the 1.2 (29) upload); MARKETING_VERSION 1.2 → 1.3, build 29 archived as 1.3, upload pending — Don runs apple/scripts/flight.sh --tv-only --yes --no-bump. NOTE: build 29 makes the 8/23 Apple TV store shots stale again (no sun times, no verdict wave) — recapture the tvOS gallery before submitting 1.3 on tvOS. Earlier same day: tvOS LEDGER POLISH (uncommitted-to-device): the weekend column headline now wraps to two reserved lines — a day with no best_window falls back to the server's full sentence and was truncating ("Storms look parked over most of the…"); the height came out of the dead Spacer above, the surf block did not move. Ramps column heads renamed RAMP → NAME and NEXT → RAMP PREDICTION. Verified on the Apple TV 4K sim. NOTE: this makes the checked-in Apple TV store shot (design/app-store-screenshots/appletv/01-board.png) stale — it shows the old NEXT header and the truncated weekend line; recapture the tvOS gallery before submitting 1.2. Needs a flight to reach devices. DECISION: iOS 1.0 STAYS in the review queue (Don) — do not pull it, do not touch its gallery; submit 1.2 (28) once it clears. tvOS 1.2 (28) is submittable now as an update. CORRECTION: iOS has NEVER been approved — ASC screenshot from Don shows "iOS 1.0 Waiting for Review" / "tvOS 1.1 Ready for Distribution". The 8/21 "1.0 approved" read was tvOS-only (trains are per-platform). The pending iOS 1.0 record can only carry build 18, so builds 26/27/28 cannot attach to it — see open item 0 for the fork. SCREENSHOTS: all 8 store shots recaptured 2026-08-23 from the renamed build (iPhone 6.9 x3, iPad 13 x2, Apple TV x3), each verified by eye. RELEASE: 1.2 (28) UPLOADED to TestFlight for BOTH iOS and tvOS, both EXPORT SUCCEEDED, tagged flight/build-28. 1.2 listing copy drafted in docs/APP-STORE-LISTING.md. Screenshots still show the pre-rename header — recapture before submitting. RELEASE: tvOS 1.1 (25) is APPROVED — surfaced by the closed-train rejection when flighting, Don to confirm in ASC. MARKETING_VERSION 1.1 → 1.2; both platforms flighted as 1.2 (28) with the rename. NAMING: one-name pass done — "Volusia Beach Info" is now the name on every surface (web title/wordmark/manifest/per-view titles, /county page, iOS + iPadOS + tvOS in-app wordmark, TRMNL template headers, README/REQUIREMENTS/CLAUDE.md). tvOS header band dropped the "Volusia County" subtitle at Don's direction — the wordmark stands alone and that space is reserved for something else. INFOPLIST_KEY_CFBundleDisplayName = "Beach Info" (Don's call — the full 18-char name truncates under the icon); verified in the built Info.plist. iOS/tvOS/watch all BUILD SUCCEEDED, go vet + server tests pass, web verified in-browser. Widget gallery entries renamed off the old app name to "Ramp Board" / "Ramps Open Now" (intent title "Ramp Widget") — Don to veto if unwanted. Apple changes need a flight to reach devices; sw CACHE_NAME v24→v25 and ?v=16→17 bumped for web. API: period-aware rough regime DEPLOYED 7f44672 and verified live — today's buoy 1.31 ft @ 13 s now reads `rough`, NS-141/110/118 "closure possible ~4–4:30pm", NS-106/DBS-075 "could close ~6:30pm" — the same sea state that read quiet yesterday. Review scorecards ~8/30; fallback if over-hedging = "disqualify calm" variant. API: grade-aware shift scans SHIPPED 3312421, prod force-retrained 13:38Z at Don's direction — calm raise 0.45, NS-141/118/110 open-yesterday raise 0.4; today's outlook flipped from "tide closure possible ~3:30pm" to "closes for the day ~6:30pm" on every NS/DBS ramp. First real test: tomorrow's scorecard for 2026-08-22. iOS/iPadOS 1.1 (26) UPLOADED to TestFlight at Don's direction — ASC processing; the iOS 1.1 listing draft (What's New + redrafted description) is in docs/APP-STORE-LISTING.md, ready to paste once the build appears; Don action: submit the iOS 1.1 version in ASC. Web: server city verdict + overnight override deployed; city headline bug fixed server-side; favorites pulled from web, iOS keeps "Pin to widget" only. tvOS 1.1 (25) SUBMITTED for review — see app_review_state. Physical-remote pass on build 24 found one bug: Don
  loved the layout but could not focus the ramp list — Watching and Beach outlook
  focused fine. Cause: after the turtle-season close the ledger swapped the ramp
  list for an "Overnight · All cities" roll-up that was built non-focusable, so
  every evening the ramps were unreachable. Fixed 2026-08-21 morning: the
  focusable RampsBox stays on the ledger around the clock; overnight its rows
  read Closed (the outlook is authoritative — the county feed lags at OPEN) with
  the server reopen copy in Next. OvernightCitiesBox/TVOvernightCityLine/
  overnightCityLines DELETED. Reproduced and verified in the tvOS sim against
  prod while prod was still in the overnight state (07:58–08:00 ET): all 8 UI
  tests pass incl. the ledger walk and row Select → detail → Menu restore.
  FLIGHTED at Don's direction 2026-08-21 08:39 ET as 1.1 (25), tvOS only (iOS is
  unchanged since 24), tag flight/build-25 — after the first attempt as 1.0 (25)
  bounced off ASC's closed 1.0 train, which is how we learned 1.0 was approved. Same morning,
  second remote-pass bug, server-side: the city verdict detail said "first around
  1:30pm" (the risk WINDOW start) while every ramp row said 2:30pm (peak minus
  learned lead). Fixed in predict: each RampOutlook now carries the close time its
  own copy quotes (likely → peak−lead, possible → the peak) and the city line
  aggregates that — it can never name an hour no ramp line names; when the
  earliest is the peak itself the suffix is dropped rather than repeated. Pinned
  by TestCityVerdictFirstAroundMatchesRampCopy. Deployed via main; no client
  change needed (clients render the strings verbatim). Then, at Don's ask ("All five
  open" and "Pretty much flat out there" five days running gets old): a VOICE LAYER
  (predict/voice.go) — the surf line and the all-open verdict rotate through pools of
  local-lingo phrases (the Inlet, the break, lineup, groms, Beachway, sharks), seeded
  by ET date + daypart so the wording changes morning/midday/evening and never between
  refreshes; closure copy is untouched. Also fixed in passing: the surf line's
  "closure's possible around" clause had the same window-start bug. Deployed via main.
  Earlier 2026-08-20: tvOS REBUILT AGAIN to the "video first" design — Don lived
  with the two-mode board on a real device one evening and killed it: he watches the
  video far more than expected, and the mode toggle made the information fight the
  picture. New design (Claude Design project d3055b06, handoff README in the project's
  design_handoff_tvos_videofirst/): fixed bands — header 110 / picture 340 / cam strip
  56 / ledger 574 — the panorama is NEVER covered, cropped further, or moved; pull
  surfaces (Beach outlook from the header button, Ramp detail from a ledger row)
  replace the bottom 630pt only; red means closed and nothing else (focus/active/
  all-open are dry-sand #F0DDB4); the ground follows the sun through 16 NEW dark
  day-part gradients (TVSkyGround, tvOS-local, contrast unit-tested, three anchors
  pinned from the mock). The 1280×270 relay stream is top-crop-clipped client-side to
  1920×340, which exactly removes the vendor's baked-in AccuWeather badge (relay stays
  -c copy). No mode toggle: TVBoardMode, both invisible focus catchers, SunRibbon, and
  all three overlays DELETED. Ledger: server per-city verdict copy rendered verbatim
  (new /api/v2/outlook `cities` block, VerdictBuilder fallback), windowed 5-row ramp
  list (closures sort to top, sand scroll thumb, "12 · 7 below" header count), per-ramp
  Next column from outlook short/reopen strings, surf report + weekend slots right.
  Ramp detail surface: today bar + white tide curve + 48h log from /intervals.
  Beach outlook surface: 7-day table (Day/High/Rain/Surf/Best window/Closure risk)
  from the weekend endpoint extended same-day to 7 days + closure_risk_label +
  surf_label, plus the new per-city verdicts (Go: cityverdict.go/citytext.go, all
  additive, backtest pins untouched, deployed to prod before the client). Archivo now
  used on tvOS via the shared package's registered faces. Verified in the tvOS
  simulator against prod: resting/outlook/detail/golden/night screenshots, crop
  framing validated against a captured live frame, 6 rewritten XCUIRemote UI tests
  passing (cam switch, ledger walk, city cycle, box-local Right, both surfaces with
  focus restore), TVSkyGround contrast test sweeping every 2° of sun altitude. QA args
  now --surface-outlook / --surface-ramp-detail (+ --stream-url); screenshots.sh
  updated. Sim quirk noted in-commit: the tvOS Simulator renders the relay's mpegts
  video slowly/black at first (audio leads) — real hardware is fine, fmp4 renders
  instantly. FLIGHTED at Don's direction 2026-08-20 afternoon: build 1.0 (23), both
  platforms, tag flight/build-23 — TestFlight-only, build 18 stays pinned to the App
  Review submission. The physical-remote pass (item 2) should ride this build. Also
  verified same afternoon (Don asked): the follow-the-sun ground IS live in
  video-first — TVSkyGround keeps all 16 phases on SkyPalette's anchors, deliberately
  re-voiced dark (teal noon, amber golden hour), confirmed by --sky-minutes
  noon-vs-golden screenshots. Don then called the dark re-voicing WRONG — he wants
  the bright evolving sky back — so later the same afternoon the ground was
  reverted to the shared full-brightness SkyPalette (TVSkyGround DELETED) with a
  new TVSky ink-veil layer (v3's panel hue 0x041A28: header flat 0.32, ledger
  gradient 0.42→0.62, picture never veiled) keeping type legible on the pale
  day phases; the TVSkyGround darkness test was replaced by veil-contrast tests
  sweeping every 2° of sun altitude (white ≥3.5:1 ledger / ≥3.0 header, sand
  ≥2.4 header). Verified noon/golden/night in the sim; all UI tests pass.
  FLIGHTED as build 1.0 (24), tag flight/build-24 — this supersedes build 23's
  dark grounds and is the build for the physical-remote pass.
  App Store TV screenshots now trail by FOUR designs.
  Prior 08-19 state below.)
prior_2026_08_19_late: (tvOS gained its TWO-MODE presentation from the
  "tvOS modes" Claude Design handoff — Cam mode and Board mode, one D-pad press apart.
  Cam mode is the new resting state: the video at its native 680pt (1:1 — the 3222×680
  source's largest sharp frame, 60% of the panorama; Board mode's 405pt band shows 100%
  at 0.596×; neither upscales — resizeAspectFill produces both automatically), below it
  a surf sentence and the five ramp cards on a dark ambient ground; no heading, weekend
  panels, or daylight bar. The band's verdict block moved to fixed top-anchored
  coordinates so brand row / weather / clock / verdict hold identical positions in both
  modes — only the video's bottom edge travels, with the caption strip riding it. Down
  opens the board (invisible focus catcher below the band), Up from the caption strip
  falls through and closes it (catcher above the strip, Home-screen style), Menu
  returns to Cam mode from the board and exits the app from Cam mode — Recent changes
  now opens ONLY from the heading button. Mode persists across launches (tvDisplayMode
  default) and falls back to Cam after 10 idle minutes; a verdict change while Cam
  mode is up flashes the accent bar in place and never opens the board. The board is
  one translated block (340ms ease-out) — the ramp cards ride between modes rather
  than rebuild, board chrome crossfades. Caption strip right end hints the mode
  ("▾ Ramps" / "▴ Full cam"). Verified in the tvOS simulator against prod: cam/board
  screenshots plus a scripted D-pad walk (down-open, row order, up-close, both Menu
  behaviors); UI tests rewritten for the two-mode focus graph, all passing.
  FLIGHTED at Don's direction: build 1.0 (22), both platforms, tag
  flight/build-22 — TestFlight-only, build 18 stays pinned to the App Review
  submission. Docs tied up the same session: the tvOS v3 + modes design-handoff
  READMEs and modes design sources checked into design-review/, REQUIREMENTS.md
  §10 rewritten for the two-mode board (and §10.5's retired yt-dlp URL-push spec
  replaced with the cam-relay summary), §19 tvOS row updated. Note the submitted
  App Store TV screenshots now trail the app by three designs (v2 tiles → v3 →
  modes) — recapture whenever listing assets are next touched. New QA args:
  --mode-cam / --mode-board. Earlier same night below.)
prior_2026_08_19_night: (tvOS board REBUILT to "tvOS design v3" (panorama
  header, inline selectors — implemented from the Claude Design project handoff).
  New structure: the cam holds the top 405pt full-bleed at its true 4.74:1 aspect
  and carries the verdict (80pt headline + subline) plus a WATCHING caption strip
  on its own bottom edge (all five cams, focus flips channels, offline cams struck
  through with "offline since", nearest live neighbor named in amber); city
  switching moved into the ramp section heading ("RAMPS New Smyrna Beach ‹ ›" +
  count + Recent changes); ramp cards are 218pt with a new `overnight` state
  (neutral field driven by the outlook's closed_now/overnight call — red now means
  only an unplanned closure, and the verdict goes "Driving is done for today" with
  the server's reopen copy); recovered space became the Ahead band — a 48pt surf
  panel (line + rip risk + height/period/buoy-age, honest no-read state) and two
  weekend day panels that open the NEW seven-row beach-forecast table overlay
  (replaces the column OutlookOverlay); a slim daylight strip closes the screen.
  DELETED: TopBar, VerdictBand/stat tiles, CoastlineRail, WeatherOverlay (the
  Water/Air/Wind strip lives in the cam band, no overlay behind it). Shared
  BeachStatus gained the outlook `surf` context block (wave height/period).
  Verified in the tvOS simulator against prod (board, forecast, activity
  screenshots) and all 4 XCUIRemote UI tests rewritten for the new focus graph
  (cam strip → heading → day panels) pass. FLIGHTED same evening at Don's
  direction: build 1.0 (20), both platforms, tag flight/build-20. Followed the
  same night by build 21 (tag flight/build-21) backing out the
  infrared-after-dark cam treatment: the feed now presents identically day and
  night, and the night dim scrim stops at the cam band. (Build 21's first
  export attempt failed on a transient home-DNS blip — NSURLError -1003
  masquerading as the stale-Apple-ID failure; the --no-bump --yes rerun went
  clean.) Build 18 stays pinned to the App Review submission.
  Same night: all four live cams went dark at the relay ~7:50–8:00 PM ET — a
  home-network event stalled every RTMP publish (droplet log: i/o timeouts,
  then zero reconnects) and the Studio restreamer never recovered; upstream
  YouTube broadcasts verified still live, resolves verified working from the
  home IP, Studio up on LAN but SSH-less — needs a hands-on kickstart.
  Earlier same day below.)
prior_2026_08_19_pm: (tvOS caught up with the predictive features, then
  the band was redesigned the same session — the three stat squares (Tide /
  Water·Air / Wind) plus the briefly-added Weekend tile became TWO rectangles:
  "Outlook" leads (labeled SAT/SUN columns with color-coded verdict words + the surf
  line, opening the six-day overlay with verdict pills, best stretches, feels-like
  temps, and the surf read), "Weather" follows (labeled WATER/AIR/WIND micro-columns
  + next tide extreme — labels chosen over bare values after Don couldn't tell 83°
  water from 84° air — opening one combined overlay: tide curve/extremes + water
  stations + NWS forecast with per-period wind).
  WeekendOutlook model + fetchWeekendOutlook() added to the shared BeachStatus
  package; the three single-stat overlays are gone; XCUIRemote UI tests updated and
  passing; screenshots.sh TV shots repointed (--overlay-outlook/--overlay-weather —
  the submitted App Store TV screenshots 02-tide/04-water no longer match the app
  and STILL need recapturing + re-submitting whenever listing assets are next
  touched). Verified in the tvOS simulator against prod, then FLIGHTED: Don
  overrode the build-18 wait and build 1.0 (19) went to TestFlight 2026-08-19
  (both platforms, tag flight/build-19) so he can live with the new TV board.
  TestFlight-only — build 18 stays the one pinned to the App Review submission.
  Earlier same day below.)
prior_2026_08_19_am: (TWO NEW FEATURES SHIPPED to main → prod (web): (1) Weekend
  Outlook — /api/v2/outlook/weekend, 6-day great/good/mixed/tough verdicts from the
  tide engine + new NWS forecast package (api/internal/nwsfc), live-tunable thresholds
  in the weekend_verdict_params settings key, web board section below the ramp cards;
  (2) Surf Report — one casual surf line (surf_report block on both outlook endpoints)
  from buoy + NWS wind + KMLB Surf Zone Forecast rip risk (relayed verbatim), shown
  beside the weekend outlook on web and in the iOS detail band in-tree. iOS surf line
  needs a re-flight to reach TestFlight; tvOS/TRMNL deferred. Next up: a /county/
  showcase section for the weekend outlook. Prior state below. Same-day refinement
  2026-08-19 pm: weekend verdicts now justify themselves — dayVerdict reports binding
  drivers, a `why` line renders when the headline doesn't name the cause (e.g. MIXED
  from a 108° heat index), and day cards show feels-like temps; live on web + county
  page.)
prior_2026_08_18: (SUBMITTED FOR APP REVIEW — build 1.0 (18), first submission ever.
  Same day, the prep that made it possible: full ASC metadata sheet written to
  docs/APP-STORE-LISTING.md — name, subtitle, keywords, descriptions, review notes, and
  privacy answers for BOTH platforms, every length-limited field measured. Listing name
  changing from "Beach Ramp Status" to "Volusia Beach Info" (Don, 2026-08-17). Privacy and
  support pages BUILT (web/privacy/, web/support/, web/legal.css, linked from the board
  footer) — they clear the two required-URL blockers once main deploys. Fresh Apple TV
  screenshots captured at store size (3840×2160 ×4) into design/app-store-screenshots/appletv/
  via a new `tv` platform in apple/scripts/screenshots.sh. Content Rights (the cams are
  third-party YouTube streams re-broadcast through the relay) is Don's open decision.
  Prior 08-16 state: cam relay stabilized + camera_health tracking shipped (a27a28a);
  prediction feature shipped with nightly-trained per-ramp model and /api/v2/outlook
  consumed by web, iOS/iPadOS, tvOS, and widgets; Don action still pending: set
  CAM_HOOK_KEY in the DO UI to activate the instant-hook path. Ormond Beach cam still
  dead at the county's end.)
---

## Top open items
0a. County outreach — SENT 2026-08-17 ~10am ET, NO RESPONSE as of 2026-08-26; STRATEGY
   PIVOTED. The pitch (free app ↔ sanctioned ramp-data access + direct WeatherBug cam
   feeds) went to Tamra Malphurs (Beach Safety, CC Jessica Fentress/Coastal) plus a warm
   reply on the 2024 GIS thread with Brandon Barnett; both emails pointed at the
   /county/ pitch page (live, linked from a homepage banner). OUTCOME, from the
   first-party page_views log (migration 011, GET /api/v2/admin/pageviews, read via the
   beach-traffic-check skill): ONE county reader, 74.191.71.218 (same /24 as the
   maps*.vcgov.org GIS servers — so almost certainly Barnett/Turner's side, not Beach
   Safety), who opened /county/ four hours after the send (8/17 14:03 ET) and came back
   the next afternoon for the live board (8/18 15:45 ET) — then nothing: no reply, no
   return visits since, no forwarding cluster. Read: the pitch was seen and evidently
   not escalated; Beach Safety likely never engaged. DECISION (Don, 2026-08-26):
   step back from courting the county directly; next move is a PORTFOLIO-LEVEL
   messaging campaign across all the apps, run from the hub (~/atc) — this repo
   holds until that campaign dictates otherwise. Untouched fallbacks if it ever
   reopens: a low-pressure bump to Barnett (his side did click), Beach Safety by
   phone (386-239-7873), county Community Information. The traffic tripwire stays
   live: any new county-/24 hit shows up in the beach-traffic-check skill's output.
0. App Store — CLOSED 2026-09-17. Every Apple platform is public on the current
   parity design: iOS/iPadOS 1.2 (28) live since 2026-09-02 01:49Z, tvOS 1.3 (30)
   live since 2026-09-17 16:33:58Z (submitted 9/16, approved in about a day; verified
   2026-09-19 via the iTunes lookup API, entity=tvSoftware, version 1.3). That was the
   last thing this repo owed the store. There is no App Store backlog item any more —
   the next submission is whatever new client work earns one, and it will be an update
   review on both trains, which this record has now cleared twice in under a day each.
   Shipped with the gallery truncation noted in app_review_state, accepted knowingly;
   fix it in a later tvOS build rather than holding a release for weather.
   DONE 2026-09-09: beach.donwb.com links the listing
   (https://apps.apple.com/us/app/volusia-beach-info/id6761724123) from the board
   footer and /support ("Get the app"); the build-18 wording caution is over.
   Sibling dispatch 2026-09-09-donwb-com-beach-merge.md handles the donwb.com side.
   HISTORY: iOS 1.0 (18) went live 2026-09-01 and was superseded ~10h later.
   Metadata as submitted is checked in at docs/APP-STORE-LISTING.md; /privacy and
   /support are live and verified. Screenshots done for iPhone 6.9", iPad 13", and
   Apple TV (3840x2160, design/app-store-screenshots/appletv/). If review comes back
   with a rejection, the two most likely fronts are (a) name proximity to the county's
   own "Volusia Beaches" app (guideline 4.1/2.3.8) — mitigated by the explicit
   "not affiliated with Volusia County" line in the description and support page, and
   (b) Content Rights for the beach cams, which are public YouTube live streams from
   the county's own channel re-broadcast through the cams.donwb.com relay.
   RESOLVED 2026-08-23: the name is "Volusia Beach Info" everywhere — listing, website,
   in-app wordmark on iOS/iPadOS/tvOS, docs. INFOPLIST_KEY_CFBundleDisplayName is
   "Beach Info" (not the full 18-char name, which truncates on the Home Screen).
   Takes effect on the next flight; the built binaries still say "Beach Ramps".
0b. DONE 2026-08-21 — iOS/iPadOS feature parity with web/tvOS, on main, unflighted:
   weekend outlook ("When should I go?") on iPhone board + iPad rail/portrait;
   server city verdict (outlook.cities) now the phone/iPad headline when live, with the
   overnight override and overnight rows forced to Closed like tvOS; surf block with
   height/period/rip/buoy-age facts; iPhone gained the forecast strip and the city
   recent-changes feed the iPad already had. Web followed the same afternoon (9392995):
   server city verdict + overnight override, so all three platforms now share one
   headline. Favorites pulled 2026-08-21 (Don: they never synced across web/iOS/TV, so
   confusing) — web dropped entirely; iOS keeps the mechanism only as "Pin to
   widget" on the detail screen feeding the widget's "Pinned ramps" mode. Remaining
   gap: web detail has no threshold line.
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
1c. Predictive closure features — SERVER-SIDE MODEL SHIPPED 2026-08-16. A nightly
   trainer (03:30 ET) learns per-ramp closure thresholds/lead/lag/base-rate from
   ramp_status_history + NOAA peaks (settings key prediction_params; inspect via
   GET /api/v2/admin/prediction/params). /api/v2/outlook + /ramps/:id/outlook serve
   casual risk copy ("High-tide closure likely midafternoon"), consumed by web
   (detail band + board hints). A five-month backtest pins recall/calibration
   floors in CI. beach_conditions snapshots (tide/wind/NDBC waves, 30-min) accrue
   for the surf feature that mid-range accuracy needs. NOTE: a curated
   ramp_metadata.closure_height_ft OVERRIDES the learned threshold — with learned
   values now live, curation (1a) is optional and can even fight the model; clear
   or verify curated heights against learned ones. tvOS AND iOS/iPadOS consume
   /outlook as of 2026-08-16 (shared BeachStatus Outlook model + fetchOutlook;
   board tiles/rows show the server's short hints, and the iOS detail status
   band prefers the server line over ClosureProjector, which stays as the
   old-server fallback; both verified in simulators against prod — needs a
   re-flight to reach devices). Widgets too: BoardSnapshot carries the outlook,
   all families show a hint line ("Tide risk on 5 ramps · closure likely
   ~10am"), verified on the simulator home screen. Live Activity explicitly
   deferred (Don, 2026-08-16) — widgets cover prediction; pushes wait for the
   APNs sender. WAVE-AWARE MODEL SHIPPED 2026-08-18 (prompted by Aug 17-18
   false alarms: "likely" on 3.3 ft peaks over a 0.5 m swell, zero closures):
   new wave_observations series (NDBC 41113, logger dual-write + trainer
   self-heal + archive backfill to March), county-wide calm/rough regime
   split learned jointly (boundary + threshold shift, misses weighted double)
   layered on the tide thresholds — calm raises the bar, swell widens
   "possible" downward but never promotes to "likely", hard cutoffs immune.
   Backtest vs tide-only: mid-band recall way up (PI-097 0.16→0.58, DB-041
   0.78→0.90, DBS-075 0.81→0.90), "likely" precision up everywhere, Aug 17
   false alarms 7→3 on replay. Outlook now carries a `surf` block; scorecard
   grades carry WVHT/DPD; PREDICT_WAVES_ENABLED=false is the serve-side kill
   switch; params v4 retrains on deploy. REMAINING: TRMNL consumption, retire
   the duplicated JS/Swift reopen heuristics fully, period-aware runup
   refinement (11s groundswell > its height suggests; DPD now recorded on
   every grade), APNs Live Activity sender, and eventually a
   re-flight so the apps render the 2026-08-17 `scheduled` end-of-day hint.
   **Re-flight deliberately deferred (Don, 2026-08-17): let build 18 finish
   App Review first** — do not upload a new build while 18 is pending. The cost
   of waiting is small: build 18 already shows the overnight "opens around 8am"
   copy (it reuses the existing closed_now path), and the end-of-day hint simply
   degrades to the since line until a later build.
2. One physical-remote pass on the Apple TV — remote navigation (focus order, Recent
   changes button, Menu open/close, overlay focus restore) is now covered by
   BeachRampTVUITests via XCUIRemote in the simulator; a real Siri-remote sanity pass
   is still wanted before calling it done.
3. DONE 2026-08-16 (b3c9817) — Web multi-camera switcher: board + ramp-detail cam
   sections render roster chip tabs off /api/v2/cameras; recovery re-fetches the
   roster so a non-default pick survives playback failures. Same commit restored
   inline switcher chips to the iPad board (lost in the redesign; iPhone switches
   in the fullscreen cam). iPad chips ride the next flight. INTAKE §6.
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
   multi-camera switcher and the tvOS redesign. INTAKE §8. Partial 2026-08-15: App Store
   gallery captured at store sizes (iPhone 6.9" ×3 sky phases, iPad 13" ×2, watch ×1) via
   the new `make screenshots` automation into design/app-store-screenshots/ (5a972ab);
   slides/screenshots/ itself still stale.
8. DONE 2026-08-19 — Site-copy fixes from the claim audit ("Beville" ramp doesn't exist in
   the live feed; "six screens" is now seven). Verified against live donwb.com: the beach
   page renders GRANADA / DUNLAWTON / HARTFORD / MILSAP / FLAGLER — Beville is gone,
   replaced by Flagler — and the body copy carries no screen-count claim at all. The copy
   itself lives in the donwb-com repo, so nothing remains to do here. INTAKE §5 (V3, V8).

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
- RESOLVED 2026-09-13/16: Ormond Beach cam is BACK. Its YouTube broadcast went private
  2026-08-31 (the second such rotation — the first killed it 8/16); the county's new
  live ID p1s7EdZgGvU landed in migration 013 (4e688d7, PR #9), applied on the
  auto-deploy, and the endpoint was verified serving 200 through the relay 2026-09-16
  with all five cams publishing. Standing risk, not a blocker: the county rotates these
  broadcast IDs without notice, so expect to repeat this — find the new ID on the county
  channel, add a migration, deploy, then kickstart or wait for the 6h roster refresh.
- NSB cam offline upstream since 2026-09-19 02:25 ET — COUNTY-SIDE, no repo action.
  YouTube reports `playabilityStatus: LIVE_STREAM_OFFLINE` / "We're experiencing
  technical difficulties" for 550p9smwjPM on every player client, while the same host
  resolves other cam IDs fine (PO token, m3u8, format) and the other four publish — so
  this is the county's encoder, not our relay, yt-dlp, or the home connection. UNLIKE
  Ormond's two rotations, the video is NOT private and NOT replaced: it still sits on
  the Volusia Beaches channel (UCjYc5xAEWCYIcqG1-KC9nZQ) among the current five cam
  broadcasts, titled "New Smyrna Beach Cam 180". So the ID stands and the restreamer
  recovers on its own 30-minute backoff whenever the county restarts the stream — do
  not write a migration for this one. Escalate to the Ormond playbook (find the new ID
  on the channel, migrate, deploy) ONLY if the video turns private or a replacement
  broadcast appears. Board impact is covered as of 2026-09-19 — see Recently shipped.
- County GIS is an unstable upstream: Volusia renumbered every OBJECTID once already
  (fixed in ff3a353 + migration 006); could recur.
- RESOLVED 2026-09-01/02: both Apple platforms are RELEASED — tvOS 1.2 (28) live
  2026-09-01, iOS 1.2 (28) live 2026-09-02 — so "live on the App Store" is a supported
  claim and the public iOS app is the current design; the old build-18 wording caution
  no longer applies.
- The tvOS record's bundle ID is frozen at com.donwb.BeachRampTV, so that identifier is
  permanent for every platform including iOS and watch. Confirmed 2026-08-15 by the upload
  itself: ASC rejected build 2 with "bundle version must be higher than the previously
  uploaded version: 15", proving real history behind the freeze. Accepted deliberately —
  the alternative was deleting and recreating both records, risking the reserved name
  "Beach Ramp Status" to fix a purely cosmetic identifier that users never see.
- Waiting on Don personally: home-cron host maintenance and any App Store Connect
  actions (next: submit 1.4 (31) for review when he wants the idle fix public). The
  2026-09-19 Apple ID re-auth blocker is RESOLVED 2026-09-25 — flights now use an ASC
  API key + local Apple Distribution identity via the shared flight tool.

## Recently shipped
- 2026-09-25: Prediction model reads the water that arrives — observed-minus-predicted water level at Trident Pier + Mayport raises every predicted tide to effective water height, in training and serving (outlook, weekend, scorecard); below-normal water counts half; params v7 (retrain on deploy). Walk-forward backtest, 27 ramps May–Sep: misses 111 → 21, "likely" precision 0.59 → 0.74, September (king-tide season) misses 28 → 4. Kill switch PREDICT_WATER_LEVEL_ENABLED. Still open: after-hours evening peaks that close ramps mid-afternoon aren't in the outlook or scorecard.
- 2026-09-25: 1.4 (31) uploaded to TestFlight, iOS + tvOS — the tvOS idle-reset fix (8127e53: idle no longer flips the cam back to New Smyrna). First build through the shared flight tool (github.com/donwb/flight) on an API key. Tag flight/build-31.
- 2026-09-17: tvOS 1.3 (30) RELEASED on the App Store — the sunrise/sunset header band,
  the verdict tide wave with a now-line that ticks every 30 s (the build-29 freeze fixed
  in 376b1d5), two-line weekend headlines, and the NAME · NOW · RAMP PREDICTION column
  relabel. Submitted 9/16, live 9/17 16:33:58Z, verified 2026-09-19 via the iTunes
  lookup API. Closes the App Store thread that had been open since the first submission
  on 2026-08-18: both platforms are now public on the parity design.
- 2026-09-19 (latest): Web camera pick became offline-aware. NSB — the roster's
  `default_id` — went dark upstream at 02:25 ET and `pickCamera` (web/js/cam.js)
  selected on ID alone, so every first-time visitor to beach.donwb.com landed on a
  "Reconnecting" panel while four cams sat live in the same roster. Now an explicit
  viewer pick stays sticky even when dark (they chose it, it may come back), but a
  pick the app makes steps over a camera the relay health poller reports offline; a
  missing `online` flag counts as live, so older payloads behave as before. The views
  record that fallback into `selectedCameraId` — without it the roster refresh that
  brings the default back would yank the video to another beach mid-watch. Covered by
  8 new cases in web/js/smoke.test.mjs; sw CACHE_NAME v27→v28, ?v=18→19.
- 2026-09-13 (latest, two PRs, both merged and now verified deployed 2026-09-16): Cam
  infrastructure. (1) #9 / 4e688d7 — migration 013 rotates Ormond Beach to the county's
  new YouTube live ID (p1s7EdZgGvU) after its old broadcast went private 2026-08-31;
  applied on the auto-deploy, the cam is serving again and all five are online for the
  first time since 8/16. (2) #10 / d26d398 — per-cam restreamer logs had reached 6.7 GB
  (2 GB each for nsb/dunlawton, almost entirely yt-dlp's internal ffmpeg chatter): the
  downloader now runs at `-loglevel warning -nostats` with a 64 MB tail-and-truncate
  backstop (`rotate_log`), the 9/04 `-4` IPv4 fix is committed at last, and
  `make restreamer-status` probes ormond-by-the-sea too. `make restreamer-diff` confirms
  the deployed ~/bin copy matches the repo.
- 2026-09-09: tvOS 1.3 listing prep + the city-scoped surf line (12b8dfb, 78e515c,
  60bb16a) — iOS 1.2 confirmed live via the iTunes lookup API, the Apple TV gallery
  recaptured at 3840×2160, the App Store listing linked from the board footer and
  /support, and the surf line's ramp-access clause narrowed from county-wide wording to
  the cities actually tide-closed (server-side copy, so build 30 renders it).
- 2026-08-26: Stale county-data quarantine in the prediction trainer (params v6).
  Trigger: the county forgot the 8am flip — eight ramps (DB-048/051, DBS-067, five NSB)
  stood in the overnight "CLOSED - CLEARED FOR TURTLES" past noon, through a real 8:09am
  2.2 ft peak; the county's own app showed the same. Finding: the exact-string tide match
  means stuck turtle days never taught false closures — the pollution is false "stayed
  open" evidence (close rates, threshold scans, wave pool, open-yesterday persistence
  pairs) plus an unguarded worst case (a stale CLOSED FOR HIGH TIDE would label every
  later peak closed, unbounded). Shipped `predict/stale.go`: a blocking status still
  standing 2h past the posted open marks the ramp-day stale — dropped from labeling in
  training, the persistence prior (Known=false), and the scorecard (new `stale` outcome +
  summary counter, outside graded/recall/precision). Tide episodes keep day 1, quarantine
  later days. Manual backstop: `prediction_excluded_days` settings key (JSON date array,
  county-wide, admin settings POST). Fires on 15 real fixture ramp-days (incl. DBS-075
  7/28 overnight case); backtest floors hold unchanged. 8/26 itself needs no manual
  entry — the heuristic catches it once the county flips. Also resolves the "known label
  noise" caveat in the 8/23 entry. Discount the 8/26 scorecard's morning peak either way.
- 2026-08-23: Period-aware wave regime. 8/22 post-mortem: the quiet morning call
  was right on the height the buoy reported (1.3 ft "calm" until 3:56pm) but the dominant
  period jumped 4 s → 14 s at 10am — a groundswell — and four NS ramps closed at 3:30pm.
  Scorecard graded them covered with the afternoon height, so the engine was blind to
  period, not overfit. Fixture evidence: long-period peaks close 63% vs 50% (Daytona 85%
  vs 53%). Shipped: period ≥ 10 s counts as rough at any height (serve, scorecard,
  weekend marine). Backtest +6 closure days / −20 quiet days, smooth 9–12 s. **Decision
  (Don): review after a week of scorecards; if over-hedging, try "long period only
  disqualifies calm" (+3 / −7) next.** Verified live 8/23 09:40: 1.31 ft @ 13 s → `rough`,
  NS ramps flagged for the 6:30pm 2.6 ft peak. Known label noise: the county sometimes
  forgets to flip a status (NS-118 showed OPEN through 8/22's closure), which feeds the
  persistence prior a wrong "stayed open" — tolerable, but it is why a single day's
  `yesterday.applied` can look off.
- 2026-08-22 (latest, shipped 3312421 + prod force-retrain 13:38Z): Shift scans made grade-aware. Don noticed NS ramps
  still "possible ~3:30" on a calm day after open days; root cause: the wave/persistence
  scans scored a binary closed/open cut, so demoting likely→possible counted as a miss and
  prod learned zero calm raise and zero open-yesterday raise for NS-141/118/110 (five
  straight false alarms). Scans now score the real three-level grade; on prod's station
  scale NS ramps learn a 0.4 ft raise and calm learns 0.45 — today's 2.53 ft peak reads
  "No tide trouble expected". Backtest floors hold; NS-106 recall 0.66 → 0.73. Verified
  live after the retrain: NS-141/118/110 + DBS-075 quiet with `yesterday.applied: true`,
  NSB verdict "All five open". Watch the 2026-08-22 scorecard for misses.
- 2026-08-21 (latest, uncommitted): Persistence prior in the outlook engine — Don's
  insight that whether a ramp closed *yesterday* predicts today better than the tide
  height alone inside the learnable band (fixture data: DBS-075 at ~3.0 ft closes 11%
  after an open day, 100% after a closed one). Per-ramp learned threshold shifts with a
  county-wide fallback (params blob v5), hedge-only asymmetry like the wave model,
  height-anchored carry-forward in the weekend planner, `yesterday` echo in outlook +
  scorecard, one copy clause when it moved the call, `PREDICT_PERSISTENCE_ENABLED`
  kill switch. Backtest: ~95 hedge days on open days → 78 correct quiet calls + 17
  misses; no ramp under its recall floor. Verified locally: NS ramps dropped from
  "likely" to "possible · rode out yesterday's tide", yesterday's false alarms 3 → 0.
- 2026-08-17 (latest): Outlook became a real forecast line. Three shipped changes:
  (a) it decays — a predicted close time the clock has passed is never quoted back at a
  ramp that is still open, peaks stay in play through their learned lag, then soften and
  clear (0b9d091); (b) every string names its cause and the line always looks forward, so
  every hour of the clock has a next-action answer — overnight predicts the morning open,
  a live tide risk tells the tide story, otherwise the driving day's close (64751ec);
  (c) tide closures are always "possible", never "likely". New `reason` field
  (high_tide / end_of_day / overnight) and new `scheduled` risk value — none/possible/
  likely grade the TIDE ONLY and the backtest + scorecard read them that way, which is
  how the first cut got caught. **Finding: the county clears the beach ~6:30pm, not the
  posted turtle-season 7pm** (13 straight days, 6:17–6:47, median 6:32), so the trainer
  now learns the median offset into `day_close_offset_min` and the schedule applies it
  (clamped ±90 min); prod learned −30 on deploy and serves "closes for the day ~6:30pm".
  paramsVersion 2→3 forces the retrain. Web is live; the Apple builds in review show the
  overnight copy (it reuses closed_now) but need a re-flight for the `scheduled`
  end-of-day hint. Residual: a ramp closed mid-day for turtles/capacity has no
  predictable reopen, so that one card still shows a since time.
- 2026-08-16: Beach open/close prediction ("outlook") — validated against
  13,399 history transitions joined to NOAA tides (per-ramp thresholds 2.1–3.85 ft
  MLLW, closures ~90–120 min before peak, reopens ~60–100 min after), then shipped
  as: beach_conditions snapshot logger (30-min tide/wind/NDBC-buoy-wave rows,
  migration 009), Go solar port, NOAA range fetches with 6h TTL cache, nightly
  trainer persisting learned params to settings, outlook engine with casual
  server-built copy (risk hysteresis, county-wide hard cutoffs learned as P05/P97
  of the peak distribution — prod's tide station 8721164 has a different height
  scale than the analysis station 8721147, so nothing is hard-coded — half-hour
  windows, falling-limb reopen estimates), /api/v2/outlook endpoints, and web
  integration (detail band prefers server outlook; board cards show italic hints;
  sw v9). Copy carries approximate clock times by Don's call ("closure likely
  ~1:30pm · often back open by 5pm") — hedged, half-hour rounded, never
  minute-precise. Five-month backtest in CI pins recall and calibration floors.
  All free data sources — zero incremental hosting cost.
- 2026-08-15: iOS/iPadOS redesign from design-review/design_handoff_ios/ —
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
