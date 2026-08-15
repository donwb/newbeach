/**
 * Eastern-time formatting + status helpers. Pure functions, no DOM.
 *
 * All board copy renders in US Eastern regardless of the viewer's zone,
 * matching the server's TRMNL formatting and the Apple targets'
 * SinceFormatter so copy is identical across platforms.
 */

export const EASTERN = 'America/New_York';

const partsFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: EASTERN,
  year: 'numeric', month: 'numeric', day: 'numeric',
  hour: 'numeric', minute: 'numeric', second: 'numeric',
  hour12: false,
});

/** Calendar components of an instant as read in Eastern time. */
export function easternParts(date) {
  const parts = {};
  for (const { type, value } of partsFmt.formatToParts(date)) parts[type] = value;
  return {
    year: +parts.year, month: +parts.month, day: +parts.day,
    hour: +parts.hour % 24, minute: +parts.minute, second: +parts.second,
  };
}

/**
 * The UTC instant of the given Eastern wall-clock time. Converges in two
 * passes, which covers DST offsets either side of a transition.
 */
export function easternToUtc(year, month, day, hour = 0, minute = 0, second = 0) {
  const target = Date.UTC(year, month - 1, day, hour, minute, second);
  let guess = target;
  for (let i = 0; i < 2; i++) {
    const p = easternParts(new Date(guess));
    const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
    guess += target - asUtc;
  }
  return new Date(guess);
}

/** Midnight in Eastern time for the calendar day containing `date`. */
export function easternMidnight(date = new Date()) {
  const p = easternParts(date);
  return easternToUtc(p.year, p.month, p.day);
}

const clockFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: EASTERN, hour: 'numeric', minute: '2-digit', hour12: true,
});

/** "3:04 PM" — no leading zero on the hour. */
export function clock(date) {
  return clockFmt.format(date).replace(' ', ' ');
}

const monthDayFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: EASTERN, month: 'short', day: 'numeric',
});

/** "Jun 8" */
export function monthDay(date) {
  return monthDayFmt.format(date);
}

function sameEasternDay(a, b) {
  const pa = easternParts(a); const pb = easternParts(b);
  return pa.year === pb.year && pa.month === pb.month && pa.day === pb.day;
}

/**
 * When a status took effect, relative to now: a clock time for today
 * ("6:02 AM"), "Yest 4:11 PM" for yesterday, "Jun 8" for anything older.
 */
export function sinceString(date, now = new Date()) {
  if (sameEasternDay(date, now)) return clock(date);
  if (sameEasternDay(date, new Date(now.getTime() - 86_400_000))) return 'Yest ' + clock(date);
  return monthDay(date);
}

/** Mirrors the server's StatusToCategory. */
export function categoryFromStatus(status) {
  switch ((status || '').trim().toUpperCase()) {
    case 'OPEN': return 'open';
    case '4X4 ONLY':
    case 'CLOSING IN PROGRESS':
    case 'OPEN - ENTRANCE ONLY': return 'limited';
    default: return 'closed';
  }
}

/**
 * "BEACHWAY AV" → "Beachway Av", "3RD AV" → "3rd Av",
 * "INTERNATIONAL SPEEDWAY BLVD" → "International Speedway Blvd".
 * Ordinals keep their suffix lowercase; every other word is title-cased.
 */
export function prettyRampName(raw) {
  return (raw || '').trim().split(/\s+/).map((word) => {
    if (/^\d+(ST|ND|RD|TH)$/i.test(word)) return word.toLowerCase();
    return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
  }).join(' ');
}

/** Title-cases a city name: "NEW SMYRNA BEACH" → "New Smyrna Beach". */
export function titleCase(raw) {
  return (raw || '').toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
}

export function escapeHTML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
