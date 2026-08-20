# Import note

Imported 2026-08-19 from the Claude Design project
(https://claude.ai/design/p/d3055b06-79c3-4983-9093-21701d882d73).

Checked in here: the handoff README and the design sources
(`tvOS modes.dc.html`, `TvRampCard.dc.html`, `TvDayPanel.dc.html`).
The 1920×1080 renders (`screens/*.png`), the `review/cam-banner.png`
camera still, and the shared `_ds` bundle + `support.js` the .dc.html
files reference live in the design project — the HTML here is reference
material, not a standalone page.

Implemented in `apple/BeachRamp/BeachRampTV/` (commit ea273ce,
flighted as build 22). The sibling `design_handoff_tvos_v3/` README
documents Board mode's states; this package covers the mode switch.
