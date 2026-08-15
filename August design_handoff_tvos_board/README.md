# Handoff: tvOS ambient board redesign — Beach Ramp Status

## Overview

A redesign of the tvOS dashboard (`apple/BeachRamp/BeachRampTV/`). The board keeps its
existing composition — one hero cam, one ramp grid, one coastline rail — and changes four
things:

1. **A verdict band above the ramp grid** that answers "can I get on the beach right now?"
   in one line, before the grid is read.
2. **Status carried by the tile field, not by tinted text.** Open tiles go quiet, limited
   and closed become solid amber/red fields, so the tile that matters is the only loud
   thing on screen.
3. **Sixteen sun phases instead of seven**, adding the three twilights at each end of the
   day. Same interpolation model, more anchors.
4. **Designed states for stale data, cam offline, and ramp-closing-soon**, plus the
   three stat tiles becoming focusable detail views (tide / water & air / wind).

The Recent Activity log moves off the board entirely and lives behind Menu.

## About the design files

The files in this bundle are **design references created in HTML** — prototypes showing
intended look and behavior. They are **not production code to copy**.

The target for this work is the existing **SwiftUI tvOS target**, `BeachRampTV`. The task
is to recreate the design in that codebase using its established patterns: `SkyPalette` /
`TVTheme.swift` for color, `ContentView.swift` for layout, SF Symbols for icons, the
shared `BeachStatus` package for models, and `FlatFocusButtonStyle` for focus chrome.
Do not introduce new dependencies or a new styling approach.

`tvOS Board.dc.html` is the board mock. Open it in a browser; the Tweaks values named
below are exposed as props at the top of the file (`data-props` on the
`<script data-dc-script>` tag) and can be edited there:

- `timeMinutes` — 0–1439, scrubs the sun through all 16 phases
- `scenario` — `All open` | `Beachway closing soon` | `Crawford closed` | `Stale data` | `Cam offline`
- `detailPanel` — `None` | `Tide` | `Water & air` | `Wind`
- `showActivity` — opens the Recent-changes overlay

`Design Review - Beach Ramp Status.dc.html` is the 16-slide critique that motivated the
redesign, including the findings about the current code. Worth reading slides 6–8.

## Fidelity

**High fidelity.** Colors, type sizes, spacing and layout are final and should be matched.
Every value in this README is measured from the mock, and the mock is authored at
**1920×1080** — the same logical coordinate space tvOS uses — so **px in the mock maps 1:1
to points in SwiftUI**. A 38px name in the mock is `.font(.system(size: 38))`.

The one thing that is *not* final: the cam banner in the mock is a static crop of a live
frame (`review/cam-banner.png`), standing in for `TVVideoPlayerView`. Keep the existing
player.

---

## Screen: the board

**Purpose.** Ambient display, left on for hours. Read from across a room. Answers
"can I get on, and what is the tide doing," then acts as a beach cam.

### Layout

Root `ZStack`:

1. Sky gradient, `ignoresSafeArea()` — `LinearGradient(topLeading → bottomTrailing)`,
   three stops from the current phase (see Sun phases).
2. Board content.
3. Night dimming scrim — `Color.black.opacity(1 - dimming)`, `allowsHitTesting(false)`.
4. Overlays (activity, three detail panels) — opaque, full-bleed.

Board content is a `VStack(spacing: 0)` with `padding(.horizontal, 60)`,
`padding(.top, 56)`, `padding(.bottom, 52)`. Content width is therefore **1800**.

Vertical budget, top to bottom (heights in points, gaps as `padding(.top, …)`):

| Block | Height | Gap above |
|---|---|---|
| Top bar | 56 | — |
| Verdict band | ~150 (intrinsic) | 22 |
| Ramp grid | 184 | 26 |
| Sun ribbon + labels | ~72 | 22 |
| Cam banner | fills remainder (~372) | 20 |
| Coastline rail | ~60 | 16 |

The cam banner takes the remaining height (`frame(maxHeight: .infinity)`), so growing any
block above it shortens the cam rather than overflowing. Source aspect is **1280×270
(4.74:1)** — reserve it, do not letterbox to 16:9.

### Top bar

`HStack`, height 56, `alignment: .center`.

- **Left — city chip.** `Text(city)` at 38pt weight `.bold`, letter-spacing −0.01em, then
  `Image(systemName: "chevron.left.chevron.right")` at 22pt, opacity 0.6, gap 14.
  Padding 8 vertical / 16 horizontal. Fill `Color.white.opacity(0.10)`, border
  `2pt Color.white.opacity(0.28)`. **Zero corner radius.** Reuse `FlatFocusButtonStyle`
  with `cornerRadius: 0`.
