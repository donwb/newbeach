/**
 * The sixteen sun phases and the sun-following ground.
 *
 * Palette anchors are a direct port of tvOS's SkyPalette (TVTheme.swift):
 * nine anchors per track keyed on sun altitude, night and noon shared, with
 * linear interpolation between bracketing anchors. The ground engine writes
 * the interpolated sky and the daytime veil into CSS custom properties on a
 * 30-second tick; `html[data-ground]` flips the foreground token set.
 *
 * Palette math is pure (Node-testable); only startGroundEngine touches DOM.
 */

import { altitude, isRising } from './solar.js';

function stop(hex) {
  return { r: (hex >> 16) & 0xff, g: (hex >> 8) & 0xff, b: hex & 0xff };
}

function mixStops(a, b, t) {
  return {
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
  };
}

export function cssRGB({ r, g, b }, alpha = 1) {
  const rr = Math.round(r); const gg = Math.round(g); const bb = Math.round(b);
  return alpha >= 1 ? `rgb(${rr}, ${gg}, ${bb})` : `rgba(${rr}, ${gg}, ${bb}, ${alpha.toFixed(3)})`;
}

function palette(name, top, mid, bot, dim) {
  return { name, top: stop(top), mid: stop(mid), bot: stop(bot), dim };
}

const NIGHT = palette('Night', 0x070a14, 0x101830, 0x1c2a44, 0.55);
const NOON = palette('Noon', 0x0e7fa8, 0x33b0cc, 0xb2e6f0, 1.0);

// Anchors keyed by sun altitude (degrees), ordered low → high. Twilight
// anchors sit at the standard solar angles: −18° astronomical, −13/−9/−5
// between, −0.8° at the visible sunrise/sunset.
const RISING_ANCHORS = [
  [-18, NIGHT],
  [-13, palette('Astronomical dawn', 0x080c1a, 0x141c38, 0x26304e, 0.58)],
  [-9, palette('Nautical dawn', 0x0c1230, 0x22265a, 0x3e3a6b, 0.64)],
  [-5, palette('Civil dawn', 0x142046, 0x4a4478, 0x8e6a82, 0.74)],
  [-0.8, palette('Sunrise', 0x1b2a52, 0x6a5c8e, 0xf2b07a, 0.85)],
  [6, palette('Golden morning', 0x17456b, 0x3e7c9e, 0xf0c48e, 0.92)],
  [20, palette('Morning', 0x0e6e8c, 0x1f9bbf, 0x9cd8e8, 1.0)],
  [34, palette('Late morning', 0x0e779a, 0x29a6c6, 0xa8deec, 1.0)],
  [48, NOON],
];

const FALLING_ANCHORS = [
  [-18, NIGHT],
  [-13, palette('Astronomical dusk', 0x080d1c, 0x1a1c3a, 0x3a2942, 0.62)],
  [-9, palette('Nautical dusk', 0x0a1228, 0x2e2a52, 0x6e3c58, 0.72)],
  [-5, palette('Civil dusk', 0x0e2840, 0x5e4055, 0xb45c50, 0.8)],
  [-0.8, palette('Sunset', 0x123a52, 0x9a5e50, 0xf08a46, 0.9)],
  [6, palette('Golden evening', 0x145066, 0x6f7a66, 0xe8a85e, 0.94)],
  [20, palette('Afternoon', 0x10657f, 0x3f957e, 0xd9bc72, 0.98)],
  [34, palette('Early afternoon', 0x0f7294, 0x39a5a5, 0xc5d6b1, 0.99)],
  [48, NOON],
];

/**
 * The palette for a given sun altitude (degrees) and direction, linearly
 * interpolated between bracketing anchors so transitions are continuous.
 * The phase `name` comes from the nearer anchor.
 */
export function forSun(sunAltitude, rising) {
  const anchors = rising ? RISING_ANCHORS : FALLING_ANCHORS;
  if (sunAltitude <= anchors[0][0]) return anchors[0][1];
  if (sunAltitude >= anchors[anchors.length - 1][0]) return anchors[anchors.length - 1][1];

  for (let i = 0; i < anchors.length - 1; i++) {
    const [loAlt, lo] = anchors[i];
    const [hiAlt, hi] = anchors[i + 1];
    if (sunAltitude >= loAlt && sunAltitude <= hiAlt) {
      const t = (sunAltitude - loAlt) / (hiAlt - loAlt);
      return {
        name: t < 0.5 ? lo.name : hi.name,
        top: mixStops(lo.top, hi.top, t),
        mid: mixStops(lo.mid, hi.mid, t),
        bot: mixStops(lo.bot, hi.bot, t),
        dim: lo.dim + (hi.dim - lo.dim) * t,
      };
    }
  }
  return anchors[anchors.length - 1][1];
}

/** Modernist off-white, the daytime page ground. */
const PAPER = stop(0xf3f2f2);

/**
 * dayness: 1 above +8° sun, 0 below −4° (civil dusk), linear between.
 * Drives the veil alpha and, at 0.5, the day/night foreground token flip.
 */
export function dayness(sunAltitude) {
  return Math.max(0, Math.min(1, (sunAltitude + 4) / 12));
}

/**
 * Everything the ground needs for one instant: the sky stops, the veil
 * (paper tinted 30% toward the sky's low color), dayness, and phase name.
 */
export function groundState(now = new Date()) {
  const alt = altitude(now);
  const rising = isRising(now);
  const p = forSun(alt, rising);
  const d = dayness(alt);
  return {
    phase: p.name,
    altitude: alt,
    rising,
    dayness: d,
    sky: { top: cssRGB(p.top), mid: cssRGB(p.mid), bot: cssRGB(p.bot) },
    veil: cssRGB(mixStops(p.bot, PAPER, 0.7), d),
  };
}

/**
 * Starts the 30-second ground tick, writing CSS custom properties and the
 * data-ground attribute onto <html>. `clockFn` exists so the dev scrubber
 * can freeze time. Returns the applied state; calls `onTick(state)` after
 * each application for header clock/phase updates.
 */
export function startGroundEngine({ clockFn = () => new Date(), onTick = null } = {}) {
  const apply = () => {
    const state = groundState(clockFn());
    const root = document.documentElement;
    root.style.setProperty('--sky-top', state.sky.top);
    root.style.setProperty('--sky-mid', state.sky.mid);
    root.style.setProperty('--sky-bot', state.sky.bot);
    root.style.setProperty('--veil', state.veil);
    root.dataset.ground = state.dayness < 0.5 ? 'night' : 'day';
    if (onTick) onTick(state);
    return state;
  };

  const state = apply();
  const timer = setInterval(apply, 30_000);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) apply();
  });
  return { state, refresh: apply, stop: () => clearInterval(timer) };
}
