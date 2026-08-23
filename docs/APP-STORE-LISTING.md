# App Store Connect listing — Volusia Beach Info 1.0

Copy-paste sheet for the ASC record (Apple ID 6761724123, bundle ID
`com.donwb.BeachRampTV`, carrying **both** iOS and tvOS). The listing name changes
from the reserved "Beach Ramp Status" to **Volusia Beach Info**.

Every claim below was checked against the live API and the repo on 2026-08-17.
The privacy and support pages are built and ready to deploy; the one open decision
is Content Rights. See "Before you submit" at the bottom.

---

## App Information (set once for the record)

| Field | Value |
|---|---|
| **Name** | `Volusia Beach Info` |
| **Subtitle** | `Live ramp status, tides & cams` |
| **Primary language** | English (U.S.) |
| **Bundle ID** | com.donwb.BeachRampTV |
| **SKU** | `beach-ramp-status` (any unique string; not user-visible) |
| **Primary category** | Weather |
| **Secondary category** | Travel |
| **Content rights** | Yes — contains third-party content (your call, see below) |
| **Age rating** | 4+ (all questionnaire answers "None" / No) |
| **License agreement** | Apple's standard EULA |
| **Made for Kids** | No |
| **Privacy Policy URL** | `https://beach.donwb.com/privacy` |

**Subtitle alternates** (30-char limit, all fit):
- `Live ramp status, tides & cams` — 30 (recommended)
- `Ramp status, tides & beach cams` — 31, one over; drop "beach" to use it
- `Every ramp, the tide, the cams` — 29

The subtitle now has to carry "ramp" and "status", since the name no longer does.
"Volusia", "beach", and "info" are indexed from the name, so don't repeat them.

**On name proximity to the county's app.** "Volusia Beaches" is the county's own
Flutter app (and the name of the YouTube channel four of the five cams come from),
which is why that name is out. "Volusia Beach Info" is clearly distinct as a string,
but it still sits next to theirs in a search results list, and Apple's copycat rule
(4.1) and metadata rule (2.3.8) both live in that neighborhood. Two things already
work in your favor: the description and support page both carry an explicit "not
affiliated with or endorsed by Volusia County" line, and the icon and screenshots
look nothing like theirs. Worth a glance at their listing before you submit, to be
sure nothing else reads as an imitation.

---

## Version metadata — iOS / iPadOS 1.0

### Promotional text (170 max — editable later without a new build)

```
Live status for all 27 Volusia County beach ramps, plus tides, water temp, weather, and five live beach cams — refreshed every minute. Free, no account, no ads.
```

### Description (4000 max)

```
Can you drive on the beach right now? Volusia Beach Info answers that in one glance.

Volusia County opens and closes its beach access ramps all day long — high tide, weather, erosion, events. This app watches the county's own live feed and shows every ramp's status the moment it changes, along with the tide, the water temperature, the forecast, and a live look at the beach itself.

WHAT YOU GET

• Every ramp, every status — all 27 county access ramps from Ormond Beach down to New Smyrna Beach, marked open, limited, or closed, checked against the county feed every minute.
• Filter by city — Ormond Beach, Daytona Beach, Daytona Beach Shores, Ponce Inlet, and New Smyrna Beach.
• Tide chart — today's highs and lows, which way the tide is running, and how far along it is.
• Water and weather — water temperature from NOAA coastal stations, current conditions and the forecast from the National Weather Service.
• Live beach cams — five cameras up and down the coast. Turn your phone sideways for full screen.
• Closure outlook — the app learns how each ramp behaves around high tide and says when one is likely to close, in plain language: "closure likely around 1:30pm."
• Ramp history — when each ramp opened or closed, and what it's been doing today.
• Widgets — the board on your Home Screen or Lock Screen, in every size.
• A sky that follows the sun — the screen shifts from dawn purple through midday blue to golden evening, tracking the real sunrise and sunset where you're standing.

FREE, AND IT STAYS THAT WAY

No account. No sign-in. No ads. No tracking and no analytics — nothing about you is collected or uploaded. The app downloads public beach data and shows it to you.

WHERE THE DATA COMES FROM

Ramp status: Volusia County's public GIS feed. Tides and water temperature: NOAA. Weather: the National Weather Service. Beach cams: public live cameras along the Volusia coast.

Volusia Beach Info is an independent app and is not affiliated with or endorsed by Volusia County. Conditions on the beach change fast — always follow posted signs and the direction of Beach Safety officers on scene.
```

### Keywords (100 max, comma-separated, no spaces after commas)

```
daytona,new smyrna,ormond,ponce inlet,driving,webcam,water temp,surf,forecast,access,high tide
```

94 characters. Deliberately excludes "volusia", "beach", and "info" (in the name) and
"ramp", "status", "tides", and "cams" (in the subtitle) — Apple indexes every word
in both, so repeating them wastes the budget.