- **Right — freshness chip, then clock.** Gap 24.
  - Freshness chip: a 14×14 circle, then `Text` at 24pt weight `.semibold`,
    letter-spacing 0.04em, gap 12, padding 8/16, 2pt border.
    - Live: label `Live`, dot `#2AE07A`, fill `white.opacity(0.10)`, border `white.opacity(0.28)`
    - Stale: label `Stale · 14 min`, dot `#F5A214`, fill `rgba(245,162,20,0.22)`, border `#F5A214`
  - Clock: 38pt weight `.regular`, `.monospacedDigit()`.

### Verdict band

`HStack(alignment: .top, spacing: 48)`, columns weighted **1.55 : 1**.

**Left column** — `VStack(alignment: .leading, spacing: 14)`:

- Row: a **22×76 solid rectangle** in the verdict accent color, then the headline —
  84pt weight `.bold`, line-height 0.92, letter-spacing −0.02em, gap 20. The bar is what
  makes the headline readable at distance before the words resolve; it is not decoration.
- Subline: 34pt weight `.regular`, line-height 1.25, opacity 0.92,
  `padding(.leading, 42)` so it aligns to the headline's text edge, not the bar's.

| Scenario | Accent | Headline | Subline |
|---|---|---|---|
| All open | `#2AE07A` | All five open | Tide dropping · low 4:57 PM · 5h 41m of light left |
| Crawford closed | `#E63A2B` | Crawford Rd closed | Four open · closed for high tide since 12:48 PM · reopens near 6:30 PM |
| Beachway closing soon | `#F5A214` | Beachway closing soon | High tide 4:57 PM · entrance only since 11:15 AM · four others fully open |
| Stale data | `#F5A214` | Last known: five open | County feed unreachable for 14 minutes · retrying every 60s · do not trust this board |

Headline copy is generated, not literal — the rule is: name the exception if there is one,
otherwise state the count. Never lead with a number alone.

**Right column** — three stat tiles, `LazyVGrid` / `HStack` of 3 equal columns, spacing 20.

Each tile: padding 12 vertical / 16 horizontal, fill `white.opacity(0.06)`,
border `2pt white.opacity(0.22)`, zero radius. `VStack(alignment: .leading, spacing: 8)`:

1. Header row, `HStack` with `Spacer()`: label 22pt, letter-spacing 0.08em, uppercase,
   opacity 0.7 — then a `chevron.right` at 24pt, opacity 0.55.
2. Value: 40pt weight `.bold`, line-height 1.0.
3. Detail: 24pt, opacity 0.75.

| Tile | Label | Value | Detail |
|---|---|---|---|
| 1 | TIDE | Dropping | Low 4:57 PM |
| 2 | WATER · AIR | 82° · 89° | Mostly clear |
| 3 | WIND | ENE 9 | Sat 93° |

**Focus.** These are `Button`s using the existing `FlatFocusButtonStyle` with
`cornerRadius: 0`: fill `0.06 → 0.26` and border `0.22 → 1.0` on focus, `scaleEffect 0.97`
on press, **no focus scaling**. Selecting one opens its detail panel.

### Ramp grid

`LazyVGrid` with **5 flexible columns**, spacing 16, row height **184**.

For counties/cities with more ramps, use `GridItem(.adaptive(minimum: 330))` so the row
wraps rather than crushing names.

Order is explicit, not API order. **New Smyrna Beach: Beachway Av, Crawford Rd, Flagler Av,
3rd Av, 27th Av.** Other cities may fall back to roster order. Tiles are numbered 01–05 so
the ordering reads as deliberate.

Each tile: `VStack(alignment: .leading)` with `Spacer()` between two groups, padding 16
vertical / 18 horizontal, **2pt border, zero corner radius**, `frame(maxWidth: .infinity,
alignment: .leading)`.

Top group, spacing 6:
- Index: 22pt, letter-spacing 0.08em, uppercase, opacity 0.65
- Ramp name: 38pt weight `.bold`, line-height 1.02, letter-spacing −0.01em.
  **Wrap to two lines, do not truncate** — `International Speedway Blvd` must fit.

Bottom group, spacing 4:
- Status row, `HStack(spacing: 10)`: a **14×26 solid rectangle mark**, then the status
  string at 28pt weight `.bold`, line-height 1.1
