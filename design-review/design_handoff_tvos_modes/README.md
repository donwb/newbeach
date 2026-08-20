# Handoff: Beach Ramp Status — tvOS Cam mode / Board mode

## Overview

The tvOS app has two presentations of the same moment, one D-pad press apart.

- **Cam mode** — the beach camera at its largest sharp size, with only the
  verdict, the surf sentence and the five ramp cards. The resting state.
- **Board mode** — the camera settles into a header band and the full
  information board fills the screen: ramp city heading, five ramp cards,
  surf panel, two weekend panels, daylight bar.

The switch is a direction, not a setting. Press **Down** from Cam mode and the
board rises; press **Up** from the board's top row and it drops away.

The single rule that makes it legible: **the verdict never moves.** The brand
row, weather cluster, clock, accent bar, verdict headline and its detail line
occupy identical coordinates in both modes. Only the video's bottom edge
travels — 680px to 405px — and the cam caption strip is fixed to that edge.
Information is added underneath rather than rearranged.

## About the design files

The files in `design/` are **design references created in HTML** — prototypes
that show intended look and behavior. They are not production code to port.
The task is to recreate these designs in the target codebase's own environment
(SwiftUI / TVMLKit for tvOS) using its established patterns. Where this README
gives a pixel value, treat it as the intended rendered value at 1920×1080, not
as a CSS instruction.

`design/tvOS modes.dc.html` is a single review document containing all three
screens side by side, plus a "rules" block at the bottom. Each screen is a
1920×1080 element with an id (`#m01`, `#m02`, `#m03`).

## Fidelity

**High-fidelity.** Final colors, typography, spacing and layout. Recreate
pixel-accurately using the codebase's existing components where they exist.

## Canvas and safe area

| | |
|---|---|
| Canvas | 1920 × 1080 |
| Horizontal safe padding | 64px both sides, every row |
| Cam band, Cam mode | 1920 × 680 |
| Cam band, Board mode | 1920 × 405 |
| Verdict block | y 172 → 291, **both modes** |
| Minimum type size | 22px |
| Mode transition | 340ms, ease-out |

## The camera feed — read this before implementing

The source stream is **3222 × 680** (4.74:1). Both modes are built so the feed
is never upscaled:

- **Cam mode** renders it at **1920 × 680 — 1:1**, every source pixel mapped to
  one display pixel. This crops horizontally: 1920 of 3222 columns, **60% of
  the panorama**, centered on the pier.
- **Board mode** fits the full width and renders **1920 × 405**, a 0.596×
  downscale showing 100% of the panorama.

Filling the 16:9 frame would require a 1.59× upscale of an already-soft stream.
Do not do it. 680px is the ceiling. If the feed's resolution changes, the cam
band height in Cam mode should change with it rather than being left at 680.

The camera **runs 24/7 and gets no special overnight handling** — same feed,
same treatment, no infrared mode, no per-cam sub-label at night. After dark
the picture is simply darker: `brightness(0.34) saturate(0.72) contrast(1.06)`
in the prototype, which stands in for the real feed's low-light output.

## Screens

### 01 — Cam mode (`#m01`)

The resting state. Vertical stack, no scroll.

**Cam band — y 0 → 680**

Camera fills the band (`object-fit: cover`, center). Well color behind it
`#0A1420`. Two scrims over the video, both needed for text contrast:

- top: `linear-gradient(to bottom, rgba(4,20,32,0.72) 0%, rgba(4,20,32,0.34) 34%, transparent 100%)`, height 400
- bottom: `linear-gradient(to top, rgba(4,20,32,0.86) 0%, rgba(4,20,32,0.30) 46%, transparent 100%)`, height 240

Content inset `40px 64px 20px`, stacked:

1. **Chrome row** (y 40 → 132). Left: 13px `#2AE07A` dot, 26px/800 "Beach Ramp
   Status", 22px uppercase 0.08em `opacity .6` "Volusia County". Right: weather
   cluster then 32px tabular clock "1:23 PM".
   Weather cluster is a 2px `rgba(255,255,255,0.34)` bordered box on
   `rgba(4,20,32,0.44)`, three cells divided by 2px `rgba(255,255,255,0.22)`,
   each `9px 20px`: 22px uppercase label `opacity .7` over 34px/800 tabular
   value — Water 82°, Air 91°, Wind SW 5.
2. **Verdict block** (margin-top 40 → y 172 → 291). 20 × 74px accent bar in the
   status color, 20px gap, then 80px/800 headline (line-height .94,
   letter-spacing -.025em) "All five open" over 30px detail line `opacity .92`
   "Tide rising · high 2:56 PM · 6h 36m of light left".
3. **Flexible spacer** — this is the picture. ~300px of unobstructed video.
4. **Cam caption strip**, pinned to the band's bottom edge. 2px
   `rgba(255,255,255,0.34)` top rule, 12px padding above content. Left: 22px
   uppercase `opacity .6` "Watching". Then the five cam names in fixed
   geographic order — active one 26px/800 with a 4px white underline, the rest
   24px at `opacity .55`. Right: 22px `opacity .6` "‹ › cam", then a 2px
   left divider and 22px/700 "▾ Ramps".

