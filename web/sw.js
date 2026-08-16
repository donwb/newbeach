/**
 * Beach Ramp Status service worker.
 *
 * CACHE_NAME must be bumped on EVERY deploy that changes any precached
 * asset — the fetch handler is cache-first for static files, so a stale
 * cache otherwise masks the new code until this constant changes.
 */
const CACHE_NAME = 'beach-ramps-v9';

const STATIC_ASSETS = [
  '/',
  '/app.js?v=5',
  '/styles.css?v=5',
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
      .then(() => self.clients.claim()),
  );
});

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

  // Navigations: network-first, falling back to the cached shell — this is
  // what makes /ramp/:id and /tide open offline and installed.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => caches.match('/')),
    );
    return;
  }

  // Static assets: cache-first.
  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request)),
  );
});
