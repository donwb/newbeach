/**
 * Sun position for a fixed location. Direct port of the shared package's
 * SolarCalculator.swift — low-precision NOAA-style model, good to a fraction
 * of a degree, driving the sun-following ground and sun times.
 *
 * Pure functions, no DOM. Dates in, Dates out; day boundaries are evaluated
 * in Eastern time to match the Swift `calendar.startOfDay` behavior.
 */

import { easternMidnight } from './format.js';

/** New Smyrna Beach, FL — the location the board is anchored to. */
export const NSB = { latitude: 29.0258, longitude: -80.927 };

/**
 * Standard sunrise/sunset altitude: −0.833° accounts for the sun's apparent
 * radius plus atmospheric refraction at the horizon.
 */
export const HORIZON_ALTITUDE = -0.833;

const rad = (d) => (d * Math.PI) / 180;
const deg = (r) => (r * 180) / Math.PI;

function normalizeDegrees(value) {
  const r = value % 360;
  return r < 0 ? r + 360 : r;
}

/**
 * The sun's altitude above the horizon, in degrees, at the given instant.
 * Negative means below the horizon (twilight or night).
 */
export function altitude(date = new Date(), { latitude, longitude } = NSB) {
  const julian = date.getTime() / 86_400_000 + 2_440_587.5;
  const n = julian - 2_451_545.0; // days since J2000.0

  const meanLongitude = normalizeDegrees(280.46 + 0.9856474 * n);
  const meanAnomaly = normalizeDegrees(357.528 + 0.9856003 * n);
  const eclipticLongitude = meanLongitude
    + 1.915 * Math.sin(rad(meanAnomaly))
    + 0.02 * Math.sin(rad(2 * meanAnomaly));
  const obliquity = 23.439 - 0.0000004 * n;

  const declination = Math.asin(Math.sin(rad(obliquity)) * Math.sin(rad(eclipticLongitude)));
  const rightAscension = Math.atan2(
    Math.cos(rad(obliquity)) * Math.sin(rad(eclipticLongitude)),
    Math.cos(rad(eclipticLongitude)),
  );

  const gmst = normalizeDegrees(280.46061837 + 360.98564736629 * n);
  const localSiderealTime = rad(gmst + longitude);
  const hourAngle = localSiderealTime - rightAscension;

  const lat = rad(latitude);
  const sinAltitude = Math.sin(lat) * Math.sin(declination)
    + Math.cos(lat) * Math.cos(declination) * Math.cos(hourAngle);
  return deg(Math.asin(Math.min(1, Math.max(-1, sinAltitude))));
}

/**
 * Whether the sun is climbing (morning) at the given instant. Compares the
 * altitude a few minutes on either side, so it's robust near the horizon.
 */
export function isRising(date = new Date(), location = NSB) {
  return altitude(new Date(date.getTime() + 300_000), location)
    > altitude(new Date(date.getTime() - 300_000), location);
}

const STEP_MS = 300_000; // 5-minute coarse scan, refined by bisection

function refineCrossing(from, to, target, rising, location) {
  let low = from.getTime();
  let high = to.getTime();
  for (let i = 0; i < 24; i++) {
    const mid = low + (high - low) / 2;
    const above = altitude(new Date(mid), location) >= target;
    if (above === rising) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return new Date(low + (high - low) / 2);
}

/**
 * Sunrise and sunset for the Eastern calendar day containing `date`.
 * Returns { sunrise, sunset }, either of which may be null.
 */
export function events(date = new Date(), location = NSB) {
  const startOfDay = easternMidnight(date);
  let sunrise = null;
  let sunset = null;

  let prevTime = startOfDay;
  let prevAltitude = altitude(startOfDay, location);
  for (let offset = STEP_MS; offset <= 86_400_000; offset += STEP_MS) {
    const time = new Date(startOfDay.getTime() + offset);
    const alt = altitude(time, location);

    if (sunrise === null && prevAltitude < HORIZON_ALTITUDE && alt >= HORIZON_ALTITUDE) {
      sunrise = refineCrossing(prevTime, time, HORIZON_ALTITUDE, true, location);
    }
    if (sunset === null && prevAltitude >= HORIZON_ALTITUDE && alt < HORIZON_ALTITUDE) {
      sunset = refineCrossing(prevTime, time, HORIZON_ALTITUDE, false, location);
    }

    prevTime = time;
    prevAltitude = alt;
  }
  return { sunrise, sunset };
}

/**
 * The first time on the Eastern calendar day containing `date` that the sun
 * crosses `targetAltitude` in the given direction — rising=true for the dawn
 * side, false for the dusk side. Null when no such crossing occurs that day.
 */
export function crossing(targetAltitude, rising, date = new Date(), location = NSB) {
  const startOfDay = easternMidnight(date);

  let prevTime = startOfDay;
  let prevAltitude = altitude(startOfDay, location);
  for (let offset = STEP_MS; offset <= 86_400_000; offset += STEP_MS) {
    const time = new Date(startOfDay.getTime() + offset);
    const alt = altitude(time, location);

    if (rising && prevAltitude < targetAltitude && alt >= targetAltitude) {
      return refineCrossing(prevTime, time, targetAltitude, true, location);
    }
    if (!rising && prevAltitude >= targetAltitude && alt < targetAltitude) {
      return refineCrossing(prevTime, time, targetAltitude, false, location);
    }

    prevTime = time;
    prevAltitude = alt;
  }
  return null;
}

/**
 * Solar noon — the instant of the sun's highest altitude — for the Eastern
 * calendar day containing `date`.
 */
export function solarNoon(date = new Date(), location = NSB) {
  const startOfDay = easternMidnight(date);

  let peakTime = startOfDay.getTime();
  let peakAltitude = -100;
  for (let offset = 0; offset <= 86_400_000; offset += STEP_MS) {
    const t = startOfDay.getTime() + offset;
    const alt = altitude(new Date(t), location);
    if (alt > peakAltitude) {
      peakAltitude = alt;
      peakTime = t;
    }
  }

  // Refine within ±one coarse step around the peak by golden-section search.
  let low = peakTime - STEP_MS;
  let high = peakTime + STEP_MS;
  for (let i = 0; i < 32; i++) {
    const span = high - low;
    const m1 = low + span / 3;
    const m2 = low + (2 * span) / 3;
    if (altitude(new Date(m1), location) < altitude(new Date(m2), location)) {
      low = m1;
    } else {
      high = m2;
    }
  }
  return new Date(low + (high - low) / 2);
}
