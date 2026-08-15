/**
 * Cosine-interpolated tide curve between NOAA high/low extremes:
 *
 *     h(t) = h0 + (h1 − h0) · (1 − cos(π·u)) / 2,   u = (t − t0)/(t1 − t0)
 *
 * Direct port of the shared package's TideCurve.swift. NOAA's day extremes
 * don't cover midnight-to-first-extreme, so the curve extends past both ends
 * with reflected phantom extremes (same spacing as the nearest real pair,
 * height copied from the opposite-type neighbor).
 *
 * Curve math is pure; the SVG renderer builds a markup string (Node-safe).
 */

/** Height at a single moment, interpolated between the bracketing anchors. */
export function heightAt(timeMs, anchors) {
  if (!anchors.length) return null;
  const first = anchors[0];
  const last = anchors[anchors.length - 1];
  if (timeMs <= first.time) return first.height;
  if (timeMs >= last.time) return last.height;

  for (let i = 1; i < anchors.length; i++) {
    if (timeMs <= anchors[i].time) {
      const a = anchors[i - 1];
      const b = anchors[i];
      const span = b.time - a.time;
      if (span <= 0) return a.height;
      const u = (timeMs - a.time) / span;
      return a.height + (b.height - a.height) * (1 - Math.cos(Math.PI * u)) / 2;
    }
  }
  return last.height;
}

/**
 * Anchors covering [startMs, endMs]: the usable extremes plus reflected
 * phantoms extending past both ends. Extremes are v2 /tides predictions
 * ({ time, type, height }); entries without heights are ignored.
 */
export function curveAnchors(extremes, startMs, endMs) {
  const anchors = (extremes || [])
    .filter((p) => p.height != null)
    .map((p) => ({ time: new Date(p.time).getTime(), height: p.height }))
    .sort((a, b) => a.time - b.time);

  if (anchors.length < 2) return [];

  while (anchors[0].time > startMs) {
    const spacing = anchors[1].time - anchors[0].time;
    if (spacing <= 0) break;
    anchors.unshift({ time: anchors[0].time - spacing, height: anchors[1].height });
  }
  while (anchors[anchors.length - 1].time < endMs) {
    const last = anchors[anchors.length - 1];
    const spacing = last.time - anchors[anchors.length - 2].time;
    if (spacing <= 0) break;
    anchors.push({ time: last.time + spacing, height: anchors[anchors.length - 2].height });
  }
  return anchors;
}

/**
 * Samples the curve every `stepMinutes` across [startMs, endMs]. Fewer than
 * two usable extremes yields []. Returns [{ time (ms), height (ft) }].
 */
export function curvePoints(extremes, startMs, endMs, stepMinutes = 10) {
  const anchors = curveAnchors(extremes, startMs, endMs);
  if (anchors.length < 2 || stepMinutes <= 0) return [];

  const step = stepMinutes * 60_000;
  const points = [];
  for (let t = startMs; t <= endMs; t += step) {
    const h = heightAt(t, anchors);
    if (h != null) points.push({ time: t, height: h });
  }
  return points;
}

const VIEW_W = 1000;
const VIEW_H = 300;

/**
 * The 24-hour tide chart as an SVG string. Strokes and fills come from the
 * page tokens (`--ink`, `--tidefill`, `--c-limited`), so the day/night flip
 * restyles the chart with zero JS. Extremes render as HTML cells below the
 * chart, not inside it, which keeps the SVG free to scale uniformly.
 *
 * opts: { points, nowMs?, closureFt? (dashed line when set), nowStroke? }
 */
export function renderTideChartSVG({ points, nowMs = null, closureFt = null, nowStroke = 'limited' }) {
  if (!points || points.length < 2) return '';

  const t0 = points[0].time;
  const t1 = points[points.length - 1].time;
  let hMin = Math.min(...points.map((p) => p.height));
  let hMax = Math.max(...points.map((p) => p.height));
  if (closureFt != null) {
    hMin = Math.min(hMin, closureFt);
    hMax = Math.max(hMax, closureFt);
  }
  const padY = Math.max(0.3, (hMax - hMin) * 0.12);
  hMin -= padY;
  hMax += padY;

  const x = (t) => ((t - t0) / (t1 - t0)) * VIEW_W;
  const y = (h) => VIEW_H - ((h - hMin) / (hMax - hMin)) * VIEW_H;

  const path = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'}${x(p.time).toFixed(1)},${y(p.height).toFixed(1)}`)
    .join('');
  const area = `${path}L${VIEW_W},${VIEW_H}L0,${VIEW_H}Z`;

  const lines = [];
  if (closureFt != null) {
    const cy = y(closureFt).toFixed(1);
    lines.push(`<line x1="0" y1="${cy}" x2="${VIEW_W}" y2="${cy}" stroke="var(--c-limited)" stroke-width="2" stroke-dasharray="8 6" vector-effect="non-scaling-stroke"/>`);
  }
  if (nowMs != null && nowMs >= t0 && nowMs <= t1) {
    const nx = x(nowMs).toFixed(1);
    const stroke = nowStroke === 'ink' ? 'var(--ink)' : 'var(--c-limited)';
    lines.push(`<line x1="${nx}" y1="0" x2="${nx}" y2="${VIEW_H}" stroke="${stroke}" stroke-width="3" vector-effect="non-scaling-stroke"/>`);
  }

  return `<svg viewBox="0 0 ${VIEW_W} ${VIEW_H}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Tide curve, midnight to midnight">
    <path d="${area}" fill="var(--tidefill)"/>
    <path d="${path}" fill="none" stroke="var(--ink)" stroke-width="2.5" vector-effect="non-scaling-stroke"/>
    ${lines.join('\n    ')}
  </svg>`;
}
