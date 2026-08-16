/**
 * The live beach cam. Player mechanics carried over from the previous
 * app.js: Safari plays HLS natively, everyone else goes through hls.js, and
 * fatal errors ask the API to re-resolve the stream URL behind a
 * single-flight gate with a 30s client throttle (the server has its own
 * cooldown too). New here: the offline field state — a flat #0A1420 panel
 * naming the cam and when the last frame arrived.
 */

import { refreshVideo } from './api.js';
import { clock } from './format.js';

const camState = {
  hls: null,
  lastRefreshAttempt: 0,
  refreshInflight: false,
  currentUrl: null,
  lastFrameAt: null,
  offline: false,
  els: null, // { frame, video, offline, offlineNote }
  resolveUrl: null, // async () => freshest URL for the *selected* cam, or null
};

/**
 * Pick the active camera from the /api/v2/cameras payload: the user's pick,
 * else the roster default, else the first. Null when the roster is empty.
 */
export function pickCamera(roster, selectedId) {
  const cams = roster?.cameras;
  if (!cams?.length) return null;
  return cams.find((c) => c.id === selectedId)
    || cams.find((c) => c.id === roster.default_id)
    || cams[0];
}

function tryPlay(video) {
  const p = video.play();
  if (p && typeof p.catch === 'function') {
    p.catch(() => { /* autoplay rejection — user can press play */ });
  }
}

function markOnline() {
  camState.offline = false;
  camState.lastFrameAt = new Date();
  camState.els?.offline?.setAttribute('hidden', '');
}

function markOffline() {
  if (!camState.els) return;
  camState.offline = true;
  camState.els.offline.removeAttribute('hidden');
  camState.els.offlineNote.textContent = camState.lastFrameAt
    ? `Reconnecting — last frame ${clock(camState.lastFrameAt)}.`
    : 'Reconnecting.';
}

function attachStream(video, url) {
  camState.currentUrl = url;
  if (camState.hls) {
    camState.hls.destroy();
    camState.hls = null;
  }

  // hls.js first: some Chromium builds answer "maybe" to the native HLS
  // canPlayType probe and then stall, so only browsers without MSE (iOS
  // Safari) should take the native branch below.
  if (window.Hls && Hls.isSupported()) {
    const hls = new Hls({ maxBufferLength: 30 });
    camState.hls = hls;
    hls.loadSource(url);
    hls.attachMedia(video);
    hls.on(Hls.Events.MANIFEST_PARSED, () => tryPlay(video));
    hls.on(Hls.Events.ERROR, (_event, data) => {
      // Only act on fatal errors — most network/media errors self-recover.
      if (data?.fatal) {
        markOffline();
        requestRefresh();
      }
    });
    return;
  }

  // No MSE (iOS Safari): native HLS playback.
  video.src = url;
  video.onerror = () => {
    markOffline();
    requestRefresh();
  };
  video.addEventListener('loadedmetadata', () => tryPlay(video), { once: true });
}

function requestRefresh() {
  const now = Date.now();
  if (camState.refreshInflight) return;
  if (now - camState.lastRefreshAttempt < 30_000) return;
  camState.lastRefreshAttempt = now;
  camState.refreshInflight = true;

  // Roster-aware path: the view resolves the freshest URL for the cam the
  // user actually selected (re-fetching /api/v2/cameras). The legacy
  // /video/refresh fallback only knows the default cam, so it would silently
  // flip a non-default selection back to NSB.
  const resolve = camState.resolveUrl
    ? camState.resolveUrl()
    : refreshVideo().then((payload) => payload?.video_stream_url);

  Promise.resolve(resolve)
    .then((url) => {
      if (url && camState.els) attachStream(camState.els.video, url);
    })
    .catch(() => { /* swallow — server safety-poll will catch up */ })
    .finally(() => {
      camState.refreshInflight = false;
    });
}

/**
 * Binds the cam to a mounted .cam-frame. `elements`:
 * { frame, video, offline, offlineNote }. Re-binding with the same URL is a
 * no-op so the 60s poll doesn't restart playback. `resolveUrl` (optional,
 * async) returns the freshest URL for the selected cam on fatal errors.
 */
export function mountCam(elements, url, { forceOffline = false, resolveUrl = null } = {}) {
  camState.els = elements;
  camState.resolveUrl = resolveUrl;

  elements.video.addEventListener('playing', markOnline);

  if (forceOffline || !url) {
    markOffline();
    return;
  }
  if (url === camState.currentUrl && !camState.offline) return;
  attachStream(elements.video, url);
}

/** Called on poll updates: reattach only when the URL actually changed. */
export function updateCamUrl(url) {
  if (!camState.els || !url || url === camState.currentUrl) return;
  attachStream(camState.els.video, url);
}

export function unmountCam() {
  if (camState.hls) {
    camState.hls.destroy();
    camState.hls = null;
  }
  camState.els = null;
  camState.currentUrl = null;
  camState.resolveUrl = null;
}