**Ambient section — y 680 → 1080**

Own ground so white type clears the pale end of the sky gradient:
`linear-gradient(to bottom, rgba(4,20,32,0.88), rgba(4,20,32,0.74))`.
Inset `32px 64px 40px`, `space-between`:

1. **Surf sentence** — a baseline row, not a panel: 22px uppercase
   `opacity .6` "Surf" · 44px/800 "Pretty much flat out there" · 24px
   `opacity .75` "Knee-high · 6s · rip risk low".
2. **Ramp cards** — 5 equal columns, 18px gap, 218px tall. Same component as
   Board mode.

No ramp city heading, no weekend panels, no daylight bar in this mode.

### 02 — Board mode (`#m02`)

**Cam band — y 0 → 405.** Identical structure to Cam mode's band, with a single
full-height scrim instead of two:
`linear-gradient(to bottom, rgba(4,20,32,0.58) 0%, rgba(4,20,32,0.10) 32%, rgba(4,20,32,0.38) 60%, rgba(4,20,32,0.88) 100%)`.
Chrome row and verdict block land at the same coordinates as Cam mode. The
caption strip's right end reads **"▴ Full cam"** instead of "▾ Ramps".

**Board — y 405 → 1080.** Inset `20px 64px 40px`, stacked:

1. **Ramp heading row**, 2px `rgba(255,255,255,0.42)` bottom rule, 10px padding
   above it. Left: 22px uppercase `opacity .68` "Ramps" · 38px/800 city name
   "New Smyrna Beach" · 26px `opacity .6` "‹ ›". Right: 24px `opacity .75`
   "5 ramps · all open" · 22px `opacity .6` "☰ Recent changes".
2. **Ramp cards**, margin-top 16, 5 columns, 18px gap, 218px.
3. **Surf + weekend row**, margin-top 18, columns `1.3fr 1fr 1fr`, 18px gap.
   Surf panel: `rgba(4,26,40,0.42)` on 2px `rgba(255,255,255,0.28)`, padding
   `20px 24px` — 22px uppercase "Surf" and a right-aligned rip-risk note, 48px/800
   headline, 24px `opacity .75` source line. Weekend panels are `TvDayPanel`.
4. **Flexible spacer.**
5. **Daylight bar**, bottom. A 14px strip whose gradient runs midnight to
   midnight —
   `linear-gradient(90deg,#070A14 0%,#0C1230 7%,#1B2A52 12%,#0E6E8C 24%,#0E7FA8 52%,#10657F 69%,#123A52 83.6%,#0A1228 88.5%,#070A14 100%)`
   — with a 4 × 28px white tick at the current time, offset 7px above the strip.
   Below it, margin-top 14, a 22px `opacity .85` row: sunrise left, sunset
   right, "Golden hour 7:27 PM · 6h 36m of daylight left" centered and 600
   weight. **The tick position must be computed from the clock, not hard-coded.**

### 03 — Cam mode after dark (`#m03`)

Cam mode with the night palette. Page ground
`linear-gradient(165deg,#0A1228 0%,#2E2A52 48%,#6E3C58 100%)`, cam well
`#05080F`, scrims use `rgba(6,10,24,·)` at 0.76/0.36 (top) and 0.90/0.34
(bottom). Verdict bar is `rgba(255,255,255,0.55)` — an expected overnight close
is neutral, never red. Headline "Driving is done for today", detail "Gates
closed 7:44 PM · ramps reopen around sunrise, 6:54 AM". Surf is the stale-buoy
state: 44px headline at `opacity .72` "No surf read right now" plus "Buoy 41009
last reported 7 hours ago". All five cards `overnight`.

## Interactions & behavior

### Focus model

**Up/Down are not taken over by the mode switch.** Board mode has four focus
rows, top to bottom:

1. cam caption strip
2. ramp city heading
3. ramp cards
4. surf + weekend panels

Up/Down move between them normally. Only an **Up press with nowhere further to
go — from the caption strip — falls through and closes the board.** This is the
same fall-through tvOS uses on the Home screen's top row, so it needs no
teaching. In Cam mode nothing but the caption strip is focusable, so Down has
no competing meaning and always opens the board.

**Left/Right belong to the focused row.** That is how three different
Left/Right jobs coexist without a chord or long-press: cam switching on the
caption strip, ramp-city switching on the heading, card-to-card on the ramp
row.

**Menu** exits the app from Cam mode, and returns to Cam mode from anywhere
else.

### The transition

340ms, ease-out, one motion. The **finished board is translated up as one
block** behind the cam band's bottom edge — never re-laid-out at an
intermediate height. Mid-rise it simply hangs below the frame and is clipped by
it. Concretely:

- cam band height animates 680 → 405
- the caption strip is fixed to that edge and travels with it
- the board translates from y 1080 to y 405
- the Cam-mode surf sentence cross-fades out as the board's heading and panels
  arrive
- the **ramp cards are common to both modes** and ride up with the board rather
  than being rebuilt
