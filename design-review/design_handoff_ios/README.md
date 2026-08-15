# Handoff: iOS + iPadOS redesign — Beach Ramp Status

## Overview

A redesign of the SwiftUI app at `apple/BeachRamp/`. Same data, same five endpoints, same
feature set. What changes is the order of the screen, how status is carried, and three new
surfaces the app does not have today (ramp detail, a landscape cam view, and the widget
family).

Five things:

1. **The sky is the app.** The board opens on the live sky gradient — the same sixteen sun
   phases tvOS owns — and the verdict sits in it. No `Color(.systemBackground)`, no system
   light/dark, no theme toggle. This was a deliberate call: the app's identity is the
   time of day.
2. **A verdict, not a summary.** The three `StatusCount` cards are gone. Their counts move
   onto the status filter buttons, and the top of the screen answers "can I get on the
   beach right now" in one sentence before any ramp is read.
3. **Status carried by the card field, not a coloured pill.** Open is a white card, limited
   is a solid amber field, closed is a solid red field. `cardSurface(cornerRadius: 14)`
   goes — radius is 0 everywhere and structure comes from 2px rules.
4. **A ramp detail screen**, which the app does not have: today's status band, the ramp's
   closure threshold drawn on the tide curve, and the activity feed scoped to one ramp.
   Pushed on iPhone, presented as a sheet on iPad.
5. **The cam leaves the scroll on iPhone.** A 1280×270 panorama does not fit a 402pt
   portrait column without becoming a stripe. It is its own landscape view, reached from
   one row, with the verdict overlaid. On iPad it stays in the layout, where there is width
   for it.

Read `design_handoff_tvos_board/README.md` first if you have not: it owns the sixteen sun
phases, the status tokens and the verdict-band copy rules. Then
`design_handoff_web/README.md`, which owns the day-ground veil and the detail screen's
content model. This document states where iOS and iPadOS differ.

## About the design files

`iOS.dc.html` is a **design reference created in HTML** — a prototype showing intended look
and layout. It is **not production code to port**. It renders eleven frames at 1:1 point
sizes, each tagged `data-screen-label`. Point sizes in the mock map 1:1 to SwiftUI points.

Open it in a browser, or read `screens/` for stills.

Not final: the cam is a static crop (`review/cam-banner.png`) standing in for the existing
`BeachCamView` / AVPlayer. Keep the player and its refresh logic.

## Fidelity

