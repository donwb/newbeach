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
 * Estimated reopen time for a high-tide closure: the next low tide after
 * the closure, plus the reopen offset. Null when it doesn't apply or the
 * estimate is already in the past.
 */
export function reopenEstimate(ramp, tide, now) {
  if (normalized(ramp.access_status) !== 'CLOSED FOR HIGH TIDE') return null;
  const reference = statusSince(ramp) || now;
  const nextLow = (tide?.predictions || [])
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
