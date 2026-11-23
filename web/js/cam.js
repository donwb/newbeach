/**
 * The beach cam. Player mechanics carried over from the previous app.js:
 * Safari plays HLS natively, everyone else goes through hls.js, and fatal
 * errors ask the API to re-resolve the stream URL behind a single-flight gate
 * with a 30s client throttle (the server has its own cooldown too).
 *
 * The still fallback (2026-11-23): when the relay reports the selected cam
 * dark (`online: false` — overnight quiet hours, or YouTube refusing the home
 * restreamer, docs/CAM-RELAY.md) and the roster carries a `still_url` (the
 * YouTube live thumbnail, refreshed every ~4–6 min), the frame shows that
 * still instead of a black "Reconnecting" panel, and no HLS is attached — a
 * dark relay just 404s. A live stream that dies mid-watch also falls back to
 * the still while it retries. No dark-frame check on web: the thumbnail has
 * no CORS headers, so the canvas would be tainted — and night frames aren't
 * really black anyway (moon, lights).
 *
 * The kicker's mode badge says which one you're looking at: a red dot +
 * LIVE once video is actually playing, STILL for the photo, OFFLINE when
 * neither, and a plain CAM while a stream connects.
 */

import { refreshVideo } from './api.js';
import { clock } from './format.js';

/** How often the still is re-fetched while shown (YouTube refreshes every ~4–6 min). */
export const STILL_REFRESH_MS = 120_000;

const camState = {
  hls: null,
  lastRefreshAttempt: 0,
  refreshInflight: false,
  currentUrl: null,
  lastFrameAt: null,
  offline: false,
  stillUrl: null,     // the selected cam's still, or null
  stillShown: false,  // a still frame is on screen
  stillTimer: null,
  stillLoadToken: 0,  // drops a preload that finishes after the source moved on
  els: null, // { frame, video, still, mode, offline, offlineNote }
  resolveUrl: null, // async () => freshest URL for the *selected* cam, or null
};

/**
 * Pick the active camera from the /api/v2/cameras payload: the user's pick,
 * else the roster default, else the first. Null when the roster is empty.
 *
 * An explicit pick is sticky even when that camera is dark — the viewer asked
 * for it, and it may come back while they watch. A pick we made for them is
 * not: opening on a known-offline camera when live ones are sitting in the
 * roster just shows a "Reconnecting" panel to someone who never chose it
 * (NSB went dark upstream 2026-09-19 while it was the roster default, and
 * every first-time visitor landed on the empty player). `online` is the relay
 * health poller's call; treat a missing flag as live so an older payload, or
 * a roster where the poller has not reported yet, behaves as it always did.
 * With nothing live, a cam with a still beats one with nothing (the default
 * first) — overnight every cam is still-only.
 */
export function pickCamera(roster, selectedId) {
  const cams = roster?.cameras;
  if (!cams?.length) return null;

  const chosen = cams.find((c) => c.id === selectedId);
  if (chosen) return chosen;

  const fallback = cams.find((c) => c.id === roster.default_id) || cams[0];
  if (fallback.online !== false) return fallback;
  return cams.find((c) => c.online !== false)
    || (fallback.still_url ? fallback : cams.find((c) => c.still_url))
    || fallback;
}

/**
 * What the frame should show for `camera`: `{ url, stillUrl }`, where a
 * non-null `url` means try live video. A cam the relay reports dark plays
 * its still instead — but with no still to show, it still tries the stream
 * (the old behavior: the "Reconnecting" panel, recovering on its own).
 * `legacyUrl` is config.video_stream_url, for a server with no roster.
 */
export function camSource(camera, legacyUrl = null) {
  const stillUrl = camera?.still_url || null;
  const streamUrl = camera ? camera.stream_url || null : legacyUrl || null;
  const dark = camera?.online === false && stillUrl;
  return { url: dark ? null : streamUrl, stillUrl };
}

/** True when a chip should be selectable: there's video or a still to show. */
export function camSelectable(camera) {
  return Boolean(camera?.stream_url || camera?.still_url);
}

/**
 * The still URL with a minute-granular cache-buster, replacing any existing
 * `t`. The thumbnail is served max-age=300, which on top of YouTube's own
 * refresh would let a browser show a frame ~10 minutes old.
 */
export function stillSrc(url, now = Date.now()) {
  const u = new URL(url);
  u.searchParams.set('t', String(Math.floor(now / 60_000)));
  return u.toString();
}

function tryPlay(video) {
  const p = video.play();
  if (p && typeof p.catch === 'function') {
    p.catch(() => { /* autoplay rejection — user can press play */ });
  }
}

const MODE_LABELS = { live: 'Live', still: 'Still', offline: 'Offline', connecting: 'Cam' };

function setMode(mode) {
  const el = camState.els?.mode;
  if (!el) return;
  el.className = `cam-mode cam-mode--${mode}`;
  el.textContent = MODE_LABELS[mode];
  el.title = mode === 'still'
    ? 'Live video is off; this photo refreshes every few minutes.'
    : '';
}

