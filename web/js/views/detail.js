/**
 * Ramp detail screen (/ramp/:id): hero + status field band with a
 * forward-looking line, today's midnight-to-midnight status band from the
 * intervals endpoint, the tide curve against this ramp, the last-48-hours
 * feed, the nearest cam, and the other-ramps switcher.
 *
 * v1 ships without the facts row and the dashed closure-height line — that
 * per-ramp metadata doesn't exist yet; renderTideChartSVG already supports
 * `closureFt` for when it does.
 */

import { escapeHTML, prettyRampName, titleCase, sinceString, clock, categoryFromStatus, easternMidnight } from '../format.js';
import { statusPhrase, nextExtreme, tideIsRising, reopenEstimate } from '../verdict.js';
import { sortRampsForCity } from '../order.js';
import { curvePoints, renderTideChartSVG } from '../tide.js';
import { loadIntervals, loadCameras } from '../api.js';
import { mountCam, updateCamUrl, unmountCam, pickCamera } from '../cam.js';

const capFirst = (s) => s.charAt(0).toUpperCase() + s.slice(1);

export function createDetailView(store) {
  let root = null;
  let rampId = null;
  let intervalsData = null;
  const unsubs = [];

  const $ = (sel) => root.querySelector(sel);

  function currentRamp() {
    return (store.state.ramps || []).find((r) => r.id === rampId) || intervalsData?.ramp || null;
  }

  function mount(container, params) {
    root = container;
    rampId = params.id;
    intervalsData = null;

    root.innerHTML = `
      <header class="topbar">
        <a class="back-link" href="/" id="back-link"><span class="arrow">←</span> All ramps</a>
        <div class="topbar-right">
          <button class="fav-toggle" id="detail-fav" aria-pressed="false"><span class="star">☆</span> Favorite</button>
          <span class="clock tabular" id="detail-clock"></span>
        </div>
      </header>

      <section class="detail-hero">
        <div class="hero-kicker" id="hero-kicker"></div>
        <h1 id="hero-name">&nbsp;</h1>
        <div class="status-band" id="status-band">
          <div class="band-mark"></div>
          <div>
            <div class="band-status" id="band-status">—</div>
            <div class="band-since" id="band-since"></div>
          </div>
          <div class="band-outlook" id="band-outlook"></div>
        </div>
      </section>

      <section class="day-band">
        <div class="section-head">
          <span class="kicker">Today, midnight to midnight</span>
          <span class="section-note tabular" id="day-band-now-label"></span>
        </div>
        <div class="day-band-track" id="day-band-track"></div>
        <div class="day-band-labels" id="day-band-labels"></div>
      </section>

      <div class="detail-two">
        <section>
          <div class="section-head">
            <span class="kicker">Tide against this ramp</span>
            <span class="section-note" id="detail-tide-note"></span>
          </div>
          <div class="tide-chart-wrap" id="detail-tide-chart"></div>
          <div class="tide-extremes" id="detail-tide-extremes"></div>
        </section>
        <section>
          <div class="section-head">
            <span class="kicker">This ramp · last 48 hours</span>
          </div>
          <table class="changes-table"><tbody id="ramp-feed"></tbody></table>
        </section>
      </div>

      <section class="cam" id="detail-cam" hidden>
        <div class="section-head">
          <span class="kicker" id="detail-cam-kicker">Live cam</span>
        </div>
        <div class="cam-tabs" id="detail-cam-tabs" hidden></div>
        <div class="cam-frame">
          <video id="detail-cam-video" muted playsinline autoplay></video>
          <div class="cam-offline" id="detail-cam-offline" hidden>
            <h3 id="detail-cam-offline-title">Cam offline</h3>
            <p id="detail-cam-offline-note">Reconnecting.</p>
          </div>
        </div>
      </section>

      <section>
        <div class="section-head">
          <span class="kicker">Other ramps</span>
        </div>
        <nav class="other-ramps" id="other-ramps"></nav>
      </section>
    `;

    $('#detail-fav').addEventListener('click', () => {
      const ramp = currentRamp();
      if (ramp) store.toggleFavorite(ramp.access_id);
    });

    $('#detail-cam-tabs').addEventListener('click', (e) => {
      const tab = e.target.closest('.cam-tab');
      if (tab && !tab.disabled) store.set({ selectedCameraId: tab.dataset.cam });
    });

    const sub = (keys, fn) => unsubs.push(store.subscribe(keys, fn));
    sub(['now'], updateClock);
    sub(['ramps', 'tide', 'favorites', 'now', 'stale'], updateAll);
    sub(['config', 'cameras', 'selectedCameraId'], updateCam);

    updateClock(store.state);
    updateAll(store.state);
    updateCam(store.state);
    fetchIntervals();
  }

  function unmount() {
    while (unsubs.length) unsubs.pop()();
    unmountCam();
    root = null;
    intervalsData = null;
  }

  async function fetchIntervals() {
    try {
      const data = await loadIntervals(rampId, 48);
      intervalsData = data;
      if (root) {
        updateAll(store.state);
      }
    } catch {
      /* the band and feed just stay empty; the rest of the page works */
    }
  }

  function updateClock(s) {
    $('#detail-clock').textContent = clock(s.now);
  }

  function updateAll(s) {
    const ramp = currentRamp();
    if (!ramp) {
      $('#hero-name').textContent = 'Ramp not found';
      return;
    }

    const name = prettyRampName(ramp.ramp_name);
    const cat = ramp.status_category || categoryFromStatus(ramp.access_status);
    const city = titleCase(ramp.city || '');
    const cityRamps = sortRampsForCity(
      (s.ramps || []).filter((r) => (r.city || '') === (ramp.city || '')),
      ramp.city,
    );
    const index = cityRamps.findIndex((r) => r.id === ramp.id);

    document.title = `${name} — Beach Ramp Status`;
    $('#back-link').innerHTML = `<span class="arrow">←</span> All ${escapeHTML(city)} ramps`;
    $('#hero-kicker').textContent = `Ramp ${String(index + 1).padStart(2, '0')} · ${city}`;
    $('#hero-name').textContent = name;

    const fav = $('#detail-fav');
    const isFav = s.favorites.has(ramp.access_id);
    fav.setAttribute('aria-pressed', String(isFav));
    fav.querySelector('.star').textContent = isFav ? '★' : '☆';

    // Status field band.
    const band = $('#status-band');
    band.className = `status-band is-${cat}`;
    $('#band-status').textContent = capFirst(statusPhrase(ramp.access_status));
    $('#band-since').textContent = ramp.status_since
      ? `${s.stale ? 'as of' : 'since'} ${sinceString(new Date(ramp.status_since), s.now)}`
      : '';
    $('#band-outlook').textContent = serverOutlookLine(ramp, s) || outlookLine(ramp, s);

    updateDayBand(s);
    updateTide(s);
    updateFeed(s);
    updateOtherRamps(cityRamps, ramp);
  }

  /**
   * The server's learned outlook for this ramp, when available. Timing
   * headlines for upcoming risk, detail copy otherwise (which carries the
   * reopen story for closed ramps). Empty string falls back to the legacy
   * client-side heuristic.
   */
  function serverOutlookLine(ramp, s) {
    const ro = (s.outlook?.ramps || []).find((r) => r.access_id === ramp.access_id);
    if (!ro) return '';
    if (ro.risk === 'likely' || ro.risk === 'possible' || ro.risk === 'scheduled') {
      return ro.headline || '';
    }
    return ro.detail || ro.headline || '';
  }

  function outlookLine(ramp, s) {
    if (!s.tide) return '';
    const reopen = reopenEstimate(ramp, s.tide, s.now);
    if (reopen) return `Reopens near ${clock(reopen)} as the tide drops`;

    const status = (ramp.access_status || '').trim().toUpperCase();
    const next = nextExtreme(s.tide, s.now);
    const nextHigh = (s.tide.predictions || [])
      .map((p) => ({ ...p, time: new Date(p.time) }))
      .filter((p) => p.type === 'H' && p.time > s.now)
      .sort((a, b) => a.time - b.time)[0];

    if ((status === 'OPEN - ENTRANCE ONLY' || status === 'CLOSING IN PROGRESS') && tideIsRising(s.tide) && nextHigh) {
      return `Expect full closure near high tide ${clock(nextHigh.time)}`;
    }
    if (nextHigh) return `Next high tide ${clock(nextHigh.time)}`;
    if (next) return `Next ${next.label.toLowerCase()} tide ${clock(next.time)}`;
    return '';
  }

  // Today's midnight-to-midnight status band.
  function updateDayBand(s) {
    const track = $('#day-band-track');
    const labels = $('#day-band-labels');
    $('#day-band-now-label').textContent = `Now ${clock(s.now)}`;

    if (!intervalsData?.intervals?.length) {
      track.innerHTML = '<div class="day-band-seg is-gap" style="flex: 1"></div>';
      labels.innerHTML = '';
      return;
    }

    const dayStart = easternMidnight(s.now).getTime();
    const dayEnd = dayStart + 86_400_000;
    const span = dayEnd - dayStart;

    // Clip intervals to today; open a leading gap if history starts late.
    const clipped = [];
    for (const iv of intervalsData.intervals) {
      const start = Math.max(new Date(iv.start).getTime(), dayStart);
      const end = Math.min(new Date(iv.end).getTime(), dayEnd);
      if (end > start) clipped.push({ ...iv, startMs: start, endMs: end });
    }
    if (!clipped.length) {
      track.innerHTML = '<div class="day-band-seg is-gap" style="flex: 1"></div>';
      labels.innerHTML = '';
      return;
    }
    if (clipped[0].startMs > dayStart) {
      clipped.unshift({ category: 'gap', startMs: dayStart, endMs: clipped[0].startMs, status: '' });
    }
    // The band covers the whole day; the future is a gap after "now".
    const last = clipped[clipped.length - 1];
    if (last.endMs < dayEnd) {
      clipped.push({ category: 'gap', startMs: last.endMs, endMs: dayEnd, status: '' });
    }

    track.innerHTML = clipped.map((iv) => `
      <div class="day-band-seg is-${iv.category}" style="flex: ${(iv.endMs - iv.startMs) / span}"></div>
    `).join('') + `<div class="day-band-now" style="left: ${(((s.now.getTime() - dayStart) / span) * 100).toFixed(2)}%"></div>`;

    // Skip labels that would collide with the previous one — short segments
    // (a turtle sweep before the morning opening) otherwise overprint.
    const MIN_LABEL_GAP_PCT = 10;
    let lastLabelPct = -Infinity;
    labels.innerHTML = clipped
      .filter((iv) => iv.category !== 'gap')
      .map((iv) => {
        const pct = ((iv.startMs - dayStart) / span) * 100;
        if (pct - lastLabelPct < MIN_LABEL_GAP_PCT) return '';
        lastLabelPct = pct;
        return `
        <div class="day-band-label" style="left: ${pct.toFixed(2)}%">
          <div class="seg-time">${escapeHTML(iv.startMs === dayStart ? '12:00 AM' : clock(new Date(iv.startMs)))}</div>
          <div class="seg-name">${escapeHTML(capFirst(statusPhrase(iv.status)))}</div>
        </div>
      `;
      }).join('');
  }

  function updateTide(s) {
    if (!s.tide?.predictions?.length) return;
    const dayStart = easternMidnight(s.now).getTime();
    const dayEnd = dayStart + 86_400_000;
    const points = curvePoints(s.tide.predictions, dayStart, dayEnd, 10);
    $('#detail-tide-chart').innerHTML = renderTideChartSVG({
      points,
      nowMs: s.now.getTime(),
      nowStroke: 'ink',
      closureFt: null, // per-ramp closure heights land later
    });
    const dir = tideIsRising(s.tide) ? 'Rising' : 'Dropping';
    $('#detail-tide-note').textContent = dir;
    $('#detail-tide-extremes').innerHTML = s.tide.predictions.slice(0, 4).map((p) => `
      <div class="tide-extreme">
        <div class="ex-label">${p.type === 'H' ? 'High' : 'Low'}</div>
        <div class="ex-time">${clock(new Date(p.time))}</div>
        <div class="ex-height">${p.height != null ? `${p.height < 0 ? '−' : ''}${Math.abs(p.height).toFixed(1)} ft` : ''}</div>
      </div>
    `).join('');
  }

  function updateFeed(s) {
    const feed = $('#ramp-feed');
    if (!intervalsData?.intervals?.length) {
      feed.innerHTML = '<tr><td class="col-time">—</td><td>No changes in the last 48 hours.</td></tr>';
      return;
    }
    const rows = [...intervalsData.intervals].reverse().slice(0, 10);
    feed.innerHTML = rows.map((iv) => `
      <tr>
        <td class="col-time">${escapeHTML(sinceString(new Date(iv.start), s.now))}</td>
        <td class="col-name">${escapeHTML(capFirst(statusPhrase(iv.status)))}</td>
      </tr>
    `).join('');
  }

  function updateOtherRamps(cityRamps, ramp) {
    $('#other-ramps').innerHTML = cityRamps.map((r) => `
      <a class="other-ramp hover-accent" href="/ramp/${r.id}" aria-current="${r.id === ramp.id}">
        ${escapeHTML(prettyRampName(r.ramp_name))}
      </a>
    `).join('');
  }

  function updateCam(s) {
    const camera = pickCamera(s.cameras, s.selectedCameraId);
    const url = camera?.stream_url || s.config?.video_stream_url;
    const section = $('#detail-cam');
    if (!url) {
      section.setAttribute('hidden', '');
      return;
    }
    section.removeAttribute('hidden');
    const camName = camera?.name || titleCase(currentRamp()?.city || store.state.selectedCity);
    $('#detail-cam-kicker').textContent = `Live cam · ${camName}`;
    $('#detail-cam-offline-title').textContent = `${camName} cam offline`;

    updateCamTabs(s, camera);

    const video = $('#detail-cam-video');
    if (!video.dataset.bound) {
      video.dataset.bound = '1';
      mountCam({
        frame: root.querySelector('#detail-cam .cam-frame'),
        video,
        offline: $('#detail-cam-offline'),
        offlineNote: $('#detail-cam-offline-note'),
      }, url, { resolveUrl: camResolveUrl });
    } else {
      updateCamUrl(url);
    }
  }

  /** Same switcher chips as the board; hidden until a second camera exists. */
  function updateCamTabs(s, activeCamera) {
    const tabs = $('#detail-cam-tabs');
    const cams = s.cameras?.cameras || [];
    if (cams.length < 2) {
      tabs.setAttribute('hidden', '');
      return;
    }
    tabs.removeAttribute('hidden');
    tabs.innerHTML = cams.map((c) => `
      <button class="cam-tab" data-cam="${escapeHTML(c.id)}"
        aria-pressed="${c.id === activeCamera?.id}" ${c.stream_url ? '' : 'disabled'}>
        ${escapeHTML(c.name)}
      </button>
    `).join('');
  }

  /** Playback-failure recovery: re-fetch the roster, replay the selected cam. */
  async function camResolveUrl() {
    const roster = await loadCameras();
    store.set({ cameras: roster });
    return pickCamera(roster, store.state.selectedCameraId)?.stream_url || null;
  }

  return { mount, unmount };
}
