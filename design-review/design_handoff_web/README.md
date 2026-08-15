# Handoff: web redesign — Beach Ramp Status

## Overview

A redesign of the PWA at `web/` (`index.html`, `app.js`, `styles.css`). Same data, same
five endpoints, same feature set — every element the current page has survives. What
changes is the order of the page, the styling system, and two new screens.

Four things:

1. **A verdict band at the top** that answers "can I get on the beach right now?" before
   the ramp grid is read. Lifted from the tvOS board.
2. **Status carried by the card field, not by a coloured pill or a left border.** Open is a
   white card, limited is a solid amber field, closed is a solid red field.
3. **A sun-following ground.** The page is Modernist off-white by day and becomes the tvOS
   sky at dusk and through the night, interpolated on sun altitude. No dark-mode toggle —
   the current `#theme-toggle` button and its `localStorage` branch are removed.
4. **A per-ramp detail screen**, which the current site does not have: today's status band,
   the ramp's closure threshold drawn on the tide curve, and the activity feed scoped to
   one ramp.

The four summary cards are gone; their counts moved onto the status filter buttons.

## About the design files

`Web.dc.html` is a **design reference created in HTML** — a prototype showing intended look
and behaviour. It is **not production code to copy**. It renders four frames side by side:
the board at 1440 and 390, and the ramp detail screen at 1440 and 390. Each frame is tagged
`data-screen-label` (`board-desktop`, `board-mobile`, `detail-desktop`, `detail-mobile`).

The target is the existing vanilla-JS PWA. Keep its architecture: static files served by
the Go API, `fetchJSON` against `/api/v2/*`, hls.js for the cam, service worker for offline.
The recommended change to the build is to **drop the Tailwind Play CDN** and write the page
against the Modernist token sheet instead — the design uses no utility classes and the CDN
is a render-blocking third-party script on a page people load in a truck on cell service.

Tweaks exposed as props at the top of the file (`data-props` on the `<script data-dc-script>`
tag), all editable there:

- `timeMinutes` — 0–1439, scrubs the sun through all 16 phases and the whole light-to-night ground
- `scenario` — `All open` | `Beachway closing soon` | `Crawford closed` | `Stale data` | `Cam offline`
- `ground` — `Auto` | `Light` | `Night`, to inspect either ground at any hour
- `groundTint` — 0–60%, how much of the sky's colour the daytime ground carries (default 30)

Read the tvOS handoff (`design_handoff_tvos_board/README.md`) first if you have not: it owns
the sixteen sun phases, the status tokens and the verdict-band copy rules. This document
only states where web differs.

## Fidelity

**High fidelity at both widths.** The mock is authored at 1440 and 390 CSS px, so px in the
mock maps 1:1 to CSS px in the browser. Type sizes, rule weights, and the two padding
scales (40/18) are final.

Not final: the cam banner is a static crop (`review/cam-banner.png`) standing in for the
hls.js `<video>`. Keep the existing player and its refresh logic.

---

## The ground — sun-following

This is the one genuinely new mechanic on web, and the reason there is no theme toggle.

Sun altitude drives a single scalar:

```
dayness = clamp((altitude + 4) / 12, 0, 1)      // 1 above +8°, 0 below −4° (civil dusk)
```

The page background is two layers. The sky gradient is exactly the tvOS one for the current
phase; the veil above it is the Modernist ground tinted toward the sky's own low colour:

```
sky   = linear-gradient(160deg, phase.top 0%, phase.mid 52%, phase.bot 100%)
veil  = mix(phase.bot, #f3f2f2, 0.70) at alpha = dayness
background-image: linear-gradient(veil, veil), sky;
background-color: #0A1420;   /* under both, for overscroll */
```

So at noon the page is a cool blue-grey off-white; near golden hour it warms to cream;
after civil dusk the veil is gone and the sky itself is the page. `background-attachment:
fixed` on `body` in production, so the gradient spans the viewport rather than a
3000px-tall document (the mock cannot show this — it draws each frame as a tall div).

Foreground tokens flip at `dayness < 0.5` (`night`), rather than interpolating, so text
never sits at an in-between contrast:

| Token | Day | Night |
|---|---|---|
| `--ink` | `#201e1d` | `#ffffff` |
| `--ink2` (secondary) | `rgba(32,30,29,0.62)` | `rgba(255,255,255,0.72)` |
| `--rule` (2px) | `rgba(32,30,29,0.85)` | `rgba(255,255,255,0.40)` |
| `--rule2` (1px) | `rgba(32,30,29,0.22)` | `rgba(255,255,255,0.22)` |
| `--accent` | `#ec3013` | `#FF6A4D` |
| `--tidefill` | `rgba(32,30,29,0.10)` | `rgba(255,255,255,0.14)` |

Red lightens at night because #ec3013 on a #0A1420 sky is under 3:1. Transition the ground
with `transition: background-image 2s ease-in-out` on the same 30-second tick tvOS uses;
`prefers-reduced-motion: reduce` drops the transition, not the theming.

