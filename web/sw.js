/**
 * Beach Ramp Status service worker.
 *
 * CACHE_NAME must be bumped on EVERY deploy that changes any precached
 * asset — the fetch handler is cache-first for static files, so a stale
 * cache otherwise masks the new code until this constant changes.
 */
const CACHE_NAME = 'beach-ramps-v22';

const STATIC_ASSETS = [
  '/',
  '/app.js?v=14',
  '/styles.css?v=14',
  '/manifest.json',
  '/icons/icon.svg',
  '/js/api.js',
  '/js/cam.js',
  '/js/format.js',
  '/js/order.js',
  '/js/router.js',
  '/js/sky.js',
  '/js/solar.js',
  '/js/store.js',
  '/js/tide.js',
  '/js/verdict.js',
  '/js/views/board.js',
  '/js/views/detail.js',
  '/js/views/stat.js',
  '/fonts/archivo-400.woff2',
  '/fonts/archivo-600.woff2',
  '/fonts/archivo-700.woff2',
  '/fonts/archivo-800.woff2',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      // cache: 'reload' bypasses the browser HTTP cache, so the precache
      // always holds what the server has now, not a heuristically-fresh copy.
      .then((cache) => cache.addAll(STATIC_ASSETS.map((u) => new Request(u, { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)),
      ))
      // Let the browser own navigation requests again — see handleNavigation.
      .then(() => self.registration.navigationPreload?.enable())
      .then(() => self.clients.claim()),
  );
});

// Navigations: network-first, falling back to the cached shell — this is what
// makes /ramp/:id and /tide open offline and installed.
//
// The network hit comes from navigationPreload rather than a worker-issued
// fetch(), so the browser owns the request instead of this worker. Chrome was
// measured to preserve the Referer either way, but a worker-forwarded
// navigation reaches the server as Sec-Fetch-Dest: empty and leaves referrer
// handling to each browser's discretion; preload keeps it an ordinary document
// navigation, which is what the page_views log grades attribution on. It is
// also the point of the API: the request starts before this worker boots.
// fetch() remains the fallback for browsers without preload (pre-Safari 15.4).
async function handleNavigation(event) {
  try {
    const preloaded = await event.preloadResponse;
    if (preloaded) return preloaded;
  } catch {
    return (await caches.match('/')) || Response.error();
  }
  try {
    return await fetch(event.request);
  } catch {
    return (await caches.match('/')) || Response.error();
  }
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // API: network-first with cache fallback, so brief offline windows show
  // the last known data.
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => caches.match(request)),
    );
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigation(event));
    return;
  }

  // Static assets: cache-first.
  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request)),
  );
});
