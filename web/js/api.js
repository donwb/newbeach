/**
 * API access. All paths are relative — the site is served by the same Go API
 * it talks to.
 */

async function fetchJSON(path, { timeoutMs = 15_000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(path, { signal: controller.signal });
    if (!res.ok) throw new Error(`${path} -> ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/**
 * The board's data in one sweep. Individual failures resolve to null so a
 * flaky endpoint degrades that section instead of the page; `ok` reports
 * whether the core ramps fetch succeeded (drives the stale bookkeeping).
 */
export async function loadAll() {
  const [ramps, tide, weather, activity, config, health, outlook, cameras] = await Promise.allSettled([
    fetchJSON('/api/v2/ramps'),
    fetchJSON('/api/v2/tides'),
    fetchJSON('/api/v2/weather'),
    fetchJSON('/api/v2/activity?limit=20'),
    fetchJSON('/api/v2/config'),
    fetchJSON('/api/v2/health'),
    fetchJSON('/api/v2/outlook'),
    fetchJSON('/api/v2/cameras'),
  ]);
  const value = (r) => (r.status === 'fulfilled' ? r.value : null);
  return {
    ramps: value(ramps),
    tide: value(tide),
    weather: value(weather),
    activity: value(activity),
    config: value(config),
    health: value(health),
    outlook: value(outlook),
    cameras: value(cameras),
    ok: ramps.status === 'fulfilled',
  };
}

/** The camera roster: { cameras: [{id, name, location, stream_url}], default_id }. */
export function loadCameras() {
  return fetchJSON('/api/v2/cameras');
}

export function loadTideChart() {
  return fetchJSON('/api/v2/tides/chart');
}

export function loadIntervals(rampId, hours = 48) {
  return fetchJSON(`/api/v2/ramps/${rampId}/intervals?hours=${hours}`);
}

export async function refreshVideo() {
  const res = await fetch('/api/v2/video/refresh', { method: 'POST' });
  if (!res.ok) throw new Error(`video refresh -> ${res.status}`);
  return res.json();
}