- Since line: 22pt, opacity 0.7 — e.g. `since 6:02 AM`, `since Yest 4:11 PM`

**Status is carried by the field and the mark, never by tinted text.** This is the
central fix: a saturated green word on a near-transparent fill measures ~1.3:1 against the
noon sky. All three states set their text at full contrast against their own field.

| State | Fill | Border | Text | Mark | Extra |
|---|---|---|---|---|---|
| Open | `rgba(4,24,34,0.55)` | `white.opacity(0.30)` | `#FFFFFF` | `#2AE07A` | — |
| Limited | `#F5A214` | `#F5A214` | `#241500` | `#241500` | outer glow `0 0 0 6 rgba(0,0,0,0.18)` |
| Closed | `#E63A2B` | `#E63A2B` | `#FFFFFF` | `#FFFFFF` | outer glow `0 0 0 6 rgba(0,0,0,0.18)` |

Open's field is a deep translucent ink: white type clears ~7:1 and the green mark ~4:1
against the noon sky, and both improve as the sky dims. Tune against the **noon** palette,
never night.

Stale scenario: every tile drops to `opacity 0.42` and its since line becomes
`as of 2:09 PM`.

### Sun ribbon

Replaces `DayTimelineBar`'s capsule with a **flat 18pt bar, zero radius**, full content
width, gradient left-to-right across the 24-hour day. Stops (position % of day → color)
follow the phase table:

```
0% #070A14 · 4% #080C1A · 7% #0C1230 · 9.5% #142046 · 12% #1B2A52 · 16% #17456B
24% #0E6E8C · 36% #0E779A · 56% #0E7FA8 · 62% #0F7294 · 69% #10657F · 76% #145066
83.6% #123A52 · 86% #0E2840 · 88.5% #0A1228 · 92% #080D1C · 100% #070A14
```

Positions are derived from the day's real solar events — compute them from
`SunTimeline` rather than hard-coding, exactly as `DayTimelineBar.gradientStops` already
does.

Now marker: a **4×32 white rectangle** at `nowFraction`, offset −7 vertically, plus a
**14×14 circle** in `#FF4438` with a `2pt white.opacity(0.9)` stroke, 26 below the bar.

Labels below, 26 gap, `HStack` with `Spacer()`s: `Sunrise 6:51 AM` (leading) ·
caption at 22pt weight `.semibold` (center) · `Sunset 8:04 PM` (trailing). All 22pt,
opacity 0.8. Caption text reuses the existing `DayTimelineBar.captionText` phase logic;
when data is stale it reads `Sun data local — unaffected`, because the sun is computed
locally and stays trustworthy when the feed does not.

### Cam banner

`TVVideoPlayerView` unchanged, filling the remaining height, **zero corner radius**
(currently 10 and 16 — drop both).

Bottom-left status chip, flush to the corner: 12×12 circle then a label at 22pt weight
`.semibold`, letter-spacing 0.04em, gap 12, padding 10 vertical / 18 horizontal, fill
`rgba(6,18,28,0.62)`.

- Live: dot `#E63A2B`, label `Live · New Smyrna Beach`
- Offline: dot `#F5A214`, label `Offline`

### Cam offline state

Replaces the current 22pt `video.slash` glyph at 30% white — invisible from a couch.

The banner becomes an **opaque flat field**, `#0A1420`, filling the same rect.
`VStack(alignment: .leading, spacing: 14)`, centered vertically,
`padding(.horizontal, 56)`:

- `New Smyrna Beach cam offline` — 44pt weight `.bold`, letter-spacing −0.01em
- `Reconnecting — last frame 3:12 PM. Four other cams are live; press right.` — 28pt,
  opacity 0.85

Name the cam, state when the last frame was, say what to do. The existing recovery
machinery — `PlayerFailureObserver`, the 15-second `PlayerStallWatcher`, URL
re-resolution — is correct and stays; this only makes it visible.

### Coastline rail

Keep `CoastlineRail`'s geography, restyle the pins as flat rules. `HStack` of equal
columns across 1420 max width; each column is `VStack(alignment: .leading, spacing: 6)`:
a name at 22pt then a full-width rule.

- Inactive: name opacity 0.55, rule **2pt** `white.opacity(0.28)`
- Active: name weight `.bold` full opacity, rule **4pt** solid white

Order left→right is north→south, matching `CoastlineRail.coastPosition`:
Ormond-By-The-Sea, Ormond Beach, Dunlawton, Ponce Inlet, New Smyrna Beach.

Right of the rail, a Menu affordance: `☰ Recent changes` at 22pt, opacity 0.6, 32 gap.