## Status tokens

The tvOS trio holds at night. Day needs two darker variants — `#2AE07A` and `#E63A2B` on
off-white are 1.5:1 and 3.6:1 respectively.

| Role | Day | Night |
|---|---|---|
| open mark | `#0A7A42` | `#2AE07A` |
| open card fill | `#ffffff` | `rgba(4,24,34,0.55)` |
| open card border | `rgba(32,30,29,0.85)` | `rgba(255,255,255,0.30)` |
| limited fill / border | `#F5A214` | `#F5A214` |
| limited text + mark | `#241500` | `#241500` |
| closed fill / border | `#D22B18` | `#E63A2B` |
| closed text + mark | `#ffffff` | `#ffffff` |

Put all six in `BeachStatus` alongside the tvOS set rather than defining them in CSS twice.
**Radius is 0 everywhere** — the current `rounded-xl`, `rounded-full` pills and
`rounded-lg` video wrapper all go. Structure comes from 2px rules.

---

## Screen: the board

Order, top to bottom. Everything is flush left; page padding **40px desktop / 18px mobile**.

| Block | Desktop | Mobile |
|---|---|---|
| Header | 76px tall, brand + county, freshness chip + phase name + clock | 58px, dot + brand, clock |
| City selector | five tabs, 4px accent underline on active | one tappable control, `New Smyrna Beach ⌄` + "5 cities" |
| Verdict band | 1.55fr / 1fr — headline left, three stat cells right | stacked: headline, then three cells |
| Filter row | four count buttons + Favorites only | four compact count buttons |
| Ramp grid | 5 columns, gap 16, min-height 172 | full-width rows, gap 10 |
| Live cam | full width, aspect 1280/270 | same |
| Tide + forecast | 1.35fr / 1fr | stacked; forecast 2 columns |
| Recent changes | 130px / 1fr / 1fr rows | 88px / 1fr rows |
| Footer | sources left, updated right | one line |

**Breakpoints.** Below 720 use the mobile column. 720–1119, ramp grid
`repeat(auto-fill, minmax(300px, 1fr))` and the verdict band stacks. 1120 and up, five
across. Never crush a ramp name — `International Speedway Blvd` must wrap to two lines
rather than truncate.

**Verdict band.** An 18×70 solid rectangle in the verdict colour, then the headline at
62px/800, then the subline at 21px with `margin-left: 36px` so it aligns to the headline's
text edge, not the bar's. Mobile: 12×46 bar, 34px headline, 15px subline, 24px indent.
Headline copy follows the tvOS rule — name the exception if there is one, otherwise state
the count, never lead with a bare number.

**Stat cells** (Tide / Water · Air / Wind) are links, 2px top rule, label 11px uppercase,
value 29px/800, detail 14px, `›` in accent. On web they navigate to `/tide`, `/water`,
`/wind` rather than opening the tvOS full-screen panels — same content, real URLs.

**Filter row** carries the counts, which is why the four summary cards are gone: the active
filter is a solid accent field with white type, the rest are 2px-bordered. Favorites-only is
a toggle with a Lucide star; the per-card star stays as the setter (filled = favourite).

**Ramp card.** Index 12px uppercase 0.65 opacity, star top right, name 27px/800 with
`-0.015em`, then at the bottom a 12×22 status mark, the status word at 18px/800, and the
since line at 13px/0.7. Whole card is the link to the detail screen. Mobile row: name 22px
with the since line under it on the left, mark + status right, 15px.

**Stale state.** Cards drop to `opacity: 0.45`, each since line becomes `as of 2:09 PM`, the
freshness chip goes amber with `Stale · 14 min`, and the verdict reads
`Last known: five open` with `do not trust this page` in the subline. The current
`errorMessage` red banner is removed.

**Cam offline.** The 1280×270 rect becomes a flat `#0A1420` field with
`New Smyrna Beach cam offline` at 28px/800 and `Reconnecting — last frame 3:12 PM.` under
it. Keep `/api/v2/video/refresh` and the existing retry.

---

## Screen: ramp detail (new)

Route `/ramp/:id`. Header replaces the city tabs with a back link
(`← All New Smyrna ramps`) and a Favorite toggle.

1. **Hero.** Kicker `Ramp 01 · New Smyrna Beach` at 12px, name at 62px/800 (34 on mobile),
   then a full-width **status field band** in the ramp's own field colour: 16×40 mark,
   status at 34px/800, since line at 15px, and on the right the forward-looking line at
   17px — `Next high tide 11:07 PM — no closure expected today`, or
   `Reopens near 6:30 PM as the tide drops`, or `Expect full closure near high tide 4:57 PM`.
2. **Today's status band.** Midnight to midnight, one flex segment per state, weighted by
   duration, 18px tall, 2px gaps, in the status field colours. A 3px `--ink` now-marker
   overhangs 9px top and bottom. Under each segment, its start time at 15px/800 tabular and
   its label at 13px. This is the same position-on-a-line vocabulary as the sun ribbon and
   coastline rail on tvOS.