### URLs

| Field | Value |
|---|---|
| **Support URL** | `https://beach.donwb.com/support` |
| **Marketing URL** | `https://beach.donwb.com` |
| **Privacy Policy URL** | `https://beach.donwb.com/privacy` |
| **Version** | `1.0` |
| **Copyright** | `2026 Don Browning` |
| **What's New** | n/a — first version, field not shown |

### Build

Select **build 1.0 (18)**, not 17 — see Blockers.

---

## Version metadata — tvOS 1.0

### Promotional text

```
The whole Volusia beach board on your TV: all 27 access ramps, tides, water temp, the forecast, and five live beach cams. Refreshed every minute. Free, no account.
```

### Description

```
The beach board, on your TV.

Volusia County opens and closes its beach access ramps all day long. Volusia Beach Info puts the whole board on the big screen: all 27 ramps from Ormond Beach down to New Smyrna Beach, marked open, limited, or closed, refreshed from the county's own feed every minute.

Alongside the board — today's tide chart, water temperature, and the National Weather Service forecast.

And five live beach cameras, arranged along a stylized map of the coast: pick a spot from Ormond Beach to New Smyrna and watch it full screen.

Free. No account, no sign-in, no ads, and nothing about you is collected.

Ramp status comes from Volusia County's public GIS feed; tides and water temperature from NOAA; weather from the National Weather Service; the cams are public live cameras along the Volusia coast.

Volusia Beach Info is an independent app and is not affiliated with or endorsed by Volusia County. Always follow posted signs and the direction of Beach Safety officers on scene.
```

### Keywords

```
daytona,new smyrna,ormond,ponce inlet,driving,webcam,water temp,coast,live cam
```

77 characters. ("surf" and "forecast" swapped for "coast" and "live cam" — tvOS
search is thinner and screensaver-adjacent live-view terms carry more weight there.)

Support URL, Marketing URL, Copyright, Version: same as iOS.

---

## Version metadata — iOS / iPadOS 1.1 (build 26, drafted 2026-08-21)

Context: the 2026-08-21 parity pass brought the phone and iPad up to the web and
tvOS feature set (weekend outlook, server-built city verdict, surf line, forecast
strip, recent changes) and pulled favorites in favor of "Pin to widget". Flighted
as 1.1 (26), iOS only — tvOS 1.1 (25) is already in review. Screenshots: the
existing iPhone 6.9" / iPad 13" sets still match the board; recapture only if the
review asks. Note the 1.0 description quoted "closure likely around 1:30pm" —
the product rule is that a tide closure is always *possible*, never *likely*, so
the 1.1 copy says so.

### What's New in This Version

```
The board now plans ahead.

• When should I go? — the next seven days, each graded for the beach with the best driving window, closure risk, high, rain chance, and wind. Saturday and Sunday first.
• One verdict, every screen — the headline for your city is now the same on the phone, the iPad, the TV, and the website, right down to "Driving is done for today" after the evening sweep.
• Surf, in a sentence — the buoy read for Ponce Inlet with height, period, rip current risk, and how fresh it is.
• Forecast and recent changes on the iPhone board, not just the iPad.
• Pin to widget — choose the ramps your Home Screen widget shows from the ramp's own screen.

Ramp status still comes straight from the county's feed, refreshed every minute. Free, no account, nothing collected.
```

(≈780 characters; limit 4000.)

### Description (redrafted for 1.1)

```
Can you drive on the beach right now? Volusia Beach Info answers that in one glance — and tells you when to come back.

Volusia County opens and closes its beach access ramps all day long — high tide, turtles, weather, crowds. This app watches the county's own live feed and shows every ramp's status the moment it changes, with the tide, the water temperature, the forecast, the surf, and a live look at the beach itself.

WHAT YOU GET

• Every ramp, every status — all 27 county access ramps from Ormond Beach down to New Smyrna Beach, marked open, limited, or closed, checked against the county feed every minute.
• A plain-English verdict for your city — "Five for five", "Two of eight open", "Driving is done for today" — the same line on every device.
• What's likely next — the app learns how each ramp behaves around high tide and says when a closure is possible, in plain language: "tide closure possible ~2:30pm", or simply the end of the driving day.
• When should I go? — the next seven days graded for the beach: best driving window, closure risk, high, rain chance, wind.
• Tide chart — today's highs and lows and which way the tide is running.
• Water, weather, surf — water temperature from NOAA, the forecast from the National Weather Service, and the Ponce Inlet buoy's surf read with rip current risk.
• Live beach cams — five cameras up and down the coast. Turn your phone sideways for full screen.
• Ramp history — today's timeline and the last 48 hours of changes for every ramp.
• Widgets — the board on your Home Screen or Lock Screen, in every size; pin the ramps you care about.
• A sky that follows the sun — the screen shifts from dawn purple through midday blue to golden evening, tracking the real sunrise and sunset.

FREE, AND IT STAYS THAT WAY

No account. No sign-in. No ads. No tracking and no analytics — nothing about you is collected or uploaded. The app downloads public beach data and shows it to you.

WHERE THE DATA COMES FROM

Ramp status: Volusia County's public GIS feed. Tides and water temperature: NOAA. Weather: the National Weather Service. Surf: the NOAA Ponce Inlet buoy. Beach cams: public live cameras along the Volusia coast. Closure outlooks are estimates learned from past county closures — the county makes the call.

Volusia Beach Info is an independent app and is not affiliated with or endorsed by Volusia County. Conditions on the beach change fast — always follow posted signs and the direction of Beach Safety officers on scene.
```

