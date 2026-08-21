/**
 * Central state with a tiny pub/sub. Views mount once and subscribe to the
 * keys they render; the poll loop and UI ticks write through `set`, which
 * notifies only the subscribers of keys that actually changed.
 */

export function createStore() {
  const state = {
    ramps: null,          // /api/v2/ramps payload
    tide: null,           // /api/v2/tides payload
    weather: null,        // /api/v2/weather payload
    activity: null,       // /api/v2/activity payload
    config: null,         // /api/v2/config payload
    health: null,         // /api/v2/health payload
    outlook: null,        // /api/v2/outlook payload (server-side prediction)
    weekend: null,        // /api/v2/outlook/weekend payload (multi-day verdicts)
    cameras: null,        // /api/v2/cameras payload (roster + default_id)
    selectedCameraId: null, // user's cam pick; null until set, then sticky for the session
    chart: null,          // /api/v2/tides/chart payload
    dataAgeMs: null,      // grown client-side between polls
    stale: false,
    selectedCity: 'NEW SMYRNA BEACH',
    selectedStatus: 'all',
    now: new Date(),      // the UI clock (scrubber-aware)
  };

  const subscribers = new Map(); // key -> Set<fn>

  function subscribe(keys, fn) {
    for (const key of Array.isArray(keys) ? keys : [keys]) {
      if (!subscribers.has(key)) subscribers.set(key, new Set());
      subscribers.get(key).add(fn);
    }
    return () => {
      for (const set of subscribers.values()) set.delete(fn);
    };
  }

  function notify(keys) {
    const seen = new Set();
    for (const key of keys) {
      for (const fn of subscribers.get(key) || []) {
        if (!seen.has(fn)) {
          seen.add(fn);
          fn(state);
        }
      }
    }
  }

  function set(patch) {
    const changed = [];
    for (const [key, value] of Object.entries(patch)) {
      if (state[key] !== value) {
        state[key] = value;
        changed.push(key);
      }
    }
    if (changed.length) notify(changed);
  }

  return { state, set, subscribe };
}