---

## Overlays

All four overlays are **opaque flat fields**, `#0A1420`, full-bleed. Not scrims — at any
usable alpha the board's own type shows through and collides with the panel's.

Layout is shared: `padding(.horizontal, 120)`, vertically centered, content width 1560,
flush left. Structure is always kicker → title row → 2pt rule → body → footnote.

- Kicker: 22pt, letter-spacing 0.08em, uppercase, opacity 0.65
- Title: 72pt weight `.bold`, letter-spacing −0.02em, line-height 1.0
- Right of title, baseline-aligned: a 34pt line at opacity 0.85
- Rule: `2pt white.opacity(0.4)`, 24 above
- Footnote: 22pt, opacity 0.6, 26 above — always names the data source and
  `press Menu to close`

### Recent changes (Menu)

Kicker `Recent changes · New Smyrna Beach`, title `Today` at 56pt.

Rows: `LazyVGrid` 3 columns `180 / 1fr / 1fr`, gap 32, padding 22 vertical,
`1pt white.opacity(0.22)` separator, `2pt white.opacity(0.4)` on the last. All 30pt;
time column `.monospacedDigit()` at opacity 0.75, ramp name weight `.bold`, status
regular.

Footnote: `Press Menu to close · the board never shows this unprompted`.

This is the only place the activity feed appears on tvOS. The per-tile `since` line
answers the common case — "when did that ramp close?" — without opening anything.

### Tide detail

Title `Dropping` / `Rising`; right line is live: `Next low 4:57 PM · in 3h 27m`,
recomputed from the current time against the day's predictions.

Chart: SwiftUI `Charts`, 1560×340 viewport, `TOP: 20`, `BOT: 270`, y mapped over
−0.5…3.2 ft. Sample every 10 minutes across 24 hours, cosine-interpolated between
consecutive NOAA extremes:

```
h(t) = h₀ + (h₁ − h₀) · (1 − cos(π · u)) / 2,  u = (t − t₀) / (t₁ − t₀)
```

- Zero line: `2pt white.opacity(0.25)` at y 270
- Area fill: `white.opacity(0.12)`
- Curve: `5pt` solid white
- Now line: `4pt #F5A214`, full height

Below, 4 equal columns, gap 24, each `2pt white.opacity(0.4)` top rule + 16 padding:
kicker (`LOW`/`HIGH`) at 22pt / time at 40pt `.bold` / height at 24pt opacity 0.7.
Captured day: Low 4:40 AM −0.1 ft · High 10:44 AM 2.8 ft · Low 4:57 PM −0.1 ft ·
High 11:07 PM 2.8 ft.

Footnote: `NOAA station 8721164 · predictions, not observations · press Menu to close`.

### Water & air detail

Title `Water 82° · Air 89°`, right line `Mostly clear`.

Three stations, 3 columns gap 24: kicker 22pt / value 52pt `.bold` / source 22pt
opacity 0.7. Trident Pier 82° (Station 8721604 · Port Canaveral) · Mayport 83°
(Station 8720218 · Bar Pilots Dock) · Average 82° (What the board shows). Showing both
stations makes it visible where the averaged number comes from.

Second `2pt` rule, 30 above. Then all six NWS forecast periods, 6 columns gap 20:
period name 22pt opacity 0.65 / temp 44pt `.bold` / description 22pt opacity 0.75
line-height 1.3.

Footnote: `NOAA water temperature · NWS api.weather.gov · press Menu to close`.

### Wind detail

Title `ENE 9 mph`, right line `Onshore · 67°`.

Direction axis rather than a compass rose — it matches the board's existing
position-on-a-line vocabulary (sun ribbon, coastline rail) and reads better at distance.
An 18pt bar, `linear-gradient(white 0.10 → 0.34 → 0.10)`, with a **4×34 `#F5A214`
marker** at `degrees / 360` (ENE 67.5° → 18.75%). Labels below at 24pt opacity 0.75,
evenly spaced: N NE E SE S SW W NW N.

Second `2pt` rule, 34 above. Then wind by forecast period, 6 columns gap 20: period 22pt
opacity 0.65 / speed 40pt `.bold` / direction 24pt opacity 0.75.

Footnote: `NWS api.weather.gov · mph · press Menu to close`.

---

## Interactions & behavior

- **Stat tile → detail panel.** Focus with the remote, Select opens. Menu closes. In the
  HTML mock, click opens and click-anywhere closes.
