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
};

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

  // Safari (and iOS) play HLS natively.
  if (video.canPlayType('application/vnd.apple.mpegurl')) {
    video.src = url;
    video.onerror = () => {
      markOffline();
      requestRefresh();
    };
    video.addEventListener('loadedmetadata', () => tryPlay(video), { once: true });
    return;
  }

  // Other browsers: hls.js.
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

  // No HLS support at all — direct src, let the browser do what it can.
  video.src = url;
}

function requestRefresh() {
  const now = Date.now();
  if (camState.refreshInflight) return;
  if (now - camState.lastRefreshAttempt < 30_000) return;
  camState.lastRefreshAttempt = now;
  camState.refreshInflight = true;

  refreshVideo()
    .then((payload) => {
      const url = payload?.video_stream_url;
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
 * no-op so the 60s poll doesn't restart playback.
 */
export function mountCam(elements, url, { forceOffline = false } = {}) {
  camState.els = elements;

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
}
