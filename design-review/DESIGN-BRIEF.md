# Beach Ramp Status — Design Brief

Context for a first real design pass across all surfaces. Screenshots live in
`screenshots/` (see [README.md](README.md) for the inventory). The app has never had
a deliberate design treatment — every surface evolved feature-first.

## What the product is

Real-time beach access ramp status (open / limited / closed), tide predictions,
water temperature, weather, and live beach cams for Volusia County, Florida —
primary focus New Smyrna Beach. Users are locals deciding *right now* whether to
drive onto the beach: the core question is "can I get on, and what's the tide doing?"
Data updates every ~60s from Volusia County GIS; tides/water temp from NOAA.
Full product spec: [`../REQUIREMENTS.md`](../REQUIREMENTS.md). Engineering
conventions: [`../CLAUDE.md`](../CLAUDE.md).

## Surfaces

| Surface | Stack | State |
|---|---|---|
| Web (`beach.donwb.com`) | Vanilla HTML/JS + Tailwind, single page, served by the Go API | Light + dark (manual toggle + `prefers-color-scheme`), mobile-first |
| iOS (iPhone) | SwiftUI, single scrolling page | Light + dark; **no beach cam section** (iPad/tvOS have it) |
| iPadOS | Same app, adaptive two-column layout | Has multi-camera switcher rail + live cam player |
| tvOS | SwiftUI dashboard, ambient "glanceable" display | Multi-cam via bottom CoastlineRail picker; blue-gradient look of its own |
| watchOS | SwiftUI list | Minimal: counts + ramp list |
| TRMNL X e-ink | Liquid template, 1040×780 canvas, 16-gray | Editorial black-on-cream look; active platform |
| TRMNL OG e-ink | Liquid template, 800×480, 1-bit | Abbreviated status strings (>12 chars) |

Shared SwiftUI code: `apple/BeachRamp/` — views in `Views/` (Header, RampCard,
FilterBar, TideChart, WaterTemp, WeatherSection, BeachCam, CameraSwitcher), plus
`BeachRampTV/` and `BeachRampWatch Watch App/`. Web markup/styles are inline in
`web/index.html` + `web/app.js`.

## Current visual language (such as it is)

- **Brand color:** teal — web uses Tailwind teal (`#0d9488` primary, `#14b8a6`,
  `#0f766e`, `#115e59`, `#134e4a`); iOS header is a teal/emerald gradient.
- **Web light background:** warm cream/sand (`#fdf6e3`, `#fefcf3`, `#f9e8c0`,
  `#f4d68a` accents) — a beachy personality the native apps don't share (iOS light
  mode sits on stock system grouped gray).
- **Status semantics (must survive any redesign):** open = green, limited =
  amber/yellow, closed = red, everywhere including e-ink (where it becomes
  weight/inversion instead of color).
- **Typography:** system fonts everywhere (SF on Apple, Tailwind default stack on
  web, TRMNL system faces). No brand type, no logo/wordmark; app icon lives in
  `apple/BeachRamp/BeachRamp/Assets.xcassets`.
- **Tone:** utility dashboard. Cards + pills on every platform, but the radii,
  spacing, and elevation treatments were each invented independently.

## Known inconsistencies / design debt (observed in the screenshots)

1. **Three personalities:** web = warm sand + teal; iOS = stock-iOS gray + teal
   gradient header; tvOS = ocean-blue gradient with glassy tiles. Nothing ties them
   together beyond "teal-ish and green checkmarks."
2. **Purple/violet accents leak in:** tide chart Low labels and weather storm icons
   render purple/magenta (SF Symbol multicolor defaults) against the teal palette.
3. **Feature asymmetry reads as design asymmetry:** iPhone has no cam; web has a
   single cam while iPad/tvOS have the multi-cam switcher; the web "Recent
   Activity" feed exists nowhere else.
4. **Web summary tiles** (Total/Open/Limited/Closed) use left color-bars while iOS
   uses colored numbers on gray cards — same data, different grammar.
5. **iPad is mostly a widened iPhone** — the two-column layout works but spacing,
   card sizing, and the cam rail feel unresolved; landscape untested.
6. **Dark modes were derived, not designed** — web dark is a straight slate flip of
   the light theme; the warm-sand character disappears entirely.
7. **No iconography system:** mix of SF Symbols (Apple), emoji-ish inline SVG (web),
   and ad-hoc glyphs (TRMNL).

## Constraints a redesign must respect

- **Glanceability first.** Primary use is a 3-second check, often outdoors in
  sunlight (phone) or across the room (TV, e-ink). Status color + ramp name must
  dominate at every size.
- **E-ink:** TRMNL OG is 1-bit; X is 16-gray rendered at 1040×780 CSS px then
  upscaled 1.8×. High contrast, no grays for small/thin type, no color. Status
  strings >12 chars need the abbreviated form on OG.
- **tvOS focus model:** tiles need visible focus/hover states; the cam player is
  the hero and shouldn't be crowded out.
- **Web:** no frameworks, Tailwind only, single `index.html` + `app.js`, no build
  step. Dark mode must keep both the manual toggle and `prefers-color-scheme`.
- **SwiftUI only** on Apple platforms; shared components live in the `BeachStatus`
  package; SF Symbols for icons; every view keeps a working preview.
- **Live data layout tolerance:** ramp names vary ("27th Av" → "International
  Speedway Blvd"), status strings vary ("Open" → "Closed for High Tide",
  "Open - Entrance Only", "4x4 Only"), ramp counts per city vary (5 in NSB, more
  county-wide). Nothing can assume short strings or fixed counts.
- **The cam feeds are 16:9-ish panoramic HLS streams** (stable URLs at
  `cams.donwb.com`) — players should reserve that aspect and expect occasional
  downtime (design an offline state; none exists today).

## What a design pass should deliver (suggested scope)

1. A small cross-platform design language: palette (resolve teal vs. sand vs.
   TV-blue), type scale, card/pill grammar, status-color tokens, icon rules —
   expressed as Tailwind tokens for web and a SwiftUI theme for Apple.
2. Redesigned web page (it's the most visible surface and the most dated).
3. iOS/iPadOS alignment to the same language, including whether iPhone gets the cam.
4. tvOS: keep its ambient character but bring it into the family.
5. States nobody designed: loading, stale-data, cam-offline, empty filter results.
6. Optional: wordmark/app-icon refresh so the brand exists outside the UI.