- **Menu on the board** opens Recent changes. Menu again closes.
- **Coastline rail** keeps today's channel-flip feel: moving focus across pins switches
  the live stream (`onChange(of: focusedCamera)` → `selectCamera`).
- **Sky transitions** stay `.easeInOut(duration: 2.0)` driven by `sunAltitude`, on the
  existing 30-second tick.
- **Now marker** stays `.easeInOut(duration: 1.0)` on `nowFraction`.
- **Focus** never scales. `FlatFocusButtonStyle` already does this; extend it to the stat
  tiles with `cornerRadius: 0`.

## State

Additions to `TVViewModel` / `ContentView`:

| State | Type | Notes |
|---|---|---|
| `detailPanel` | `enum { none, tide, temp, wind }` | which overlay is open |
| `showActivity` | `Bool` | Recent-changes overlay |
| `dataAge` | `TimeInterval` | drives the freshness chip and tile muting |
| `activity` | `[RampChange]` | today's changes; needs an API surface if none exists |
| `rampOrder` | `[String: [String]]` | explicit per-city ordering; NSB as above |

`errorMessage` is no longer rendered as an 18pt line. Stale is expressed by the header
chip, the muted tiles, and the verdict subline.

## Design tokens

**Status.** Retuned to hold against the sky at both ends of the day. Replaces the
`tvStatus*` triple; the values differ from iOS's `statusOpen/#10B981` family, so unify
both in `BeachStatus` rather than keeping two sets.

```
open     #2AE07A
limited  #F5A214
closed   #E63A2B
```

**Sky phases.** Nine on the rising track, seven falling; night and noon shared so the
flip at the solar extremes stays seamless. Keyed on sun altitude in degrees, same
`SkyPalette.forSun(altitude:isRising:)` interpolation as today.

Rising:

| Phase | Alt | Top | Mid | Bottom | Dim |
|---|---|---|---|---|---|
| Night | −18 | `#070A14` | `#101830` | `#1C2A44` | 0.55 |
| Astronomical dawn | −13 | `#080C1A` | `#141C38` | `#26304E` | 0.58 |
| Nautical dawn | −9 | `#0C1230` | `#22265A` | `#3E3A6B` | 0.64 |
| Civil dawn | −5 | `#142046` | `#4A4478` | `#8E6A82` | 0.74 |
| Sunrise | −0.8 | `#1B2A52` | `#6A5C8E` | `#F2B07A` | 0.85 |
| Golden morning | 6 | `#17456B` | `#3E7C9E` | `#F0C48E` | 0.92 |
| Morning | 20 | `#0E6E8C` | `#1F9BBF` | `#9CD8E8` | 1.00 |
| Late morning | 34 | `#0E779A` | `#29A6C6` | `#A8DEEC` | 1.00 |
| Noon | 48 | `#0E7FA8` | `#33B0CC` | `#B2E6F0` | 1.00 |

Falling:

| Phase | Alt | Top | Mid | Bottom | Dim |
|---|---|---|---|---|---|
| Night | −18 | `#070A14` | `#101830` | `#1C2A44` | 0.55 |
| Astronomical dusk | −13 | `#080D1C` | `#1A1C3A` | `#3A2942` | 0.62 |
| Nautical dusk | −9 | `#0A1228` | `#2E2A52` | `#6E3C58` | 0.72 |
| Civil dusk | −5 | `#0E2840` | `#5E4055` | `#B45C50` | 0.80 |
| Sunset | −0.8 | `#123A52` | `#9A5E50` | `#F08A46` | 0.90 |
| Golden evening | 6 | `#145066` | `#6F7A66` | `#E8A85E` | 0.94 |
| Afternoon | 20 | `#10657F` | `#3F957E` | `#D9BC72` | 0.98 |
| Early afternoon | 34 | `#0F7294` | `#39A5A5` | `#C5D6B1` | 0.99 |
| Noon | 48 | `#0E7FA8` | `#33B0CC` | `#B2E6F0` | 1.00 |

The old model's lowest anchor was −10°, so roughly 90 minutes of twilight at each end
collapsed into one flat "night." The three new dawn/dusk steps per side are the whole
point of going from 7 to 16.

**Surfaces.**

```
tile field, open      rgba(4,24,34,0.55)
tile border, open     rgba(255,255,255,0.30)
chip / stat fill      rgba(255,255,255,0.06)
chip / stat border    rgba(255,255,255,0.22)
focused fill          rgba(255,255,255,0.26)
focused border        #FFFFFF
overlay field         #0A1420   (opaque)
cam status chip       rgba(6,18,28,0.62)
rule, strong          rgba(255,255,255,0.40) at 2pt
rule, light           rgba(255,255,255,0.22) at 1pt
now marker            #FF4438
```

