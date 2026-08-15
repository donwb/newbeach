/**
 * Stat screens — /tide, /water, /wind. One shared view: kicker, big title,
 * 2px rule, then rows of facts. Same content as the board's stat cells,
 * expanded, at real URLs.
 */

import { escapeHTML, titleCase, clock, easternMidnight } from '../format.js';
import { nextExtreme, tideIsRising } from '../verdict.js';
import { curvePoints, renderTideChartSVG } from '../tide.js';

const TITLES = { tide: 'Tide', water: 'Water · Air', wind: 'Wind' };

export function createStatView(store) {
  let root = null;
  let kind = 'tide';
  const unsubs = [];

  const $ = (sel) => root.querySelector(sel);

  function mount(container, params) {
    root = container;
    kind = params.kind || 'tide';
    document.title = `${TITLES[kind]} — Beach Ramp Status`;

    root.innerHTML = `
      <header class="topbar">
        <a class="back-link" href="/"><span class="arrow">←</span> Board</a>
        <div class="topbar-right">
          <span class="clock tabular" id="stat-clock"></span>
        </div>
      </header>
      <section class="stat-screen">
        <div class="hero-kicker kicker">${escapeHTML(titleCase(store.state.selectedCity))}</div>
        <h1>${TITLES[kind]}</h1>
        <div class="stat-body" id="stat-body"></div>
      </section>
    `;

    const sub = (keys, fn) => unsubs.push(store.subscribe(keys, fn));
    sub(['now'], (s) => { $('#stat-clock').textContent = clock(s.now); });
    sub(['tide', 'weather', 'now'], update);
    $('#stat-clock').textContent = clock(store.state.now);
    update(store.state);
  }

  function unmount() {
    while (unsubs.length) unsubs.pop()();
    root = null;
  }

  const row = (label, value, note = '') => `
    <div class="stat-row">
      <span>${escapeHTML(label)}${note ? ` <span class="section-note">${escapeHTML(note)}</span>` : ''}</span>
      <span class="row-value">${escapeHTML(value)}</span>
    </div>
  `;

  function update(s) {
    const body = $('#stat-body');
    if (kind === 'tide') {
      body.innerHTML = renderTide(s);
    } else if (kind === 'water') {
      body.innerHTML = renderWater(s);
    } else {
      body.innerHTML = renderWind(s);
    }
  }

  function renderTide(s) {
    if (!s.tide) return '<p class="boot-loading">Loading tide data…</p>';
    const dayStart = easternMidnight(s.now).getTime();
    const points = curvePoints(s.tide.predictions, dayStart, dayStart + 86_400_000, 10);
    const chart = renderTideChartSVG({ points, nowMs: s.now.getTime(), nowStroke: 'limited' });
    const next = nextExtreme(s.tide, s.now);
    return `
      <div class="tide-chart-wrap">${chart}</div>
      <div class="stat-rows" style="margin-top: 24px">
        ${row('Direction', tideIsRising(s.tide) ? 'Rising' : 'Dropping')}
        ${next ? row(`Next ${next.label.toLowerCase()}`, clock(next.time)) : ''}
        ${(s.tide.predictions || []).map((p) => row(
          p.type === 'H' ? 'High' : 'Low',
          `${clock(new Date(p.time))}`,
          p.height != null ? `${p.height < 0 ? '−' : ''}${Math.abs(p.height).toFixed(1)} ft` : '',
        )).join('')}
        ${s.tide.tide_percentage != null ? row('Tide level', `${s.tide.tide_percentage}%`) : ''}
      </div>
    `;
  }

  function renderWater(s) {
    const c = s.weather?.current;
    const temps = s.tide?.water_temps || [];
    if (!c && !temps.length) return '<p class="boot-loading">Loading conditions…</p>';
    return `
      <div class="stat-rows">
        ${s.tide?.water_temp_avg != null ? row('Water (avg)', `${Math.round(s.tide.water_temp_avg)}°F`) : ''}
        ${temps.map((t) => row(t.station_name, `${Math.round(t.temp_f)}°F`, 'water')).join('')}
        ${c?.temperature_f != null ? row('Air', `${Math.round(c.temperature_f)}°F`, c.description || '') : ''}
        ${c?.humidity != null ? row('Humidity', `${c.humidity}%`) : ''}
        ${c?.uv_index != null ? row('UV index', String(c.uv_index)) : ''}
      </div>
    `;
  }

  function renderWind(s) {
    const c = s.weather?.current;
    const forecast = s.weather?.forecast || [];
    if (!c) return '<p class="boot-loading">Loading wind data…</p>';
    return `
      <div class="stat-rows">
        ${row('Now', `${c.wind_direction || ''} ${c.wind_speed || ''}`.trim())}
        ${c.wind_gust ? row('Gusts', c.wind_gust) : ''}
        ${forecast.slice(0, 6).map((p) => row(p.name, `${p.wind_direction || ''} ${p.wind_speed || ''}`.trim())).join('')}
      </div>
    `;
  }

  return { mount, unmount };
}