function markOnline() {
  camState.offline = false;
  camState.lastFrameAt = new Date();
  hideStill();
  camState.els?.offline?.setAttribute('hidden', '');
  setMode('live');
}

/** The stream failed: cover with the still if there is one, else the panel. */
function markOffline() {
  if (!camState.els) return;
  camState.offline = true;
  if (camState.stillUrl) {
    showStill();
    return;
  }
  showOfflinePanel();
}

function showOfflinePanel() {
  hideStill();
  camState.els.offline.removeAttribute('hidden');
  camState.els.offlineNote.textContent = camState.lastFrameAt
    ? `Reconnecting — last frame ${clock(camState.lastFrameAt)}.`
    : 'Reconnecting.';
  setMode('offline');
}

// ----- still -----

function showStill() {
  if (!camState.stillTimer) {
    camState.stillTimer = setInterval(loadStill, STILL_REFRESH_MS);
  }
  loadStill();
}

/**
 * Preload the frame off-screen and swap it in only once it decoded, so a
 * refresh never flashes empty; the first frame fades in (CSS). A failed load
 * keeps whatever frame is up, or falls to the offline panel if none is.
 */
function loadStill() {
  const els = camState.els;
  const base = camState.stillUrl;
  if (!els?.still || !base) return;
  const token = ++camState.stillLoadToken;
  const src = stillSrc(base);
  const img = new Image();
  img.onload = () => {
    if (token !== camState.stillLoadToken || camState.els !== els) return;
    els.still.src = src;
    els.still.removeAttribute('hidden');
    // Next frame, so the opacity transition runs from the hidden state.
    requestAnimationFrame(() => els.still.classList.add('is-shown'));
    camState.stillShown = true;
    els.offline.setAttribute('hidden', '');
    setMode('still');
  };
  img.onerror = () => {
    if (token !== camState.stillLoadToken || camState.els !== els) return;
    if (!camState.stillShown) showOfflinePanel();
  };
  img.src = src;
}

function hideStill() {
  if (camState.stillTimer) {
    clearInterval(camState.stillTimer);
    camState.stillTimer = null;
  }
  camState.stillLoadToken++;
  camState.stillShown = false;
  const still = camState.els?.still;
  if (still) {
    still.classList.remove('is-shown');
    still.setAttribute('hidden', '');
    still.removeAttribute('src');
  }
}

// ----- stream -----

function detachStream() {
  if (camState.hls) {
    camState.hls.destroy();
    camState.hls = null;
  }
  const video = camState.els?.video;
  if (video && (video.getAttribute('src') || video.currentSrc)) {
    video.onerror = null;
    video.removeAttribute('src');
    video.load();
  }
  camState.currentUrl = null;
}

function attachStream(video, url) {
  camState.currentUrl = url;
  if (camState.hls) {
    camState.hls.destroy();
    camState.hls = null;
  }
  // Until frames arrive the still (if one is up) stays as cover.
  if (!camState.stillShown) setMode('connecting');

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
      // The roster refresh may have flipped the cam to still-only, which
      // setCamSource already handled; only reattach while we're live.
      if (url && camState.els && camState.currentUrl) attachStream(camState.els.video, url);
    })
    .catch(() => { /* swallow — server safety-poll will catch up */ })
    .finally(() => {
      camState.refreshInflight = false;
    });
}

/**
 * Binds the cam to a mounted .cam-frame and shows `source` (see camSource).
 * `elements`: { frame, video, still, mode, offline, offlineNote }.
 * `resolveUrl` (optional, async) returns the freshest URL for the selected
 * cam on fatal errors. `forceOffline` pins the offline panel (QA scenario).
 */
export function mountCam(elements, source, { forceOffline = false, resolveUrl = null } = {}) {
  camState.els = elements;
  camState.resolveUrl = resolveUrl;

  elements.video.addEventListener('playing', markOnline);

  if (forceOffline) {
    camState.stillUrl = null;
    showOfflinePanel();
    return;
  }
  setCamSource(source);
}

/**
 * Called on every roster/selection update; idempotent, so the 60s poll never
 * restarts playback or re-fetches a still that's already up.
 */
export function setCamSource({ url, stillUrl } = {}) {
  if (!camState.els) return;
  const stillChanged = (stillUrl || null) !== camState.stillUrl;
  camState.stillUrl = stillUrl || null;

  if (url) {
    // A different cam's still must not cover this one while it connects.
    if (stillChanged && camState.stillShown) hideStill();
    if (url !== camState.currentUrl) attachStream(camState.els.video, url);
    else if (camState.offline && !camState.stillShown && camState.stillUrl) showStill();
    return;
  }

  // No live video: stop pulling from a dark relay.
  detachStream();
  camState.offline = true;
  if (camState.stillUrl) {
    if (stillChanged || !camState.stillShown) {
      if (stillChanged) hideStill();
      showStill();
    }
  } else {
    showOfflinePanel();
  }
}

export function unmountCam() {
  hideStill();
  if (camState.hls) {
    camState.hls.destroy();
    camState.hls = null;
  }
  camState.els = null;
  camState.currentUrl = null;
  camState.resolveUrl = null;
  camState.stillUrl = null;
  camState.offline = false;
}