3. **Facts.** Four cells, 2px top rules: Address, Driving hours, Closes above, Nearest cam.
   `Closes above 2.4 ft tide` is per-ramp data the API does not currently return.
4. **Tide against this ramp.** The same 24-hour curve as the board, plus a **dashed 2px
   `#F5A214` line at the ramp's closure height** and a solid `--ink` now line. The dashed
   line is the point of the chart: it turns a tide reading into a decision.
5. **This ramp · last 48 hours.** The activity feed filtered to this ramp — 120px tabular
   time column, status at 16px/700.
6. **Nearest cam**, then **Other ramps** — the five ramps as 4px-top-rule cells, the current
   one accent and bold, so you can flip between ramps without going back.

Mobile keeps all six, in the same order, at the mobile type scale; Other ramps becomes a
2-column grid.

---

## Type

Archivo (`--font-heading` / `--font-body`), weights 400/600/700/800. Sizes in CSS px.

| Element | Desktop | Mobile |
|---|---|---|
| verdict / detail headline | 62 / 800 / −0.025em / lh 0.94 | 34 |
| ramp name (card) | 27 / 800 / −0.015em | 22 |
| detail status | 34 / 800 | 20 |
| stat value | 29 / 800 | 18 |
| forecast temp | 26 / 800 | 20 |
| tide extreme time | 22 / 800 | 14 |
| brand | 21 / 800 | 16 |
| verdict subline | 21 / 400 / lh 1.3 | 15 |
| clock | 20 tabular | 15 |
| fact value | 19 / 700 | 15 |
| status word | 18 / 800 | 15 |
| detail note | 17 | 14 |
| activity row | 16 | 13 |
| segment start time | 15 / 800 tabular | 12 |
| city tab | 14 / 600–800 / 0.04em | 15 (single control) |
| since line, section notes | 13 | 11–12 |
| kicker / label | 12 / 700 / 0.09em / uppercase | 10 |
| fact + extreme label | 11 / 700 / 0.09em | 9 |

Nothing below 9px, and nothing below 13px that a user needs to read to make a decision.
Tabular numerals (`font-variant-numeric: tabular-nums`) on every clock, time and tide time.

## Spacing

4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 22 · 24 · 34 · 36 · 40 · 56. Section rhythm is a
2px rule with 10px above the rule and 12–18px below it.

## Interaction states

- Cards, stat cells, city tabs, filter buttons: hover tint from the accent ramp
  (`color-mix(in oklch, var(--accent) 8%, transparent)`), pressed one step darker.
- Focus: `:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px }`. Never
  the browser default — this page gets used one-handed and keyboard-tabbed on desktop.
- Mobile hit targets: rows are 62px tall, the city control 46px, filter buttons 34px with
  a 44px touch area via padding. Nothing under 44px is tappable.
- `prefers-reduced-motion`: keep the ground transition off, keep everything else.

## API additions

Everything else the design needs is already in `/api/v2/ramps`, `/tides`, `/tides/chart`,
`/weather`, `/activity` and `/config`.

| Need | Where used |
|---|---|
| per-ramp closure height (ft) | detail facts + the dashed line on the tide chart |
| per-ramp status history, 48h | detail "last 48 hours" and today's status band |
| explicit per-city ramp order | board grid — NSB is Beachway, Crawford, Flagler, 3rd, 27th |
| ramp address + driving hours | detail facts (may already be in `config`) |
| data age / feed timestamp | freshness chip, stale state |

The status band needs history as intervals, not events, or it has to be derived client-side
by walking the event list backwards from now.

## Files

| File | What it is |
|---|---|
| `Web.dc.html` | The mock — four frames. Props at the top switch time, scenario, ground. |
| `screens/01–04` | Board and detail, desktop and mobile, midday. |
| `screens/05–06` | Board at night (9:30 PM, nautical dusk), desktop and mobile. |
| `screens/07–08` | Crawford Rd closed — board and detail. |
| `screens/09` | Beachway limited, mobile. |
| `screens/10` | Stale feed, desktop. |
| `screens/11` | Cam offline, desktop. |
| `review/cam-banner.png` | Cam placeholder crop. **Not a production asset.** |
| `_ds/modernist-…/styles.css`, `_ds_bundle.js` | The Modernist token sheet the mock loads. `styles.css` is the one to carry into the app. |
| `support.js` | Runtime for the mock. Not app code. |

Source files this design changes:

```
web/index.html     whole page structure; drop the Tailwind CDN and the theme toggle
web/styles.css     replace with the Modernist token sheet + this page's rules
web/app.js         verdict copy, sun-following ground, status fields, detail route, filters
web/sw.js          cache the new stylesheet; unchanged otherwise
```

## Out of scope

tvOS (done — see `design_handoff_tvos_board/`), iPhone, iPad, TRMNL X. The agreed sequence
was tvOS → web → iPadOS → iPhone, with tvOS naming the tokens the others inherit.
