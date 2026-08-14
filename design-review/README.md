# Design Review Packet

Everything needed to give Beach Ramp Status "the design treatment" — current-state
screenshots of every surface plus a design brief. Point Claude Design (or any
designer) at this folder.

- **[DESIGN-BRIEF.md](DESIGN-BRIEF.md)** — product context, current visual language,
  per-platform notes, known inconsistencies, and constraints a redesign must respect.
- **`screenshots/`** — current-state captures, all taken 2026-08-14 against the live
  production API (real ramp/tide/weather data and the live beach cam relay).

## Screenshot inventory

| File | What it shows |
|---|---|
| `web/web-desktop-light.png` | Website, 1440×900 viewport, light (above the fold) |
| `web/web-desktop-dark.png` | Website, 1440×900 viewport, dark (above the fold) |
| `web/web-desktop-light-fullpage.png` | Website, full page, light — all sections |
| `web/web-desktop-dark-fullpage.png` | Website, full page, dark — all sections |
| `web/web-mobile-light-fullpage.png` | Website on iPhone-size viewport, full page, light |
| `web/web-mobile-dark-fullpage.png` | Website on iPhone-size viewport, full page, dark |
| `web/web-tablet-light.png` | Website at 1024×768, full page, light |
| `ios/ios-iphone-home-light.png` | iOS app (iPhone 17 Pro), top of page: header, filters, counts, ramp list |
| `ios/ios-iphone-home-dark.png` | Same, dark mode |
| `ios/ios-iphone-tide-light.png` | iOS scrolled: tide chart + weather forecast |
| `ios/ios-iphone-tide-dark.png` | Same, dark mode |
| `ios/ios-iphone-weather-light.png` | iOS bottom of page: weather + water temperature (page ends here — no cam on iPhone) |
| `ipados/ipad-home-light.png` | iPadOS (iPad Pro 11" M5, portrait): two-column layout + camera switcher rail + live cam |
| `ipados/ipad-home-dark.png` | Same, dark mode |
| `tvos/tvos-home.png` | tvOS (Apple TV 4K): dashboard with ramp tiles, tide/weather, daylight timeline, live cam, CoastlineRail camera picker |
| `watchos/watch-home.png` | watchOS (Series 11 46mm): counts + ramp list (watch is dark-only) |
| `trmnl/trmnl-x-preview.png` | TRMNL X e-ink template rendered in the local preview harness with **sample data** (not live) |

Not captured: iPad landscape, tvOS camera-switching states, watch scrolled views,
and the TRMNL OG (800×480, 1-bit) template — the OG has no local preview harness;
see `trmnl/template.html` for its markup.

## How these were captured (reproducible)

- **Web:** Playwright driving system Chrome against `https://beach.donwb.com`
  (`colorScheme` emulation for dark mode).
- **Apple platforms:** `xcodebuild` (schemes `BeachRamp`, `BeachRampTV`,
  `BeachRampWatch Watch App`) → `xcrun simctl install/launch` →
  `xcrun simctl ui <device> appearance light|dark` → `xcrun simctl io <device> screenshot`.
  Note: the watch scheme's deployment target (26.5) was newer than the installed
  watchOS runtime (26.2), so the watch build used `WATCHOS_DEPLOYMENT_TARGET=26.2`.
- **TRMNL X:** static-serve the `trmnl/` dir, open `preview-x.html`, screenshot the
  1040×780 `#frame` element.
