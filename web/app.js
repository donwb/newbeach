/**
 * Beach Ramp Status — Volusia County, FL
 * Boot module: store, poll loop, sun-following ground, router.
 *
 * Dev scrubber (harmless in production):
 *   ?t=HH:MM                     freeze the clock at an Eastern wall time
 *   ?scenario=stale|closed|limited|camoff   force a board state
 */

import { createStore } from './js/store.js';
import { loadAll } from './js/api.js';
import { startGroundEngine } from './js/sky.js';
import { createRouter } from './js/router.js';
import { createBoardView } from './js/views/board.js';
import { createDetailView } from './js/views/detail.js';
import { createStatView } from './js/views/stat.js';
import { STALE_THRESHOLD_MS } from './js/verdict.js';
import { easternParts, easternToUtc } from './js/format.js';

const params = new URLSearchParams(location.search);
const scenario = params.get('scenario');

// ---- clock (scrubber-aware) ----

function makeClock() {
  const t = params.get('t');
  if (t && /^\d{1,2}:\d{2}$/.test(t)) {
    const [h, m] = t.split(':').map(Number);
    const p = easternParts(new Date());
    const frozen = easternToUtc(p.year, p.month, p.day, h, m);
    return () => new Date(frozen);
  }
  return () => new Date();
}
const clockFn = makeClock();

// ---- store + ground ----

const store = createStore();
store.set({ now: clockFn() });

let lastPollStamp = null; // ms epoch of the feed's last successful poll

function recomputeStale() {
  if (scenario === 'stale') {
    store.set({ dataAgeMs: 14 * 60_000, stale: true });
    document.documentElement.dataset.stale = 'true';
    return;
  }
  if (lastPollStamp == null) return;
  const age = Date.now() - lastPollStamp;
  const stale = age > STALE_THRESHOLD_MS;
  store.set({ dataAgeMs: age, stale });
  document.documentElement.dataset.stale = String(stale);
}

startGroundEngine({
  clockFn,
  onTick: (ground) => {
    store.set({ now: clockFn(), phase: ground.phase });
    recomputeStale();
  },
});

// ---- scenario transforms (dev) ----

function applyScenario(ramps) {
  if (!ramps || !scenario) return ramps;
  const patch = (name, status) => ramps.map((r) => (
    r.ramp_name === name
      ? { ...r, access_status: status, status_category: null, status_since: new Date(Date.now() - 47 * 60_000).toISOString() }
      : r
  ));
  if (scenario === 'closed') {
    return patch('CRAWFORD RD', 'CLOSED FOR HIGH TIDE')
      .map((r) => (r.ramp_name === 'CRAWFORD RD' ? { ...r, status_category: 'closed' } : r));
  }
  if (scenario === 'limited') {
    return patch('BEACHWAY AV', 'OPEN - ENTRANCE ONLY')
      .map((r) => (r.ramp_name === 'BEACHWAY AV' ? { ...r, status_category: 'limited' } : r));
  }
  return ramps;
}

// ---- poll loop ----

async function poll() {
  const data = await loadAll();
  const patch = {};
  if (data.ramps) patch.ramps = applyScenario(data.ramps);
  if (data.tide) patch.tide = data.tide;
  if (data.weather) patch.weather = data.weather;
  if (data.activity) patch.activity = data.activity;
  if (data.config) patch.config = data.config;
  if (data.outlook) patch.outlook = data.outlook;
  if (data.cameras) patch.cameras = data.cameras;
  if (data.health) {
    patch.health = data.health;
    const stamp = data.health.ingester?.last_poll_at;
    const ms = stamp ? new Date(stamp).getTime() : NaN;
    // Right after a server boot the ingester hasn't polled yet and health
    // reports Go's zero time (0001-01-01) — an insane stamp must not count.
    if (Number.isFinite(ms) && ms > Date.UTC(2020, 0, 1)) {
      lastPollStamp = ms;
    } else if (data.ok) {
      lastPollStamp = Date.now();
    }
  } else if (data.ok) {
    // Ramps came through but health didn't — treat the fetch itself as proof of life.
    lastPollStamp = Date.now();
  }
  store.set(patch);
  recomputeStale();
}

poll();
setInterval(poll, 60_000);

// ---- router ----

const router = createRouter({
  container: document.getElementById('view'),
  routes: {
    board: createBoardView(store),
    detail: createDetailView(store),
    stat: createStatView(store),
  },
});
router.start();

// ---- service worker ----

if ('serviceWorker' in navigator) {
  if (params.has('nosw')) {
    // Dev escape hatch: ?nosw unregisters the worker and clears its caches
    // so local iteration always hits the filesystem.
    navigator.serviceWorker.getRegistrations().then((regs) => regs.forEach((r) => r.unregister()));
    if (window.caches) caches.keys().then((keys) => keys.forEach((k) => caches.delete(k)));
  } else {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch(() => { /* offline support is best-effort */ });
    });
  }
}