**Type.** SF (system), as today. Sizes in points, 1:1 with the mock's px.

```
verdict headline   84  bold      −0.02em   lh 0.92
overlay title      72  bold      −0.02em   lh 1.00
activity title     56  bold      −0.015em
station value      52  bold
forecast temp      44  bold
cam offline title  44  bold      −0.01em
stat value         40  bold                lh 1.00
tide time          40  bold
wind speed         40  bold
city chip          38  bold      −0.01em
clock              38  regular             monospaced digits
ramp name          38  bold      −0.01em   lh 1.02
overlay right line 34  regular
verdict subline    34  regular             lh 1.25
activity row       30  mixed
status word        28  bold                lh 1.10
cam offline body   28  regular
stat detail        24  regular
freshness label    24  semibold   0.04em
chevron            24  regular
label / kicker     22  semibold   0.08em   uppercase
since line         22  regular
rail name          22  regular / bold
footnote           22  regular
```

Nothing below 22pt. The current board's 18pt error line and 13pt "Live" tag are both
below the floor for this viewing distance.

**Spacing.** 4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 22 · 24 · 26 · 30 · 32 · 34 · 42 ·
48 · 56 · 60 · 120.

**Radius. Zero everywhere.** The current board uses 10, 12 and 16 across
`GlassCard`, `FlatFocusButtonStyle` and the player. All become 0. Structure is carried by
the 2pt borders and rules instead — the same move as the rest of the design language.

**Elevation.** No shadows except the `0 0 0 6 rgba(0,0,0,0.18)` outer glow on limited and
closed tiles, which exists to separate a saturated field from a saturated sky. Drop
`GlassCard`'s `ultraThinMaterial` — it costs a blur pass per tile and the flat fills
read better at distance.

## Assets

- `screens/01-04-sky-phases.png` — the board at midday, golden evening, night and civil
  dawn. Shows the dim scrim and how far the sky moves across the day.
- `screens/05-08-states.png` — ramp closed, closing soon / entrance only, stale data,
  cam offline.
- `screens/09-12-detail-views.png` — the three stat detail panels and the Recent-changes
  overlay.

  Each sheet is a 2×2 grid of 1920×1080 boards, so every cell is 1:1 with the target
  coordinate space — measure directly off them.

- `review/cam-banner.png` — a 3222×680 crop of the live cam from the 2026-08-14 tvOS
  capture, standing in for `TVVideoPlayerView`. **Not a production asset.**
- `review/tvos-home.png`, `review/crop-ramp-grid.png`, `review/ios-home-light.png`,
  `review/ipad-home-light.png`, `review/web-desktop-light.png` — current-state captures,
  used by the critique deck.
- No new icons. Everything is SF Symbols (`chevron.left.chevron.right`, `chevron.right`)
  or drawn rectangles.
- No new fonts on tvOS — system SF throughout. The Archivo/red page chrome around the
  mock is the design-review document's styling, not the app's.

## Files

| File | What it is |
|---|---|
| `screens/` | Three contact sheets covering all twelve board states. Cells are 1920×1080, 1:1 with points. |
| `tvOS Board.dc.html` | The board mock. Props at the top switch scenario, time, detail panel. |
| `Design Review - Beach Ramp Status.dc.html` | 16-slide critique of the current surfaces. Slides 6–8 cover tvOS. |
| `support.js`, `deck-stage.js` | Runtime for the two HTML files. Not app code. |
| `_ds/modernist-…/` | Styling for the review documents only. Not app code. |
| `review/` | Screenshots and crops. |

Source files this design changes, for reference:

```
apple/BeachRamp/BeachRampTV/ContentView.swift      layout, TVRampTile, DayTimelineBar, CoastlineRail
apple/BeachRamp/BeachRampTV/TVTheme.swift          SkyPalette (7 → 16 anchors), status colors
apple/BeachRamp/BeachRampTV/TVVideoPlayerView.swift  offline state, corner radius
apple/BeachRamp/BeachRampTV/TVViewModel.swift      detail state, data age, activity, ramp order
apple/BeachRamp/BeachStatus/                       unify status tokens across platforms
```

## Out of scope

iPhone, iPad, web, TRMNL X and the retired Tidbyt template. The sequence agreed was
tvOS → iPadOS → iPhone → web, with tvOS naming the tokens the others inherit.
