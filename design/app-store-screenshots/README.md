# App Store screenshots — Volusia Beach Info 1.0

Captured 2026-08-15 on simulators against live prod data (beach.donwb.com —
the sim build points at prod, so ramp statuses, tide, weather, and the live
cam are all real). Raw device captures, no frames or overlay text — the app
is the marketing.

Regeneration (any time): `make screenshots` — see
`apple/scripts/screenshots.sh`. It builds Debug for the simulators, boots
the store-size devices, freezes the sky with the `--sky-minutes` QA hook so
shots are reproducible at any hour, overrides the iOS status bar to 9:41,
and captures with `simctl io screenshot`. Shoot when the board looks good —
"All five open" beats a stormy-day board.

Gotchas the script already encodes (learned the hard way here and on bkmks):

- **iPad landscape can only be reached through the Simulator menu.** The
  app's `--force-landscape` hook is silently ignored on iPad (multitasking
  targets reject `requestGeometryUpdate`), and simctl has no rotate
  command. The script drives Simulator's Window/Device menus via
  osascript — first run may prompt for Automation (System Events)
  permission. `simctl io screenshot` still writes a portrait buffer with
  rotated content; the script counter-rotates with `sips -r 270`.
- **The watch app is a companion app** (`WKCompanionAppBundleIdentifier`,
  no standalone flag): it only launches on a watch sim paired to a phone
  sim carrying the iOS app. The script installs both halves on Xcode's
  default paired set and retries the first launch, which can race the
  fresh-boot springboard/companion handshake.
- `status_bar override` is not supported on watchOS sims — the watch shot
  shows sim time. bkmks shipped the same way.

## iphone-6.9 (1320×2868, iPhone 17 Pro Max)

The three sky phases sell the signature feature — the ground follows the
real sun. Same board, three moods.

1. **01-board-day.png** — full daylight (`--sky-minutes 630`), "All five
   open", tide curve, live cam below the fold.
2. **02-board-golden.png** — GOLDEN EVENING (1170): warm sand gradient.
3. **03-board-dawn.png** — SUNRISE (415): purple-pink dawn board.

Watch item: the header pairs the frozen sky's phase label with the *real*
clock time ("SUNRISE · 3:18 PM" in the current dawn/golden shots). If that
reads wrong in review, recapture those two at the matching real hour (drop
`--sky-minutes` and shoot at actual sunrise/golden hour), or teach the
header to use the override time.

## ipad-13 (iPad Pro 13-inch)

1. **01-board-wide.png** (2752×2064, landscape) — the hero: full wide board
   with conditions rail, tide curve, forecast, and live cam in one frame.
2. **02-board-portrait.png** (2064×2752) — two-column card grid, full-width
   cam.

## appletv (3840×2160, Apple TV 4K 3rd gen)

Captured 2026-08-17. The App Store accepts 1920×1080 or 3840×2160 for tvOS;
the 4K sim writes the larger size, which is what these are.

1. **01-board.png** — the hero: verdict, stat rail, five NSB ramp cards with
   their outlook hints, sun ribbon, live NSB cam, and the coastline camera
   rail along the bottom.
2. **02-tide.png** — tide overlay (`--overlay-tide`): today's curve with the
   now marker and all four extremes.
3. **03-activity.png** — recent changes (`--overlay-activity`). Real county
   data, and the reason this shot is worth including: it shows the morning's
   "Closed — cleared for turtles" run.
4. **04-water.png** — water & air (`--overlay-temp`): both NOAA stations,
   the average the board shows, and the NWS forecast strip.

**No `--sky-minutes` here, on purpose.** The hook moves the sky, the header
clock, and the sun ribbon, but not the verdict subline — ContentView builds
the verdict from a real `Date()` (BeachRampTV/ContentView.swift:282). A
frozen evening board therefore reads "7:30 PM" next to "8h 58m of light
left" and contradicts itself in a store screenshot. Shooting at real
wall-clock time keeps every string agreeing; shoot midday Eastern, when the
board is mixed and the cams are lit. Threading the override into the verdict
would let sky phases come back.

## watch (416×496, Apple Watch Series 11 46mm)

1. **01-glance.png** — glance list: 5/0/0 summary tiles + New Smyrna Beach
   ramps. (watchOS is out of scope for 1.0 — captured for the eventual
   watch release; recapture then.)
