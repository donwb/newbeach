# Handoff: tvOS design v3 — Beach Ramp Status

Panorama header with inline selectors. Replaces the board in `tvOS Board.dc.html`.

Design file: `tvOS design v3.dc.html` (project root)
Components: `TvRampCard.dc.html`, `TvDayPanel.dc.html`
Screens: `screens/01`–`06`, PNG at 1920×1080

---

## What changed and why

The board ran out of room once surf, the weekend outlook and the daily
forecast arrived. In the previous version those three were squeezed into two
tiles in the top-right at roughly 21px effective — under the 24px floor a
10-foot read needs.

Three structural changes made room:

1. **The cam moved to the top as a full-bleed band at its true aspect ratio.**
   The source is 3222×680 (4.74:1). Filling a 16:9 screen with it discards
   about 60% of the width and hard-zooms the centre of the beach. As a
   1920×405 band it is uncropped and larger than the block it replaces.

2. **The bottom city-nav row was deleted.** It cost 66px and sat about 700px
   from the video it controlled.

3. **The two selectors swapped places.** Each now sits against the surface it
   drives.

The recovered space went to the Ahead band: surf is now 48px, the two day
panels 200px tall.

---

## Layout

| Region | Height | Notes |
|---|---|---|
| Cam band | 405px | Full bleed, no side padding. 3222:680 |
| Lower area | 675px | 24px top / 44px bottom / 64px sides |
| Ramp heading | ~62px | 2px rule beneath |
| Ramp cards | 218px | 5 across, 18px gap |
| Ahead band | 200px | `1.3fr 1fr 1fr` — surf, Saturday, Sunday |
| Daylight band | ~62px | Sky gradient strip + three captions |

Nothing is centred into a shrinkable flex track. Every band is `flex:none`
with a single `flex:1;min-height:0` spacer absorbing slack above the daylight
band.

---

## The two selectors

**Cam — caption strip on the video's bottom edge.** Label "WATCHING", then
the five cam names. Active one at 26px/800 with a 4px underline; the rest at
24px/0.55 opacity. Right-aligned hint reads "‹ › switches cam". It sits
inside the band's existing bottom gradient, so it costs no vertical space and
reads as a caption rather than a nav.

All five cams are always present, in fixed geographic order. Per-cam state
("offline since 12:48 PM") is a 22px sub-label nested
**under** its own cam name — never a sibling in the list, which would consume
a name slot and make the strip disagree with what the remote does.

**Ramp city — the ramp section heading.** Label "RAMPS", then the city at
38px/800 with "‹ ›" after it, over a 2px rule. The right end of the same row
carries the ramp count and "☰ Recent changes".

Both are city lists, so they are deliberately different shapes: the cam one
is a flat run of names on imagery, the ramp one is a single large name on the
ground. They can never be mistaken for each other.

---

## Status fields

Status is carried by the card's field, never by coloured text.

| Status | Field | Border | Text | Mark |
|---|---|---|---|---|
| open | `rgba(4,26,40,0.42)` | `rgba(255,255,255,0.28)` | `#fff` | `#2AE07A` |
| limited | `#F5A214` | `#F5A214` | `#241500` | `#241500` |
| closed | `#C9301C` | `#C9301C` | `#fff` | `#fff` |
| overnight | `rgba(4,8,20,0.42)` | `rgba(255,255,255,0.20)` | `rgba(255,255,255,0.72)` | `rgba(255,255,255,0.45)` |

`overnight` exists so an expected end-of-driving close is not drawn in the
same field as a storm or tide closure. Red is reserved for a closure nobody
planned. See screen 04.

Verdict marks on `TvDayPanel` use the same palette: great/good `#2AE07A`,
mixed `#F5A214`, rough `#FF5240`, no_call `rgba(255,255,255,0.45)`.

---

## Type scale

| Use | Size | Weight |
|---|---|---|
| Verdict headline | 80px | 800, -0.025em |
| Verdict subline | 30px | 400 |
| Surf line | 48px | 800, -0.02em |
| Ramp city | 38px | 800 |
| Ramp name | 40px | 800 |
| Day panel headline | 30px | 700 |
| Ramp status word | 30px | 800 |
| Active cam name | 26px | 800 |
| Section labels, captions | 22px | 600–700, 0.08em, uppercase |

22px is the floor. Nothing on the board goes below it.

---

## Data sources

Every string below is rendered verbatim — the API owns the prose, including
its hedging. Do not re-phrase client-side.

| Element | Source |
|---|---|
| Verdict headline / subline | derived from `/api/v2/outlook` ramps + `tide` |
| Ramp card third line | `RampOutlook.Short` |
| Surf line | `SurfReport.Line` |
| Surf right-hand label | `SurfReport.RipRisk` (NWS SRF verbatim) |
| Surf detail line | `SurfReport.HeightLabel`, period, `ObservedAt` |
| Day panel verdict | `WeekendDay.Verdict` |
| Day panel headline | `WeekendDay.Headline` |
| Day panel metrics | `HighTempF`, `RainChancePct`, `WindLabel` |
| Forecast overlay title | `WeekendOutlook.Headline` |
| Forecast rows | `WeekendOutlook.Days[]` |
| Driving hours in night state | `Schedule.ClosesLabel` / `OpensLabel` |

---

## States

**01 Afternoon** — base state, all five open.

**02 Mixed** — one limited, one closed, rough Sunday. Confirms the verdict
marks read identically on a ramp card and a day panel.

**03 Cam offline** — the band falls back to the sun-phase sky gradient and
the caption strip does the recovery itself: the dead cam is struck through
with "offline since 12:48 PM" beside it, and the live one is named in amber
with a chevron. No separate banner. Note the nav order is geographic
north→south, so the live neighbour may be in either direction — the copy must
be generated from position, not hard-coded.

**04 After dark** — the cam runs 24/7 and gets no special overnight handling:
same feed, same treatment, `filter: brightness(0.34) saturate(0.72)
contrast(1.06)` under the night sky scrim, and no per-cam sub-label. Ramps in
`overnight`. Stale-buoy surf state: "No surf read right now."

**05 Saturday** — the Saturday slot holds its position and takes the label
"Today · Saturday". Positions never move; only the label and copy change.

**06 Beach forecast** — opens from the weekend panel. Seven rows, verdict
mark first, `WeekendDay.Headline` verbatim, and a "No call" row for days past
the NWS horizon.

---

## Open items

- **Night status across surfaces.** This design uses `overnight` for a ramp
  after gates close. `iOS.dc.html` frame 02 currently shows the same ramps as
  **open** at 9:34 PM. Three surfaces should agree; iOS and web still need
  bringing onto this status.
- **Short display names.** The Daytona widget work established that ten-ramp
  cities need a short name per ramp ("Intl Speedway Blvd"). Same need here if
  the board ever shows a ten-ramp city — five cards at 330px will not hold
  "International Speedway Blvd" at 40px.
- **Scrim on real hardware.** The band's bottom gradient reaches 0.88 to
  protect the caption strip. Worth confirming on a real panel that the
  panorama still reads through it at the top.
