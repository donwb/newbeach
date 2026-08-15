/**
 * The board's one-line answer to "can I get on the beach right now?".
 *
 * Direct port of the shared package's VerdictBuilder.swift. The copy rule:
 * name the exception if there is one, otherwise state the count. Never lead
 * with a bare numeral — counts are spelled out.
 *
 * Pure functions, no DOM. Ramps are the raw /api/v2/ramps objects.
 */

import { clock, sinceString, prettyRampName, categoryFromStatus } from './format.js';
import { curveAnchors, heightAt } from './tide.js';

/** Data older than this is stale: two missed 60s refresh cycles plus jitter. */
export const STALE_THRESHOLD_MS = 150_000;

/**
 * High-tide closures reopen roughly this long after the following low tide
 * (county practice, not physics — tuned to observed reopenings).
 */
export const REOPEN_OFFSET_AFTER_LOW_MS = 90 * 60_000;

const normalized = (status) => (status || '').trim().toUpperCase();

const capitalizedFirst = (s) => s.charAt(0).toUpperCase() + s.slice(1);

/** Spelled-out count for verdict copy: 5 → "five". Digits past twelve. */
export function spelled(n) {
  const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six',
    'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
  return n >= 0 && n <= 12 ? words[n] : String(n);
}

/** "5h 41m" / "5h" / "41m" */
export function durationText(ms) {
  const totalMinutes = Math.floor(ms / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return `${hours}h ${minutes}m`;
  if (hours > 0) return `${hours}h`;
  return `${minutes}m`;
}

/**
 * Lowercase status phrase for sublines: "CLOSED FOR HIGH TIDE" →
 * "closed for high tide", "OPEN - ENTRANCE ONLY" → "entrance only".
 */
export function statusPhrase(accessStatus) {
  let phrase = normalized(accessStatus).toLowerCase();
  if (phrase.startsWith('open - ')) phrase = phrase.slice('open - '.length);
  return phrase.replaceAll(' - ', ' — ');
}

function category(ramp) {
  return ramp.status_category || categoryFromStatus(ramp.access_status);
}

function displayName(ramp) {
  return prettyRampName(ramp.ramp_name);
}

function statusSince(ramp) {
  return ramp.status_since ? new Date(ramp.status_since) : null;
}

/** Whether the v2 tide payload reads as rising. */
export function tideIsRising(tide) {
  return /ris/i.test(tide?.tide_direction || '');
}

/**
 * The first tide extreme after `now`. Predictions are the v2 /tides shape:
 * [{ time, type: "H"|"L", height }]. Returns { time: Date, type, label }.
 */
export function nextExtreme(tide, now) {
  const upcoming = (tide?.predictions || [])
    .map((p) => ({ ...p, time: new Date(p.time) }))
    .filter((p) => p.time > now)
    .sort((a, b) => a.time - b.time);
  if (!upcoming.length) return null;
  const next = upcoming[0];
  return { ...next, label: next.type === 'H' ? 'High' : 'Low' };
}

/**
 * When a ramp closes on the rising tide, the water that forced the closure
 * recedes to the same level on the way down — so the reopen estimate is
 * the falling curve's return to the tide height at closure time.
 * Returns null when the closure wasn't on the rising side (or the curve
 * can't be built), letting the caller fall back to the low-tide heuristic.
 */
function reopenFromClosureHeight(predictions, closedAt) {
  const closedMs = closedAt.getTime();
  const anchors = curveAnchors(predictions, closedMs - 6 * 3_600_000, closedMs + 30 * 3_600_000);
  if (anchors.length < 2) return null;
  const closureHeight = heightAt(closedMs, anchors);
  if (closureHeight == null) return null;

  // Only meaningful when the closure precedes a high — i.e. the tide was
  // still coming up. A closure logged on the falling side is feed lag.
  const nextExt = predictions
    .map((p) => ({ ...p, time: new Date(p.time) }))
    .filter((p) => p.time.getTime() > closedMs)
    .sort((a, b) => a.time - b.time)[0];
  if (!nextExt || nextExt.type !== 'H') return null;

  // Walk forward from the crest until the curve falls back through the
  // closure height, then bisect the bracketing step.
  const step = 5 * 60_000;
  let prev = nextExt.time.getTime();
  for (let t = prev + step; t <= closedMs + 30 * 3_600_000; t += step) {
    const h = heightAt(t, anchors);
    if (h != null && h <= closureHeight) {
      let lo = prev;
      let hi = t;
      for (let i = 0; i < 20; i++) {
        const mid = lo + (hi - lo) / 2;
        if (heightAt(mid, anchors) <= closureHeight) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      return new Date(hi);
    }
    prev = t;
  }
  return null;
}

/**
 * Estimated reopen time for a high-tide closure. Preferred estimate: the
 * falling tide's return to the height at which the ramp closed. Fallback
 * (closure on the falling side, or the crossing already passed): the next
 * low tide plus the county-practice offset. Null when nothing applies or
 * every estimate is already in the past.
 */
export function reopenEstimate(ramp, tide, now) {
  if (normalized(ramp.access_status) !== 'CLOSED FOR HIGH TIDE') return null;
  const predictions = tide?.predictions;
  if (!predictions?.length) return null;
  const reference = statusSince(ramp) || now;

  const byHeight = reopenFromClosureHeight(predictions, reference);
  if (byHeight && byHeight > now) return byHeight;

  const nextLow = predictions
    .map((p) => ({ ...p, time: new Date(p.time) }))
    .filter((p) => p.type === 'L' && p.time > reference)
    .sort((a, b) => a.time - b.time)[0];
  if (!nextLow) return null;
  const reopen = new Date(nextLow.time.getTime() + REOPEN_OFFSET_AFTER_LOW_MS);
  return reopen > now ? reopen : null;
}

/**
 * Headline verb for a single limited ramp. Entrance-only while the tide is
 * rising means a full closure is coming — say so.
 */
function limitedHeadlinePhrase(ramp, tide) {
  const status = normalized(ramp.access_status);
  if (status === 'CLOSING IN PROGRESS') return 'closing now';
  if (status === 'OPEN - ENTRANCE ONLY') {
    return tide && tideIsRising(tide) ? 'closing soon' : 'entrance only';
  }
  if (status === '4X4 ONLY') return '4x4 only';
  return 'limited';
}

function allOpenVerdict(count, tide, sunset, now) {
  const parts = [];
  if (tide) {
    parts.push(`Tide ${tideIsRising(tide) ? 'rising' : 'dropping'}`);
    const next = nextExtreme(tide, now);
    if (next) parts.push(`${next.label.toLowerCase()} ${clock(next.time)}`);
  }
  if (sunset && sunset > now) {
    parts.push(`${durationText(sunset - now)} of light left`);
  }
  return {
    category: 'open',
    headline: `All ${spelled(count)} open`,
    subline: parts.join(' · '),
  };
}

function closedVerdict(closed, limited, open, total, tide, now) {
  let headline;
  if (closed.length === 1) {
    headline = `${displayName(closed[0])} closed`;
  } else if (closed.length === 2) {
    headline = `${displayName(closed[0])} & ${displayName(closed[1])} closed`;
  } else if (closed.length === total) {
    headline = `All ${spelled(total)} closed`;
  } else {
    headline = `${capitalizedFirst(spelled(closed.length))} ramps closed`;
  }

  const parts = [];
  if (open.length) parts.push(`${capitalizedFirst(spelled(open.length))} open`);
  if (limited.length) parts.push(`${spelled(limited.length)} limited`);
  if (closed.length === 1) {
    const ramp = closed[0];
    let segment = statusPhrase(ramp.access_status);
    const since = statusSince(ramp);
    if (since) segment += ` since ${sinceString(since, now)}`;
    parts.push(segment);
    const reopen = reopenEstimate(ramp, tide, now);
    if (reopen) parts.push(`reopens near ${clock(reopen)}`);
  }
  if (!parts.length) parts.push('none open');
  return { category: 'closed', headline, subline: parts.join(' · ') };
}

function limitedVerdict(limited, open, tide, now) {
  let headline;
  if (limited.length === 1) {
    headline = `${displayName(limited[0])} ${limitedHeadlinePhrase(limited[0], tide)}`;
  } else if (limited.length === 2) {
    headline = `${displayName(limited[0])} & ${displayName(limited[1])} limited`;
  } else {
    headline = `${capitalizedFirst(spelled(limited.length))} ramps limited`;
  }

  const parts = [];
  const next = tide ? nextExtreme(tide, now) : null;
  if (next) parts.push(`${next.label} tide ${clock(next.time)}`);
  if (limited.length === 1) {
    const ramp = limited[0];
    let segment = statusPhrase(ramp.access_status);
    const since = statusSince(ramp);
    if (since) segment += ` since ${sinceString(since, now)}`;
    parts.push(segment);
  }
  if (open.length) {
    parts.push(`${spelled(open.length)} other${open.length === 1 ? '' : 's'} fully open`);
  }
  return { category: 'limited', headline, subline: parts.join(' · ') };
}

function staleVerdict(ramps, dataAgeMs) {
  const closed = ramps.filter((r) => category(r) === 'closed');
  const limited = ramps.filter((r) => category(r) === 'limited');

  let summary;
  if (closed.length === 1) {
    summary = `${displayName(closed[0])} closed`;
  } else if (closed.length > 1) {
    summary = `${spelled(closed.length)} closed`;
  } else if (limited.length === 1) {
    summary = `${displayName(limited[0])} ${statusPhrase(limited[0].access_status)}`;
  } else if (limited.length > 1) {
    summary = `${spelled(limited.length)} limited`;
  } else {
    summary = `${spelled(ramps.length)} open`;
  }

  const minutes = Math.max(1, Math.round(dataAgeMs / 60_000));
  return {
    category: 'limited',
    headline: `Last known: ${summary}`,
    subline: `County feed unreachable for ${minutes} minute${minutes === 1 ? '' : 's'} · retrying every 60s · do not trust this page`,
  };
}

/**
 * Generates verdict copy from ramp, tide, and sun facts.
 * Precedence: empty → stale → closed → limited → all open.
 */
export function buildVerdict({ ramps, tide = null, sunset = null, now = new Date(), dataAgeMs = null }) {
  if (!ramps || !ramps.length) {
    return {
      category: 'limited',
      headline: 'Waiting for county feed',
      subline: 'No ramp data yet · retrying every 60s',
    };
  }

  if (dataAgeMs != null && dataAgeMs > STALE_THRESHOLD_MS) {
    return staleVerdict(ramps, dataAgeMs);
  }

  const closed = ramps.filter((r) => category(r) === 'closed');
  const limited = ramps.filter((r) => category(r) === 'limited');
  const open = ramps.filter((r) => category(r) === 'open');

  if (closed.length) return closedVerdict(closed, limited, open, ramps.length, tide, now);
  if (limited.length) return limitedVerdict(limited, open, tide, now);
  return allOpenVerdict(ramps.length, tide, sunset, now);
}
