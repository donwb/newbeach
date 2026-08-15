/**
 * The board: verdict band, city tabs, filter counts, ramp grid, live cam,
 * tide + forecast, recent changes. Mounts once; granular updaters subscribe
 * to store keys, and the ramp grid reconciles keyed card elements so the
 * 60-second poll never replays animations or drops scroll position.
 */

import { escapeHTML, prettyRampName, titleCase, sinceString, clock, categoryFromStatus } from '../format.js';
import { buildVerdict, statusPhrase, nextExtreme, tideIsRising } from '../verdict.js';
import { sortRampsForCity } from '../order.js';
import { curvePoints, renderTideChartSVG } from '../tide.js';
import { easternMidnight } from '../format.js';
import { events as solarEvents } from '../solar.js';
import { mountCam, updateCamUrl, unmountCam } from '../cam.js';

const capFirst = (s) => s.charAt(0).toUpperCase() + s.slice(1);

function statusWord(accessStatus) {
  return capFirst(statusPhrase(accessStatus));
}

export function createBoardView(store) {
  let root = null;
  const unsubs = [];
  const cardEls = new Map(); // access_id -> element
  const prints = {};         // section fingerprints, so idle polls touch nothing

  // ----- derived data -----

  const cityRamps = (s) => (s.ramps || []).filter(
    (r) => (r.city || '').toUpperCase() === s.selectedCity,
  );

  function visibleRamps(s) {
    let list = sortRampsForCity(cityRamps(s), s.selectedCity);
    if (s.selectedStatus !== 'all') {
      list = list.filter((r) => (r.status_category || categoryFromStatus(r.access_status)) === s.selectedStatus);
    }
    if (s.favoritesOnly) {
      list = list.filter((r) => s.favorites.has(r.access_id));
    }
    return list;
  }

  // ----- mount -----

  function mount(container) {
    root = container;
    root.innerHTML = `
      <header class="topbar">
        <div>
          <div class="brand">Beach Ramp Status</div>
        </div>
        <span class="brand-sub">Volusia County, FL</span>
        <div class="topbar-right">
          <span class="freshness" id="freshness"><span class="dot"></span><span id="freshness-text">Live</span></span>
          <span class="phase-name" id="phase-name"></span>
          <span class="clock tabular" id="board-clock"></span>
        </div>
      </header>

      <nav class="citytabs" id="citytabs" aria-label="City"></nav>
      <button class="city-select" id="city-select" aria-haspopup="listbox">
        <span id="city-select-label"></span>
        <span class="count-note"><span id="city-count"></span> cities <span class="caret">⌄</span></span>
      </button>

      <section class="verdict" id="verdict" data-category="open">
        <div class="verdict-main">
          <div class="verdict-bar"></div>
          <div class="verdict-text">
            <h1 id="verdict-headline">&nbsp;</h1>
            <p class="verdict-sub" id="verdict-subline"></p>
          </div>
        </div>
        <div class="verdict-stats">
          <a class="stat-cell hover-accent" href="/tide">
            <span class="stat-label">Tide <span class="chev">›</span></span>
            <div class="stat-value" id="stat-tide">—</div>
            <div class="stat-detail" id="stat-tide-detail"></div>
          </a>
          <a class="stat-cell hover-accent" href="/water">
            <span class="stat-label">Water · Air <span class="chev">›</span></span>
            <div class="stat-value" id="stat-water">—</div>
            <div class="stat-detail" id="stat-water-detail"></div>
          </a>
          <a class="stat-cell hover-accent" href="/wind">
            <span class="stat-label">Wind <span class="chev">›</span></span>
            <div class="stat-value" id="stat-wind">—</div>
            <div class="stat-detail" id="stat-wind-detail"></div>
          </a>
        </div>
      </section>

      <div class="filters" id="filters">
        <button class="filter-btn" data-status="all" aria-pressed="true">All <span class="count">0</span></button>
        <button class="filter-btn" data-status="open" aria-pressed="false">Open <span class="count">0</span></button>
        <button class="filter-btn" data-status="limited" aria-pressed="false">Limited <span class="count">0</span></button>
        <button class="filter-btn" data-status="closed" aria-pressed="false">Closed <span class="count">0</span></button>
        <button class="fav-toggle" id="fav-toggle" aria-pressed="false"><span class="star">☆</span> Favorites only</button>
      </div>

      <section class="ramp-grid" id="ramp-grid" aria-live="polite"></section>

      <section class="cam" id="cam-section" hidden>
        <div class="section-head">
          <span class="kicker" id="cam-kicker">Live cam</span>
          <span class="section-note">1280 × 270 · panoramic</span>
        </div>
        <div class="cam-frame">
          <video id="cam-video" muted playsinline autoplay></video>
          <div class="cam-offline" id="cam-offline" hidden>
            <h3 id="cam-offline-title">Cam offline</h3>
            <p id="cam-offline-note">Reconnecting.</p>
          </div>
        </div>
      </section>

      <div class="tide-weather">
        <section>
          <div class="section-head">
            <span class="kicker">Today's tide</span>
            <span class="section-note" id="tide-note"></span>
          </div>
          <div class="tide-chart-wrap" id="tide-chart"></div>
          <div class="tide-extremes" id="tide-extremes"></div>
        </section>
        <section>
          <div class="section-head">
            <span class="kicker">Forecast</span>
            <span class="section-note">NWS · six periods</span>
          </div>
          <div class="forecast-grid" id="forecast-grid"></div>
        </section>
      </div>

      <section class="changes">
        <div class="section-head">
          <span class="kicker">Recent changes</span>
          <span class="section-note">County feed</span>
        </div>
        <table class="changes-table"><tbody id="changes-body"></tbody></table>
      </section>

      <footer class="foot">
        <span id="foot-sources">NOAA · NWS · Volusia County feed</span>
        <span id="foot-updated" class="tabular"></span>
      </footer>
    `;

    bindEvents();

    const sub = (keys, fn) => unsubs.push(store.subscribe(keys, fn));
    sub(['now', 'phase'], updateClock);
    sub(['ramps', 'selectedCity'], updateCityControls);
    sub(['ramps', 'selectedCity', 'selectedStatus', 'favoritesOnly', 'favorites', 'stale'], updateFiltersAndGrid);
    sub(['ramps', 'tide', 'selectedCity', 'stale', 'dataAgeMs'], updateVerdict);
    sub(['tide', 'weather'], updateStats);
    sub(['tide', 'now'], updateTideSection);
    sub(['weather'], updateForecast);
    sub(['activity'], updateChanges);
    sub(['config'], updateCam);
    sub(['health', 'stale', 'dataAgeMs', 'config'], updateChrome);

    const s = store.state;
    updateClock(s); updateCityControls(s); updateFiltersAndGrid(s); updateVerdict(s);
    updateStats(s); updateTideSection(s); updateForecast(s); updateChanges(s);
    updateCam(s); updateChrome(s);
  }

  function unmount() {
    while (unsubs.length) unsubs.pop()();
    unmountCam();
    cardEls.clear();
    Object.keys(prints).forEach((k) => delete prints[k]);
    root = null;
  }

  const $ = (sel) => root.querySelector(sel);

  // ----- events -----

  function bindEvents() {
    $('#filters').addEventListener('click', (e) => {
      const btn = e.target.closest('.filter-btn');
      if (btn) store.set({ selectedStatus: btn.dataset.status });
      if (e.target.closest('#fav-toggle')) {
        store.set({ favoritesOnly: !store.state.favoritesOnly });
      }
    });

    $('#citytabs').addEventListener('click', (e) => {
      const tab = e.target.closest('.citytab');
      if (tab) store.set({ selectedCity: tab.dataset.city });
    });

    $('#city-select').addEventListener('click', () => {
      // Cycle through cities on the mobile control.
      const cities = cityList();
      if (cities.length < 2) return;
      const i = cities.indexOf(store.state.selectedCity);
      store.set({ selectedCity: cities[(i + 1) % cities.length] });
    });

    $('#ramp-grid').addEventListener('click', (e) => {
      const star = e.target.closest('.card-star');
      if (star) {
        e.preventDefault();
        e.stopPropagation();
        store.toggleFavorite(star.closest('.ramp-card').dataset.accessId);
      }
    });
  }

  function cityList() {
    const seen = new Set();
    for (const r of store.state.ramps || []) {
      if (r.city) seen.add(r.city.toUpperCase());
    }
    return [...seen].sort();
  }

  // ----- updaters -----

  function updateClock(s) {
    $('#board-clock').textContent = clock(s.now);
    $('#phase-name').textContent = s.phase || '';
  }

  function updateChrome(s) {
    if (s.stale) {
      const minutes = Math.max(1, Math.round((s.dataAgeMs || 0) / 60_000));
      $('#freshness-text').textContent = `Stale · ${minutes} min`;
    } else {
      $('#freshness-text').textContent = 'Live';
    }
    const station = s.config?.tide_station;
    $('#foot-sources').textContent = `NOAA ${station || ''} · NWS api.weather.gov · Volusia County feed`.replace('  ', ' ');
    const lastPoll = s.health?.ingester?.last_poll_at;
    $('#foot-updated').textContent = lastPoll ? `Updated ${clock(new Date(lastPoll))}` : '';
  }

  function updateCityControls(s) {
    const cities = cityList();
    const print = cities.join('|') + '::' + s.selectedCity;
    if (prints.cities !== print) {
      prints.cities = print;
      $('#citytabs').innerHTML = cities.map((c) => `
        <button class="citytab" data-city="${escapeHTML(c)}" aria-current="${c === s.selectedCity}">${escapeHTML(titleCase(c))}</button>
      `).join('');
      $('#city-select-label').textContent = titleCase(s.selectedCity);
      $('#city-count').textContent = cities.length;
    }
  }

  function updateFiltersAndGrid(s) {
    const inCity = cityRamps(s);
    const counts = {
      all: inCity.length,
      open: inCity.filter((r) => r.status_category === 'open').length,
      limited: inCity.filter((r) => r.status_category === 'limited').length,
      closed: inCity.filter((r) => r.status_category === 'closed').length,
    };
    for (const btn of root.querySelectorAll('.filter-btn')) {
      btn.querySelector('.count').textContent = counts[btn.dataset.status];
      btn.setAttribute('aria-pressed', String(btn.dataset.status === s.selectedStatus));
    }
    const fav = $('#fav-toggle');
    fav.setAttribute('aria-pressed', String(s.favoritesOnly));
    fav.querySelector('.star').textContent = s.favoritesOnly ? '★' : '☆';

    updateGrid(s);
  }

  function cardHTML(ramp, index, s) {
    const cat = ramp.status_category || categoryFromStatus(ramp.access_status);
    const name = prettyRampName(ramp.ramp_name);
    const since = sinceLine(ramp, s);
    return `
      <span class="card-index tabular">${String(index + 1).padStart(2, '0')}</span>
      <button class="card-star" aria-pressed="${s.favorites.has(ramp.access_id)}"
        aria-label="Favorite ${escapeHTML(name)}">${s.favorites.has(ramp.access_id) ? '★' : '☆'}</button>
      <div class="card-main">
        <div class="card-name">${escapeHTML(name)}</div>
        <div class="card-since-inline">${escapeHTML(since)}</div>
      </div>
      <div class="card-bottom">
        <div class="card-status"><span class="card-mark"></span><span class="card-word">${escapeHTML(statusWord(ramp.access_status))}</span></div>
        <div class="card-since">${escapeHTML(since)}</div>
      </div>
    `;
  }

  function sinceLine(ramp, s) {
    if (!ramp.status_since) return '';
    const when = sinceString(new Date(ramp.status_since), s.now);
    return s.stale ? `as of ${when}` : `since ${when}`;
  }

  function updateGrid(s) {
    const grid = $('#ramp-grid');
    const list = visibleRamps(s);

    if (!s.ramps) {
      grid.innerHTML = '<div class="grid-empty boot-loading">Loading ramps…</div>';
      cardEls.clear();
      return;
    }
    if (!list.length) {
      grid.innerHTML = '<div class="grid-empty">No ramps match this filter.</div>';
      cardEls.clear();
      return;
    }
    // Clear any empty-state markup left behind.
    if (grid.querySelector('.grid-empty')) {
      grid.innerHTML = '';
      cardEls.clear();
    }

    const seen = new Set();
    list.forEach((ramp, index) => {
      seen.add(ramp.access_id);
      let el = cardEls.get(ramp.access_id);
      const cat = ramp.status_category || categoryFromStatus(ramp.access_status);
      const print = [cat, ramp.access_status, ramp.status_since, index,
        s.favorites.has(ramp.access_id), s.stale].join('|');

      if (!el) {
        el = document.createElement('a');
        el.href = `/ramp/${ramp.id}`;
        el.dataset.accessId = ramp.access_id;
        el.className = `ramp-card is-${cat} is-new`;
        el.innerHTML = cardHTML(ramp, index, s);
        el.dataset.print = print;
        el.addEventListener('animationend', () => el.classList.remove('is-new'), { once: true });
        cardEls.set(ramp.access_id, el);
      } else if (el.dataset.print !== print) {
        el.className = `ramp-card is-${cat}`;
        el.innerHTML = cardHTML(ramp, index, s);
        el.dataset.print = print;
      }
    });

    // Drop cards that fell out of the filter.
    for (const [id, el] of cardEls) {
      if (!seen.has(id)) {
        el.remove();
        cardEls.delete(id);
      }
    }

    // Reorder only when the DOM order differs — appending an existing node
    // moves it without recreating, preserving focus and scroll.
    const desired = list.map((r) => cardEls.get(r.access_id));
    const currentOrder = [...grid.children];
    if (desired.some((el, i) => currentOrder[i] !== el)) {
      desired.forEach((el) => grid.appendChild(el));
    } else {
      // First render appends everything.
      desired.forEach((el) => {
        if (!el.isConnected) grid.appendChild(el);
      });
    }
  }

  function updateVerdict(s) {
    const verdict = buildVerdict({
      ramps: cityRamps(s),
      tide: s.tide,
      sunset: solarEvents(s.now).sunset,
      now: s.now,
      dataAgeMs: s.stale ? s.dataAgeMs : null,
    });
    const section = $('#verdict');
    section.dataset.category = verdict.category;
    $('#verdict-headline').textContent = verdict.headline;
    $('#verdict-subline').textContent = verdict.subline;
  }

  function updateStats(s) {
    if (s.tide) {
      $('#stat-tide').textContent = tideIsRising(s.tide) ? 'Rising' : 'Dropping';
      const next = nextExtreme(s.tide, s.now);
      $('#stat-tide-detail').textContent = next ? `${next.label} ${clock(next.time)}` : '';
    }
    const c = s.weather?.current;
    if (c || s.tide) {
      const water = s.tide?.water_temp_avg != null ? `${Math.round(s.tide.water_temp_avg)}°` : '—';
      const air = c?.temperature_f != null ? `${Math.round(c.temperature_f)}°` : '—';
      $('#stat-water').textContent = `${water} · ${air}`;
      $('#stat-water-detail').textContent = c?.description || '';
    }
    if (c?.wind_speed) {
      const speed = parseInt(c.wind_speed, 10);
      $('#stat-wind').textContent = Number.isNaN(speed) || speed === 0
        ? 'Calm'
        : `${c.wind_direction || ''} ${speed}`.trim();
      $('#stat-wind-detail').textContent = c.wind_gust
        ? `Gusts ${c.wind_gust}`
        : (c.humidity != null ? `${c.humidity}% humidity` : '');
    }
  }

  function updateTideSection(s) {
    if (!s.tide?.predictions?.length) return;
    const print = JSON.stringify(s.tide.predictions) + Math.floor(s.now.getTime() / 60_000);
    if (prints.tide === print) return;
    prints.tide = print;

    const dayStart = easternMidnight(s.now).getTime();
    const dayEnd = dayStart + 86_400_000;
    const points = curvePoints(s.tide.predictions, dayStart, dayEnd, 10);
    $('#tide-chart').innerHTML = renderTideChartSVG({
      points,
      nowMs: s.now.getTime(),
      nowStroke: 'limited',
    });

    const dir = tideIsRising(s.tide) ? 'Rising' : 'Dropping';
    const next = nextExtreme(s.tide, s.now);
    $('#tide-note').textContent = next ? `${dir} · next ${next.label.toLowerCase()} ${clock(next.time)}` : dir;

    $('#tide-extremes').innerHTML = s.tide.predictions.slice(0, 4).map((p) => {
      const height = p.height != null
        ? `${p.height < 0 ? '−' : ''}${Math.abs(p.height).toFixed(1)} ft` : '';
      return `
        <div class="tide-extreme">
          <div class="ex-label">${p.type === 'H' ? 'High' : 'Low'}</div>
          <div class="ex-time">${clock(new Date(p.time))}</div>
          <div class="ex-height">${height}</div>
        </div>
      `;
    }).join('');
  }

  function updateForecast(s) {
    const forecast = s.weather?.forecast;
    if (!forecast?.length) return;
    const print = forecast.slice(0, 6).map((p) => p.name + p.temperature).join('|');
    if (prints.forecast === print) return;
    prints.forecast = print;

    $('#forecast-grid').innerHTML = forecast.slice(0, 6).map((p) => `
      <div class="forecast-cell">
        <div class="fc-name">${escapeHTML(p.name)}</div>
        <div class="fc-temp">${p.temperature}°</div>
        <div class="fc-desc">${escapeHTML(p.short_description || '')}</div>
      </div>
    `).join('');
  }

  function updateChanges(s) {
    const entries = s.activity;
    if (!entries?.length) return;
    const print = entries[0]?.recorded_at + ':' + entries.length;
    if (prints.changes === print) return;
    prints.changes = print;

    $('#changes-body').innerHTML = entries.slice(0, 8).map((e) => `
      <tr>
        <td class="col-time">${escapeHTML(sinceString(new Date(e.recorded_at), store.state.now))}</td>
        <td class="col-name">${escapeHTML(prettyRampName(e.ramp_name || e.access_id))}</td>
        <td>${escapeHTML(statusWord(e.access_status))}</td>
      </tr>
    `).join('');
  }

  function updateCam(s) {
    const url = s.config?.video_stream_url;
    const section = $('#cam-section');
    const scenario = new URLSearchParams(location.search).get('scenario');
    if (!url && scenario !== 'camoff') {
      section.setAttribute('hidden', '');
      return;
    }
    section.removeAttribute('hidden');
    $('#cam-kicker').textContent = `Live cam · ${titleCase(s.selectedCity)}`;
    $('#cam-offline-title').textContent = `${titleCase(s.selectedCity)} cam offline`;

    const elements = {
      frame: $('.cam-frame'),
      video: $('#cam-video'),
      offline: $('#cam-offline'),
      offlineNote: $('#cam-offline-note'),
    };
    if (!elements.video.dataset.bound) {
      elements.video.dataset.bound = '1';
      mountCam(elements, url, { forceOffline: scenario === 'camoff' });
    } else {
      updateCamUrl(url);
    }
  }

  return { mount, unmount };
}