Promotional text, keywords, URLs, copyright: unchanged from iOS 1.0.

---

## Version metadata — tvOS 1.1 (build 25, drafted 2026-08-21)

Context: 1.0 (18) was approved; ASC closed the 1.0 train, so the video-first
board ships as 1.1. Screenshots: `design/app-store-screenshots/appletv/`
(recaptured 2026-08-21 from build 25). The 1.0 tvOS description below is
stale — it describes the retired band/tile design ("stylized map of the
coast", "watch it full screen") — so the description is redrafted here too.

### What's New in This Version

```
A new board, built around the beach itself.

• The live cam is now the picture: a wide panorama across the top of the screen that nothing ever covers. Flip between five Volusia cams — New Smyrna, Ponce Inlet, Dunlawton, Ormond Beach, Ormond-by-the-Sea — with the remote.
• Below it, the ledger: a plain-English verdict for your city, every ramp with what's likely to happen next ("tide closure possible ~2:30pm"), the surf right now, and the best driving windows this weekend.
• Beach outlook: a 7-day table of highs, rain, surf, best window, and closure risk.
• Ramp detail: pick a ramp for today's timeline, the tide against that ramp, and its last 48 hours of changes.
• The sky behind it all follows the real sun over New Smyrna, dawn to dark.

Ramp status still comes straight from the county's feed, refreshed every minute. Free, no account, nothing collected.
```

(≈820 characters; limit 4000.)

### Description (redrafted for 1.1)

```
The beach, on your TV.

Volusia County opens and closes its beach access ramps all day long — for the tide, for turtles, for crowds. Volusia Beach Info puts the live beach and the whole board on the big screen.

Across the top: a live beach cam panorama, never covered. Five cameras from Ormond-by-the-Sea down to New Smyrna Beach, one remote press apart.

Below it, the ledger: a plain-English verdict for your city ("Wide open — all five"), every ramp marked open, limited, or closed, and what's likely to happen to it next — a tide closure possible around 2:30pm, or simply the end of the driving day. Plus the surf right now and the best driving windows this weekend.

Press in for more. Beach outlook is a 7-day table — highs, rain, surf, best window, closure risk. Ramp detail shows today's timeline, the tide against that ramp, and its last 48 hours of changes.

The sky behind the board follows the real sun over New Smyrna Beach, dawn to dark.

Free. No account, no sign-in, no ads, and nothing about you is collected.

Ramp status comes from Volusia County's public GIS feed, refreshed every minute; tides and water temperature from NOAA; weather from the National Weather Service; surf from the Ponce Inlet buoy; the cams are public live cameras along the Volusia coast. Closure outlooks are estimates learned from past county closures — the county makes the call.

Volusia Beach Info is an independent app and is not affiliated with or endorsed by Volusia County. Always follow posted signs and the direction of Beach Safety officers on scene.
```

Promotional text, keywords, URLs, copyright: unchanged from tvOS 1.0.

---

## App Privacy (nutrition label)

**Answer: "Data Not Collected."**

Verified in the repo:
- No analytics or telemetry SDK anywhere in `apple/` — nothing imported, nothing sent.
- No account, sign-in, or user identity of any kind.
- No CoreLocation, camera, photo library, contacts, or tracking-permission usage.
- Caching is local (SwiftData); the apps only ever issue GETs against public endpoints.
- The server-side page-view log added in `da19c4e` matches **HTML page paths only**
  (`/`, `/county`, `/ramp/:id`, …) — `/api/v2/*` never matches, so the apps
  generate no rows. The claim holds.

Tracking question: **No**, the app does not track.

---

## App Review Information

| Field | Value |
|---|---|
| **Sign-in required** | No |
| **Demo account** | Not needed |
| **Contact** | Don Browning · don.browning@gmail.com · (phone) |

### Notes (paste this — it heads off the two most likely rejections)

```
No account or sign-in is required. Every screen is available immediately on launch.

Two things that may look like defects but are correct behavior:

1. Beach driving in Volusia County is only permitted from sunrise to sunset. If the app is reviewed at night Eastern Time, every ramp will correctly show CLOSED and the board will look empty. Reviewing between roughly 9am and 5pm Eastern shows the board in its normal mixed open/limited/closed state.

2. All content is live from public sources — Volusia County's GIS feed, NOAA, and the National Weather Service. Ramp statuses, tide, and weather will not match the screenshots; the screenshots are genuine captures taken on other days and at other times of day.

The live beach cameras are public webcams along the Volusia County coast, delivered over HLS from cams.donwb.com.

Contact: don.browning@gmail.com
```

**Export compliance:** nothing to answer — `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`
is baked into `Version.xcconfig`, so ASC won't ask.

---

## Pricing and Availability

| Field | Value |
|---|---|
| **Price** | Free (Tier 0) |
| **Availability** | All countries and regions |
| **Distribution** | Public — App Store |
| **Pre-orders** | No |

The app is only useful in Volusia County, but there's no upside to restricting
territories — it just adds a thing to maintain.

---

## Screenshots

| Platform | Required | Have |
|---|---|---|
| iPhone 6.9" (1320×2868) | yes | ✅ 3 shots — `design/app-store-screenshots/iphone-6.9/` |
| iPad 13" (2064×2752 / 2752×2064) | yes (device family is 1,2) | ✅ 2 shots — `design/app-store-screenshots/ipad-13/` |
| Apple TV (1920×1080 or 3840×2160) | yes | ⚠️ only `slides/screenshots/apple tv screenshot.png`, March 2026 — predates the tvOS redesign |
| Apple Watch | no | n/a — watchOS is out of scope for 1.0 |

App icons come from the build's asset catalog; nothing to upload.

**One thing to look at before uploading the iPhone shots:** per
`design/app-store-screenshots/README.md`, the two sky-phase shots pair a frozen sky
label with the real capture clock — "SUNRISE · 3:18 PM". A reviewer reading that as
a bug is unlikely but possible, and it reads wrong to a customer either way. Either
recapture those two at the matching real hour, or lead the gallery with
`01-board-day.png`, which has no mismatch.

---

## Before you submit

**1. Privacy Policy URL — DONE, pending deploy.** `web/privacy/index.html` is built
and serves at `/privacy`, styled to match the `/county` page and dark-mode aware. It
states the honest position: nothing collected by the apps, and it discloses the two
things that are true anyway — the website's server-side page-view log, and the fact
that watching a cam means cams.donwb.com sees the request.

**2. Support URL — DONE, pending deploy.** `web/support/index.html` serves at
`/support`: contact address, what open/limited/closed mean, why everything reads
closed overnight, what the closure outlook is and isn't, and the not-affiliated
notice. Both pages are linked from the board footer.

Both go live on the next push to main (auto-deploy). Verify they load before you
paste the URLs into ASC — Apple checks them.

**3. Content Rights — still yours to decide.** ASC asks whether the app contains
third-party content and has you attest you have the rights. The cams are public
YouTube live streams from other operators
(`api/migrations/004_create_cameras.up.sql`), pulled by the home restreamer and
re-broadcast through your relay at `cams.donwb.com`. You said you'd handle this one.

---

## Two decisions the name change opened up — both RESOLVED 2026-08-23

**The name under the icon.** `Version.xcconfig` now sets
`INFOPLIST_KEY_CFBundleDisplayName = Beach Info`. The full "Volusia Beach Info" is 18
characters and truncates hard on the iPhone Home Screen — roughly "Volusia Bea…" — so
the icon carries the short form, which shares two of three words with the listing
instead of the one word "Beach Ramps" shared. Takes effect on the next flight; builds
already on TestFlight still read "Beach Ramps".

**The website is now branded "Volusia Beach Info" too.** The board wordmark, the
`index.html` title, the PWA manifest (`short_name` is "Beach Info", matching the icon
label), the `/county` pitch page, and the per-view document titles all carry the
product name, alongside the `/privacy` and `/support` pages that already did. The
in-app wordmark on iOS, iPadOS, and tvOS says "Volusia Beach Info" as well. One name
everywhere.

---

## One more thing: ship build 18, not 17

`Version.xcconfig` reads `CURRENT_PROJECT_VERSION = 18` in the working tree (bumped,
uncommitted). Build **17** is what PORTFOLIO-STATUS records as being on TestFlight,
and 17 predates two things that are on main now: iOS/iPadOS consumption of the
`/outlook` endpoint (the closure-prediction copy the description above promises) and
the iPad inline camera chips. Submitting 17 would ship a listing that describes
features the binary doesn't have. Confirm what's actually in TestFlight, and re-flight
if 18 didn't complete.