- the chrome row and verdict block do not move at all

Reverse for Up.

### Mode memory

The app opens in the mode it was last left in — the choice is made once, not at
every launch. After **10 minutes with no remote activity** it falls back to Cam
mode; the picture is the better thing to leave on a television.

### Status changes while Cam mode is up

A ramp closing changes the verdict line in place and flashes the accent bar
once. It does **not** open the board. A status change is not a reason to take
the beach off the screen.

## State

| State | Values | Notes |
|---|---|---|
| `mode` | `cam` \| `board` | Persisted across launches; reset to `cam` on 10-min idle |
| `focusedRow` | 0–3 in board mode | Row 0 is the cam caption strip |
| `activeCam` | one of 5 | Fixed geographic order, never reordered |
| `activeCity` | ramp city | Drives the heading and the five cards |
| `camOnline` | bool | Offline shows a struck-through name plus "offline since HH:MM" sub-label and promotes the next live cam |
| `isAfterDark` | bool | Palette and copy only — the feed itself is unchanged |

## Design tokens

**Status colors** (from `TvRampCard`)

| Status | Field | Border | Text | Mark | Word |
|---|---|---|---|---|---|
| open | `rgba(4,26,40,0.42)` | `rgba(255,255,255,0.28)` | `#ffffff` | `#2AE07A` | Open |
| limited | `#F5A214` | `#F5A214` | `#241500` | `#241500` | Limited |
| closed | `#C9301C` | `#C9301C` | `#ffffff` | `#ffffff` | Closed |
| overnight | `rgba(4,8,20,0.42)` | `rgba(255,255,255,0.20)` | `rgba(255,255,255,0.72)` | `rgba(255,255,255,0.45)` | Closed |

Status is carried by a **field**, not by colored text. `overnight` exists so an
expected end-of-driving close is not drawn in the same field as a storm or tide
closure — red is reserved for a closure nobody planned.

**Grounds**

| Token | Value |
|---|---|
| Day sky | `linear-gradient(170deg,#0E7B9F 0%,#2A9CBC 44%,#63BFD4 76%,#9BDCE7 100%)` |
| Night sky | `linear-gradient(165deg,#0A1228 0%,#2E2A52 48%,#6E3C58 100%)` |
| Cam well, day | `#0A1420` |
| Cam well, night | `#05080F` |
| Cam-mode ambient ground | `linear-gradient(to bottom, rgba(4,20,32,0.88), rgba(4,20,32,0.74))` |
| Panel fill | `rgba(4,26,40,0.42)` |
| Panel border | 2px `rgba(255,255,255,0.28)` |
| Section rule | 2px `rgba(255,255,255,0.42)` |
| Caption rule | 2px `rgba(255,255,255,0.34)` |

**Type** — Archivo throughout; weights 600/700/800 only.

| Size | Use |
|---|---|
| 80 / 800 | Verdict headline |
| 48 / 800 | Surf headline, board mode |
| 44 / 800 | Surf headline, cam mode |
| 40 / 800 | Ramp name on card |
| 38 / 800 | Ramp city heading |
| 34 / 800 | Weather values |
| 32 | Clock |
| 30 / 800 | Card status word; verdict detail line at 400 |
| 26 / 800 | Active cam name; brand |
| 24 | Card sub-line, secondary rows |
| 22 | Uppercase labels (0.08em tracking), hints — **floor** |

Numeric values use tabular figures. Corner radius is 0 everywhere except the
13px status dot.

**Spacing** — 64px side gutters; 18px grid gap; 16/18 row margins; 20/24px
panel padding.

## Assets

- `design/review/cam-banner.png` — 3222 × 680 still standing in for the live
  New Smyrna pier feed. Replace with the real stream; keep the 1:1 sizing rule.
- No icon set. The three glyphs used are typographic: `‹ ›`, `▾ ▴`, `☰`.

## Files

| File | What it is |
|---|---|
| `design/tvOS modes.dc.html` | All three screens plus the rules block |
| `design/TvRampCard.dc.html` | Ramp card — status field logic and colors |
| `design/TvDayPanel.dc.html` | Weekend day panel |
| `design/review/cam-banner.png` | Camera still |
| `screens/01-cam-mode.png` | 1920×1080 render |
| `screens/02-board-mode.png` | 1920×1080 render |
| `screens/03-cam-mode-after-dark.png` | 1920×1080 render |

Board mode's five states (mixed statuses, cam offline, after dark, Saturday,
the seven-day forecast overlay) are documented separately in
`design_handoff_tvos_v3/`. This package covers the mode switch; that one covers
what Board mode does across conditions. They share `TvRampCard` and
`TvDayPanel`.

## Open items

- **Night status across surfaces.** `overnight` is a tvOS-side status. iOS and
  web still show the same ramps as open after gates close. Three surfaces
  should agree before this ships.
- **Cam switching from the board.** With Left/Right bound to the focused row,
  the cam picker sits two Up presses away when the board is open. If cam
  switching turns out to be frequent in that state, revisit — but measure
  before designing around it.
