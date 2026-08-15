/**
 * Node smoke test for the pure ports. Run: node web/js/smoke.test.mjs
 * Mirrors the Swift package's SolarCalculatorTests / VerdictBuilderTests
 * fixtures so the JS ports and the Apple targets agree.
 */

import { altitude, isRising, events, crossing, solarNoon, HORIZON_ALTITUDE } from './solar.js';
import { forSun, dayness, groundState, cssRGB } from './sky.js';
import { buildVerdict, nextExtreme, reopenEstimate, durationText, spelled } from './verdict.js';
import { curvePoints, curveAnchors, heightAt } from './tide.js';
import { clock, sinceString, prettyRampName, categoryFromStatus, easternMidnight, easternToUtc } from './format.js';

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) {
    failures++;
    console.error(`FAIL ${label}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
  } else {
    console.log(`ok   ${label}`);
  }
}
function checkClose(label, actual, expected, tolerance) {
  if (Math.abs(actual - expected) > tolerance) {
    failures++;
    console.error(`FAIL ${label}: expected ${expected} ±${tolerance}, got ${actual}`);
  } else {
    console.log(`ok   ${label} (${actual.toFixed(3)})`);
  }
}

// --- solar (fixtures from SolarCalculatorTests.swift: 2026-06-18) ---
const summerDay = new Date(Date.UTC(2026, 5, 18, 18));
const { sunrise, sunset } = events(summerDay);

check('sunrise before sunset', sunrise < sunset, true);
const riseHourET = +new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hour12: false }).format(sunrise);
const setHourET = +new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hour12: false }).format(sunset);
check('summer sunrise lands in the 6 AM hour ET', riseHourET, 6);
check('summer sunset lands in the 8 PM hour ET', setHourET, 20);
checkClose('altitude at sunrise sits at the horizon', altitude(sunrise), HORIZON_ALTITUDE, 0.05);
check('sun high at 1 PM ET summer', altitude(easternToUtc(2026, 6, 18, 13)) > 60, true);
check('sun below horizon at midnight', altitude(easternMidnight(summerDay)) < 0, true);
check('rising at 8 AM', isRising(easternToUtc(2026, 6, 18, 8)), true);
check('setting at 6 PM', isRising(easternToUtc(2026, 6, 18, 18)), false);

const civilDawn = crossing(-6, true, summerDay);
check('civil dawn precedes sunrise', civilDawn < sunrise, true);
checkClose('civil dawn sits at -6 deg', altitude(civilDawn), -6, 0.05);
const noon = solarNoon(summerDay);
checkClose('solar noon within the day peak', altitude(noon), Math.max(altitude(noon), 80), 90); // sanity: > 80 in June
check('solar noon altitude > 80 in June', altitude(noon) > 80, true);

// --- sky ---
const noonPalette = forSun(48, true);
check('noon top hex', cssRGB(noonPalette.top), 'rgb(14, 127, 168)');
check('noon bot hex', cssRGB(noonPalette.bot), 'rgb(178, 230, 240)');
const nightPalette = forSun(-20, false);
check('deep night top hex', cssRGB(nightPalette.top), 'rgb(7, 10, 20)');
check('nautical dusk name', forSun(-9, false).name, 'Nautical dusk');
check('dayness at +8 and above', dayness(8), 1);
check('dayness at -4 and below', dayness(-4), 0);
checkClose('dayness midpoint at +2', dayness(2), 0.5, 1e-9);
check('groundState shape', Object.keys(groundState(summerDay)).sort(),
  ['altitude', 'dayness', 'phase', 'rising', 'sky', 'veil'].sort());

// --- verdict (fixtures from the handoff READMEs) ---
// Tide: dropping, low 4:57 PM, high 11:07 PM Eastern on 2026-08-14.
const now = easternToUtc(2026, 8, 14, 13, 30);
const tide = {
  tide_direction: 'Falling',
  predictions: [
    { time: easternToUtc(2026, 8, 14, 4, 40).toISOString(), type: 'L', height: -0.1 },
    { time: easternToUtc(2026, 8, 14, 10, 44).toISOString(), type: 'H', height: 2.8 },
    { time: easternToUtc(2026, 8, 14, 16, 57).toISOString(), type: 'L', height: -0.1 },
    { time: easternToUtc(2026, 8, 14, 23, 7).toISOString(), type: 'H', height: 2.8 },
  ],
};
const sunsetAt = new Date(now.getTime() + (5 * 60 + 41) * 60_000); // 5h 41m of light left
const ramp = (name, status, sinceET) => ({
  ramp_name: name,
  access_status: status,
  status_category: categoryFromStatus(status),
  status_since: sinceET ? sinceET.toISOString() : null,
});

const allOpen = buildVerdict({
  ramps: ['BEACHWAY AV', 'CRAWFORD RD', 'FLAGLER AV', '3RD AV', '27TH AV'].map((n) => ramp(n, 'OPEN', easternToUtc(2026, 8, 14, 6, 2))),
  tide, sunset: sunsetAt, now,
});
check('all-open headline', allOpen.headline, 'All five open');
check('all-open subline', allOpen.subline, 'Tide dropping · low 4:57 PM · 5h 41m of light left');

const crawfordClosed = buildVerdict({
  ramps: [
    ramp('BEACHWAY AV', 'OPEN', easternToUtc(2026, 8, 14, 6, 2)),
    ramp('CRAWFORD RD', 'CLOSED FOR HIGH TIDE', easternToUtc(2026, 8, 14, 12, 48)),
    ramp('FLAGLER AV', 'OPEN', easternToUtc(2026, 8, 14, 6, 2)),
    ramp('3RD AV', 'OPEN', easternToUtc(2026, 8, 14, 6, 2)),
    ramp('27TH AV', 'OPEN', easternToUtc(2026, 8, 13, 16, 11)),
  ],
  tide, sunset: sunsetAt, now,
});
check('closed headline', crawfordClosed.headline, 'Crawford Rd closed');
check('closed subline', crawfordClosed.subline,
  'Four open · closed for high tide since 12:48 PM · reopens near 6:27 PM');

const beachwayLimited = buildVerdict({
  ramps: [
    ramp('BEACHWAY AV', 'OPEN - ENTRANCE ONLY', easternToUtc(2026, 8, 14, 11, 15)),
    ramp('CRAWFORD RD', 'OPEN', easternToUtc(2026, 8, 14, 6, 2)),
    ramp('FLAGLER AV', 'OPEN', easternToUtc(2026, 8, 14, 6, 2)),
    ramp('3RD AV', 'OPEN', easternToUtc(2026, 8, 14, 6, 2)),
    ramp('27TH AV', 'OPEN', easternToUtc(2026, 8, 13, 16, 11)),
  ],
  tide: { ...tide, tide_direction: 'Rising' }, sunset: sunsetAt, now,
});
check('limited headline (rising tide)', beachwayLimited.headline, 'Beachway Av closing soon');
check('limited subline', beachwayLimited.subline,
  'Low tide 4:57 PM · entrance only since 11:15 AM · four others fully open');

const stale = buildVerdict({
  ramps: ['BEACHWAY AV', 'CRAWFORD RD', 'FLAGLER AV', '3RD AV', '27TH AV'].map((n) => ramp(n, 'OPEN', null)),
  tide, sunset: sunsetAt, now, dataAgeMs: 14 * 60_000,
});
check('stale headline', stale.headline, 'Last known: five open');
check('stale subline', stale.subline,
  'County feed unreachable for 14 minutes · retrying every 60s · do not trust this page');

const empty = buildVerdict({ ramps: [] });
check('empty headline', empty.headline, 'Waiting for county feed');

check('spelled 5', spelled(5), 'five');
check('spelled 14 falls back to digits', spelled(14), '14');
check('durationText 5h41m', durationText((5 * 60 + 41) * 60_000), '5h 41m');
const ne = nextExtreme(tide, now);
check('next extreme is the 4:57 PM low', ne.type + ' ' + clock(ne.time), 'L 4:57 PM');
// Falling-side closure (feed lag case): falls back to next low + 90m.
const reopen = reopenEstimate(ramp('CRAWFORD RD', 'CLOSED FOR HIGH TIDE', easternToUtc(2026, 8, 14, 12, 48)), tide, now);
check('reopen fallback = next low + 90m', clock(reopen), '6:27 PM');

// Rising-side closure: reopen when the falling curve returns to the
// closure height. Closed 10:00 AM at ~2.70 ft on the way up to the
// 10:44 AM 2.8 ft high; the curve falls back through 2.70 ft ~11:29 AM.
const reopenRising = reopenEstimate(
  ramp('CRAWFORD RD', 'CLOSED FOR HIGH TIDE', easternToUtc(2026, 8, 14, 10, 0)),
  tide, easternToUtc(2026, 8, 14, 10, 30),
);
check('reopen by closure height', clock(reopenRising), '11:29 AM');

// --- tide curve ---
const dayStart = easternMidnight(now).getTime();
const dayEnd = dayStart + 86_400_000;
const anchors = curveAnchors(tide.predictions, dayStart, dayEnd);
check('anchors extend past both ends', anchors[0].time <= dayStart && anchors[anchors.length - 1].time >= dayEnd, true);
const points = curvePoints(tide.predictions, dayStart, dayEnd, 10);
check('curve has ~145 points at 10-minute steps', points.length, 145);
checkClose('curve passes through the 10:44 AM high', heightAt(easternToUtc(2026, 8, 14, 10, 44).getTime(), anchors), 2.8, 0.01);
checkClose('curve passes through the 4:57 PM low', heightAt(easternToUtc(2026, 8, 14, 16, 57).getTime(), anchors), -0.1, 0.01);

// --- format ---
check('clock', clock(easternToUtc(2026, 8, 14, 15, 4)), '3:04 PM');
check('since today', sinceString(easternToUtc(2026, 8, 14, 6, 2), now), '6:02 AM');
check('since yesterday', sinceString(easternToUtc(2026, 8, 13, 16, 11), now), 'Yest 4:11 PM');
check('since older', sinceString(easternToUtc(2026, 6, 8, 9, 0), now), 'Jun 8');
check('pretty Beachway', prettyRampName('BEACHWAY AV'), 'Beachway Av');
check('pretty ordinal', prettyRampName('3RD AV'), '3rd Av');
check('pretty ISB wraps not truncates (name only)', prettyRampName('INTERNATIONAL SPEEDWAY BLVD'), 'International Speedway Blvd');
check('category entrance only', categoryFromStatus('OPEN - ENTRANCE ONLY'), 'limited');
check('category unknown defaults closed', categoryFromStatus('CLOSED - AT CAPACITY'), 'closed');

if (failures) {
  console.error(`\n${failures} failure(s)`);
  process.exit(1);
}
console.log('\nall checks passed');