**High fidelity.** Authored at 402 × 874 (iPhone 16 Pro), 1194 × 834 and 834 × 1194
(iPad 11"), and at the real WidgetKit point sizes. Type sizes, rule weights, the two
padding scales (18 iPhone / 28–34 iPad) and the field colours are final.

The device bezels in the mock are drawing, not spec. Ignore them.

---

## The ground — sun-following

Identical mechanic to web, so the two stay in step. Sun altitude drives one scalar:

```
dayness = clamp((altitude + 4) / 12, 0, 1)      // 1 above +8°, 0 below −4° (civil dusk)
```

Two layers. The sky gradient is exactly the tvOS one for the current phase; the veil above
it is the Modernist ground tinted toward the sky's own low colour:

```
sky   = LinearGradient(160°, phase.top 0%, phase.mid 46%, phase.bot 100%)
veil  = mix(phase.bot, #f3f2f2, 0.70) at opacity = dayness
```

**Where iOS differs from web:** on web the veil covers the whole page, so at noon the page
is a flat cream. On iPhone the veil covers **only the sheet** — the hero always shows the
raw sky. That is what makes the phone feel like a window rather than a document. Concretely:

| Region | Day (dayness 1) | Night (dayness 0) |
|---|---|---|
| Hero | raw sky gradient + top scrim | raw sky gradient |
| Sheet | veil, opaque — `#EBE2CC` at afternoon | no fill at all; the sky continues |
| Sheet edge | 2px `--ink` rule | 2px `rgba(255,255,255,0.40)` rule |

So past civil dusk the sheet stops existing as a surface and becomes a single rule
(screen 02). Do not fade the sheet fill to a dark translucent panel — it reads as a modal.

The hero carries a top scrim so white type holds over the sky's warm horizon band:

```
LinearGradient(.top → .bottom,
  rgba(6,32,44,0.58) 0%, rgba(6,32,44,0.30) 46%, rgba(6,32,44,0.04) 100%)
```

Foreground tokens flip at `dayness < 0.5` rather than interpolating, so text never sits at
an in-between contrast. Transition the ground over 2s on the same 30-second tick tvOS uses;
`accessibilityReduceMotion` drops the transition, not the theming.

## Tokens

The tvOS trio holds at night; day needs the two darker variants web introduced. Put all six
in `BeachStatus` alongside the tvOS set rather than redeclaring them per target — the Watch
app and the widget extension need the same values.

| Token | Day | Night |
|---|---|---|
| `ink` | `#201e1d` | `#ffffff` |
| `ink2` (secondary) | `rgba(32,30,29,0.62)` | `rgba(255,255,255,0.72)` |
| `rule` (2px) | `rgba(32,30,29,0.85)` | `rgba(255,255,255,0.40)` |
| `rule2` (1px) | `rgba(32,30,29,0.22)` | `rgba(255,255,255,0.22)` |
| `accent` | `#ec3013` | `#FF6A4D` |
| `tidefill` | `rgba(32,30,29,0.10)` | `rgba(255,255,255,0.14)` |
| open mark | `#0A7A42` | `#2AE07A` |
| open card fill | `#ffffff` | `rgba(4,24,34,0.55)` |
| open card border | `rgba(32,30,29,0.85)` | `rgba(255,255,255,0.30)` |
| limited fill / border | `#F5A214` | `#F5A214` |
| limited text + mark | `#241500` | `#241500` |
| closed fill / border | `#D22B18` | `#E63A2B` |
| closed text + mark | `#ffffff` | `#ffffff` |

Red lightens at night because `#ec3013` on the night sky is under 3:1. Radius is 0
everywhere. Font is Archivo at 400/600/700/800 — bundle it; do not fall back to SF.

---

## Screen: the iPhone board (01, 02)

One scroll, verdict first. Page padding **18pt**. `ScrollView` + `LazyVStack` as today.

**Hero.** Height is content-driven, about 310pt at the default verdict — do not fix it. In
order: brand row (9pt status dot + name at 16/800, phase name + clock right), 16pt gap,
the city control, 14pt gap, the verdict, the subline. There is no spacer: an earlier
version pushed the verdict to the bottom of a 392pt hero and the dead band in the middle
was the first thing that had to go.

**Verdict.** A 12 × 52 solid rectangle in the verdict colour, then the headline at
40/800/−0.03em/lh 0.92 in white, then the subline at 15pt/0.8 alpha with `leading 26` so it
aligns to the headline's text edge, not the bar's. Headline copy follows the tvOS rule —
name the exception if there is one, state the count if there are several, never lead with a
bare numeral. Keep the last clause of the subline from breaking alone.

**Sheet.** 2px rule, then a 3-up stat strip (Tide / Water · Air / Wind) divided by 1px
rules, then a 2px rule. Labels 10/700/0.09em uppercase, values 18/800 tabular, detail 11.
Tapping a cell pushes the same tide / water / wind detail the tvOS panels show.

**Filters.** Four count buttons, 34pt tall with a 44pt touch area via padding. Active is a
solid accent field with white type; the rest are 2px-bordered. This is where the removed
summary cards' counts live.

**Ramp rows.** 62pt minimum, 10pt gaps, whole row is the push. Name 22/800/−0.015em, since
line 11pt under it, then a 10 × 20 status mark and the status word at 15/800 on the right.
Never truncate a ramp name — wrap to two lines.

**Then**, in order: tide (12-hour curve, 92pt, `--tidefill` under the stroke, accent now
line, extremes labelled below), the live cam row, the footer. Order matters: the cam is
below the tide because on a phone the tide is the decision and the cam is reassurance.

**Stale feed.** Rows drop to 0.45 opacity, since lines become `as of 2:09 PM`, the status
dot goes amber, and the verdict reads `Last known: five open` with `do not trust this page`
in the subline. The current `errorMessage` red `Text` is removed.

## Screen: iPhone ramp detail (03)

Pushed, not a sheet — on a phone a sheet costs you the back affordance and the swipe. Back
link `← All New Smyrna ramps` and a favourite toggle in a 44pt bar, then:

1. **Hero.** Kicker `Ramp 01 · New Smyrna Beach` at 10pt, name at 34/800.
2. **Status field band**, full width, in the ramp's own field colour: 12 × 34 mark, status
   at 20/800, since line at 12pt, then the forward-looking line at 14/600 —
   `Expect full closure near high tide 11:07 PM.` or
   `Reopens near 6:30 PM as the tide drops.` This line is the reason the screen exists.
3. **Today's status band.** Midnight to midnight, one segment per state weighted by
   duration, 18pt tall, 2px gaps, in the field colours. A 3px `ink` now-marker overhangs
   9pt top and bottom. Under each segment its start time at 12/800 tabular and its label
   at 10pt.
4. **Facts**, 2 × 2 with 2px top rules: Address, Driving hours, Closes above, Nearest cam.
5. **Tide against this ramp** — the 24-hour curve plus a **dashed 2px `#F5A214` line at the
   ramp's closure height**. The dashed line is the point of the chart: it turns a tide
   reading into a decision.
6. **This ramp · last 48 hours** — the activity feed filtered to this ramp, 104pt tabular
   time column.
7. **Other ramps** — 2-column, 4px top rules, current one in accent, so you can flip
   between ramps without going back.

The detail screen sits on the veiled ground, not the raw sky. The sky hero is the board's
signature and repeating it here would flatten the difference between the two screens.

## Screen: iPhone live cam (04)

Landscape only, presented full screen, `.persistentSystemOverlays(.hidden)`. The panorama
fills the frame with `.aspectRatio(contentMode: .fill)`. Over it: a top scrim carrying the
LIVE dot, the cam name at 22/800, the other cams as a right-aligned row, and a close ✕; a
bottom scrim carrying the verdict at 17/800 with its status bar and the frame timestamp.

If the cam is offline, the frame becomes flat `#0A1420` with
`New Smyrna Beach cam offline` at 28/800 and `Reconnecting — last frame 3:12 PM.` under it.
Keep `/api/v2/video/refresh` and the existing retry.

The cam is sugar. If the stream is dead the rest of the app is unaffected, and the row that
opens this view should simply not appear when the cam roster is empty.

---

## Screen: iPad board (05, 07)

One wide board. **Not** `NavigationSplitView` — there is no hierarchy to navigate here; a
sidebar would spend 320pt restating five city names that fit in a tab row.

**Landscape, 1194 × 834.** The sky band holds the status row, the brand, the five city tabs
(4px `#FF6A4D` underline on active) and the verdict, laid out `1.55fr / 1fr` — headline
left at 52/800, the three stat cells right. Below it, `1fr / 372pt`:

- **Left:** filter row (with `☆ Favorites` pushed right), the ramp grid **3 across** at
  152pt minimum, then a 2px rule and Recent changes.
- **Right rail:** tide (104pt curve), forecast 4-up, live cam at its true 1280/270 with a
  `Full screen ›` link.

**Portrait, 834 × 1194.** The rail cannot hold at 834 — it would leave the grid under
440pt. So it dissolves: the verdict's stat cells stack under the headline, the ramps go
**2 across** at 116pt, and conditions move below the grid as tide + forecast side by side,
water temperature under the forecast. The cam becomes a 106pt strip rather than a full
1280/270 crop, which at 778pt wide would eat a fifth of the page.

Both orientations are one scroll. Nothing is pinned.

## Screen: iPad ramp detail sheet (06)

`.sheet` at 760 × 762 over the dimmed board (`rgba(6,20,32,0.52)`), 2px `ink` border, no
radius. Same seven blocks as the phone detail at the iPad scale: name 46/800, status 28/800,
facts 4 across, tide and the 48-hour feed side by side, Other ramps as a single row in a
pinned footer. `Done` top right in accent.

A sheet rather than a push because the board is the context — you are comparing this ramp
against the others, and the others should stay on screen behind it.

---

## Widgets (08, 09)

Sizes are the real WidgetKit ones: small 170, medium 364 × 170, large 364 × 382. The shell
carries the **system** corner radius (`ContainerRelativeShape`); everything inside stays
square. This is the one place radius is not 0, and it is not ours to set.

Widgets sit on the same sun-following ground as the app, veil and all.

**The five-square strip** is the compact status device: one square per ramp, in city order,
in the field colours. It reads as a bar chart of the day at a glance and it is the only
element that changes shape with ramp count.

| Family | Content |
|---|---|
| Small | City kicker, the strip, `4 open` at 38/800, the exception at 12/700, clock |
| Medium | Left: strip + verdict headline at 21/800 + since. Right rail 118pt: tide value, sparkline, next extreme |
| Large | Kicker + clock, verdict at 23/800, 2px rule, the full ramp list, 2px rule, tide readout + sparkline |

**City is configured per widget instance**, so two widgets can watch two cities. A
`WidgetConfigurationIntent` with:

- `city` — the city. Defaults to New Smyrna Beach.
- `show` — `All ramps` | `Favorites only` | `One ramp`.
- `ramp` — disabled unless `show == .oneRamp`, then the widget switches to that ramp's own
  verdict and its forward-looking line.

**Scaling past five ramps.** New Smyrna's five is the tuned case; Daytona's ten is the
ceiling that still reads.

- The strip divides into as many squares as there are ramps (gap tightens 3 → 2pt).
- Small and medium never list ramps, so they are identical at any count. The verdict
  headline names the exceptions at one or two (`Beachway limited — four others open`) and
  states the count above that (`Seven of ten open`, exceptions in the subline).
- The large widget's list goes **2 across** above five: rows 34pt, name 11/800 over two
  lines, 6 × 16 mark.
- Beyond ten, large should fall back to a count-only summary rather than shrink further.

**This needs a short display name per ramp from the API.** `International Speedway Blvd`
does not fit a 162pt cell; the mock shows `Intl Speedway Blvd`. Do not truncate with an
ellipsis — a half-read ramp name is worse than no list.

## Lock Screen widgets (10)

`.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`. These render
**monochrome** — the system tints them and throws your colours away — so status has to read
as fill and weight, never hue. That is why the vocabulary here is a ring and a bar rather
than the green/amber/red fields.

- **Circular:** a 5pt ring, `4/5` at 22/800 tabular, `OPEN` at 8pt caps. The ring's filled
  arc is open ÷ total.
- **Rectangular:** a 5 × 52 white bar, then `Beachway limited` at 15/800, `4 others open`
  and `Tide 1.8 ft ↓` at 11pt/0.72.
- **Inline:** `4 of 5 ramps open · Beachway limited`.

## Live Activity (10)

Starts when a ramp the user favourites goes limited, or when the tide is inside two hours
of a closure threshold. Ends at reopen, or at the gate hour.

**Lock Screen**, 364 wide: kicker (status dot + `Beachway Ave · limited`) and clock, then a
10 × 44 field bar with `Closes near 11:07 PM` at 22/800 and the mechanism underneath —
`Tide 1.8 ft rising past 2.4 ft in 6h 55m`. Then a 6pt progress track from the limited
timestamp to the projected closure, with a 2px white now-marker. Background
`rgba(14,22,30,0.86)`.

**Dynamic Island compact:** leading 8 × 16 field mark, trailing `1.8 ft ↑` at 13/800
tabular. **Expanded:** ramp name and `Limited` at 26/800 left, `Closes` / `11:07 PM` right,
the same progress track, and `Four other New Smyrna ramps open` at 12pt.

Shape:

```swift
struct RampActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: RampStatus          // .limited | .closed
        var since: Date
        var projectedChange: Date?      // closure or reopen, nil if unknown
        var tideFeet: Double
        var tideRising: Bool
        var thresholdFeet: Double
        var othersOpen: Int
    }
    var rampID: String
    var rampName: String
    var cityName: String
}
```

The progress track is `since → projectedChange`; when `projectedChange` is nil, drop the
track and the headline becomes the status word.

## Apple Watch (11)

Refresh of the existing `BeachRampWatch` target, 45 mm. The sky ground holds — the same
gradient and scrim, scaled. Clock top right, the strip at 6pt, `4 open` at 30/800, the
exception at 12/700 over two lines, a 1px rule, then `Tide 1.8 ft ↓` and the next extreme.
One screen, no list, no navigation. Complications: circular `4/5` + `OPEN`, and a
rectangular one with the bar, `4 open`, the exception and the tide.

---

## Type

Archivo, weights 400/600/700/800. Sizes in points.

| Element | iPhone | iPad | Widget |
|---|---|---|---|
| verdict headline | 40 / 800 / −0.03em / lh 0.92 | 52 landscape · 42 portrait | 23 large · 21 medium |
| detail name | 34 / 800 | 46 | — |
| ramp name | 22 / 800 / −0.015em | 27 grid | 15 large · 11 at ten ramps |
| detail status | 20 / 800 | 28 | — |
| stat value | 18 / 800 | 26 | 22 |
| small widget count | — | — | 38 / 800 |
| brand | 16 / 800 | 20–21 | — |
| verdict subline | 15 / 400 / lh 1.3 | 18–19 | 11 |
| status word, city control, fact value | 15 | 17 | — |
| clock | 15 tabular | 19–20 | 11 |
| forward-looking note | 14 / 600 | 16 | — |
| activity row | 13 | 13–14 | — |
| segment start time | 12 / 800 tabular | 15 / 800 | — |
| since line | 11 | 12 | 10–11 |
| kicker / label | 10 / 700 / 0.09em caps | 11 / 700 / 0.09em | 9 / 700 / 0.09em |
| segment label, fact label | 10 | 12 | — |

Nothing below 9pt, and nothing below 13pt that a user needs to read to make a decision.
`.monospacedDigit()` on every clock, time, tide height and temperature.

## Spacing

4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 22 · 24 · 26 · 28 · 34 · 40 · 52. Section rhythm is a
2px rule with 10–12pt above it and 12–14pt below. Page padding 18 iPhone, 28 iPad portrait,
34 iPad landscape, 16 widget.

## Interaction states

- Rows, cards, stat cells, tabs, filters: pressed tint
  `accent.opacity(0.08)`, one step darker on hold.
- Touch targets: ramp rows 62pt, city control 46pt, filter buttons 34pt with 44pt padded
  area, cam row 58pt. Nothing tappable under 44pt.
- `.refreshable` stays on the board. `scenePhase == .active` refresh stays.
- VoiceOver: the verdict is one label, read before the ramp list. Each ramp row is one
  element — `"Beachway Ave, limited since 3:48 PM"` — not four.
- Reduce Motion: keep the ground theming, drop the 2s crossfade.

## API additions

Everything else is already in `/api/v2/ramps`, `/tides`, `/tides/chart`, `/weather`,
`/activity` and `/config`. Same list as web, plus one iOS-only need.

| Need | Where used |
|---|---|
| per-ramp closure height (ft) | detail facts, the dashed tide line, the Live Activity threshold |
| per-ramp status history, 48h | detail feed and today's status band |
| explicit per-city ramp order | board order and the widget strip — NSB is Beachway, Crawford, Flagler, 3rd, 27th |
| ramp address + driving hours | detail facts (may already be in `config`) |
| data age / feed timestamp | stale state |
| **short display name per ramp** | **widget lists at six or more ramps** |

The status band needs history as intervals, not events, or it has to be derived client-side
by walking the event list backwards from now.

## Files

| File | What it is |
|---|---|
| `iOS.dc.html` | The mock — eleven frames. Open in a browser. |
| `RampRow.dc.html` | The ramp row used by the iPhone boards in the mock. |
| `ios-frame.jsx`, `support.js` | Runtime for the mock. Not app code. |
| `screens/01–03` | iPhone board (afternoon, night) and ramp detail, full scroll length. |
| `screens/04` | iPhone live cam, landscape. |
| `screens/05–06` | iPad landscape board, and the ramp detail sheet over it. |
| `screens/07` | iPad portrait board. |
| `screens/08` | Home Screen widgets — small, medium, large. |
| `screens/09` | Widget configuration, and Daytona at ten ramps in medium and large. |
| `screens/10` | Lock Screen widgets, Live Activity, Dynamic Island. |
| `screens/11` | Apple Watch app and complications. |
| `review/cam-banner.png` | Cam placeholder crop. **Not a production asset.** |
| `_ds/modernist-…/styles.css` | The Modernist token sheet. The values, not the CSS, carry over. |

Source files this design changes:

```
apple/BeachRamp/BeachRamp/ContentView.swift        both layouts; StatusCount removed
apple/BeachRamp/BeachRamp/Views/HeaderView.swift   becomes the sky hero + verdict
apple/BeachRamp/BeachRamp/Views/FilterBarView.swift now carries the counts
apple/BeachRamp/BeachRamp/Views/RampCardView.swift  field-based status, radius 0
apple/BeachRamp/BeachRamp/Views/TideChartView.swift threshold line, new type scale
apple/BeachRamp/BeachRamp/Views/BeachCamView.swift  landscape-only presentation on iPhone
apple/BeachRamp/BeachRamp/Theme/                    day + night token sets
apple/BeachRamp/BeachStatus/Sources/                status tokens shared with widgets + Watch
apple/BeachRamp/BeachRampWatch Watch App/           sky ground, one-screen verdict
```

New targets: a widget extension (Home Screen + Lock Screen + Live Activity), and a
`RampDetailView` plus the landscape cam view in the main app.

## Out of scope

tvOS (done — `design_handoff_tvos_board/`), web (done — `design_handoff_web/`), TRMNL X.
The agreed sequence was tvOS → web → iPadOS → iPhone, with tvOS naming the tokens the
others inherit.
