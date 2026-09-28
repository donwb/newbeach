/**
 * Ask: a question box over the prediction engine (POST /api/v2/chat).
 *
 * The server does the thinking — a model picks from deterministic engine
 * tools and relays the engine's own copy — and hands back `reply` plus the
 * `sources` it rested on. This module renders the transcript, a fact card
 * from those sources, three suggested questions for the board's city, and
 * the key gate: the route is locked behind a chat key, kept in localStorage
 * after a first-run prompt. 404 means the feature is off (the section
 * hides); 401/503 means the key is wrong or missing (the key form shows).
 */

import { escapeHTML, titleCase, easternParts } from './format.js';

const KEY_STORAGE = 'beach.chatKey';
const MAX_TURNS = 20;

function readKey() {
  try { return localStorage.getItem(KEY_STORAGE) || ''; } catch { return ''; }
}
function writeKey(key) {
  try { localStorage.setItem(KEY_STORAGE, key); } catch { /* private mode: session only */ }
}
function clearKey() {
  try { localStorage.removeItem(KEY_STORAGE); } catch { /* ignore */ }
}

/** Three questions for the board's city and the hour, sent verbatim. */
export function suggestions(city, now = new Date()) {
  const name = titleCase(city || 'New Smyrna Beach');
  const { hour } = easternParts(now);
  const later = hour < 12 ? 'this afternoon' : hour < 17 ? 'later today' : 'tomorrow morning';
  return [
    `Can I get on the beach in ${name} right now?`,
    `Will the ${name} ramps be open ${later}?`,
    'Which day this weekend is best?',
  ];
}

export function createAsk(store) {
  let root = null;
  let key = readKey();
  let turns = [];
  let sources = [];
  let pending = false;
  let featureOff = false;
  let error = '';
  let unsub = null;
  let memoryKey = ''; // fallback when localStorage is unavailable

  const $ = (sel) => root.querySelector(sel);
  const currentKey = () => key || memoryKey;

  function mount(section) {
    root = section;
    root.innerHTML = `
      <div class="section-head">
        <span class="kicker">Ask</span>
        <span class="section-note" id="ask-note">Answers are the outlook's own words</span>
      </div>
      <div class="ask-body">
        <div class="ask-transcript" id="ask-transcript" aria-live="polite"></div>
        <form class="ask-key" id="ask-key" hidden>
          <p class="ask-key-text" id="ask-key-text">Ask is locked. Enter the chat key once; it stays in this browser.</p>
          <div class="ask-row">
            <input class="ask-input" id="ask-key-input" type="password" autocomplete="off" placeholder="Chat key" aria-label="Chat key">
            <button class="ask-send" type="submit">Save</button>
          </div>
        </form>
        <div class="ask-controls" id="ask-controls">
          <div class="ask-sugg" id="ask-sugg"></div>
          <form class="ask-row" id="ask-form">
            <input class="ask-input" id="ask-input" type="text" autocomplete="off" enterkeyhint="send"
                   placeholder="Ask about a ramp, a city, or a time this week…" aria-label="Your question" maxlength="1000">
            <button class="ask-send" id="ask-send" type="submit" aria-label="Send">Ask</button>
          </form>
        </div>
      </div>
    `;
    bind();
    unsub = store.subscribe(['selectedCity'], renderSuggestions);
    render();
  }

  function unmount() {
    if (unsub) unsub();
    unsub = null;
    root = null;
  }

  function bind() {
    $('#ask-form').addEventListener('submit', (e) => {
      e.preventDefault();
      const input = $('#ask-input');
      send(input.value);
    });
    $('#ask-sugg').addEventListener('click', (e) => {
      const btn = e.target.closest('button[data-q]');
      if (btn) send(btn.dataset.q);
    });
    $('#ask-key').addEventListener('submit', (e) => {
      e.preventDefault();
      const value = $('#ask-key-input').value.trim();
      if (!value) return;
      key = value;
      writeKey(value);
      memoryKey = value;
      $('#ask-key-input').value = '';
      error = '';
      render();
      // A question that was waiting on the key goes straight out.
      const draft = $('#ask-input').value.trim();
      if (draft) send(draft);
      else $('#ask-input').focus();
    });
    $('#ask-transcript').addEventListener('click', (e) => {
      if (e.target.closest('#ask-clear')) {
        turns = [];
        sources = [];
        error = '';
        render();
      }
      if (e.target.closest('#ask-forget')) {
        key = '';
        memoryKey = '';
        clearKey();
        render();
      }
    });
  }

  async function send(text) {
    const q = (text || '').trim();
    if (!q || pending) return;
    error = '';
    if (!currentKey()) {
      $('#ask-input').value = q;
      render();
      $('#ask-key-input').focus();
      return;
    }
    turns.push({ role: 'user', text: q });
    while (turns.length > MAX_TURNS || (turns.length && turns[0].role === 'assistant')) turns.shift();
    pending = true;
    $('#ask-input').value = '';
    render();

    const city = store.state.selectedCity;
    try {
      const res = await fetch('/api/v2/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Chat-Key': currentKey() },
        body: JSON.stringify({ messages: turns, context: city ? { city } : undefined }),
      });
      if (res.status === 401 || res.status === 503) {
        turns.pop();
        $('#ask-input').value = q;
        key = '';
        memoryKey = '';
        clearKey();
        error = res.status === 401 ? "That chat key wasn't accepted." : "Chat isn't set up on the server yet.";
        return;
      }
      if (res.status === 404) {
        turns.pop();
        featureOff = true;
        return;
      }
      if (!res.ok) {
        turns.pop();
        $('#ask-input').value = q;
        error = res.status === 504
          ? 'The outlook took too long to answer. Try again.'
          : "Couldn't reach the outlook. Try again in a moment.";
        return;
      }
      const data = await res.json();
      turns.push({ role: 'assistant', text: data.reply || '' });
      sources = Array.isArray(data.sources) ? data.sources : [];
    } catch {
      turns.pop();
      $('#ask-input').value = q;
      error = "Couldn't reach the outlook. Try again in a moment.";
    } finally {
      pending = false;
      render();
    }
  }

  // ---- rendering ----

  function render() {
    if (!root) return;
    root.hidden = featureOff;
    if (featureOff) return;
    const needsKey = !currentKey();
    $('#ask-key').hidden = !needsKey;
    $('#ask-controls').hidden = needsKey;
    if (needsKey) {
      $('#ask-key-text').textContent = error || 'Ask is locked. Enter the chat key once; it stays in this browser.';
    }
    $('#ask-send').disabled = pending;
    $('#ask-input').disabled = pending;
    renderTranscript();
    renderSuggestions(store.state);
  }

  function renderSuggestions(s) {
    if (!root) return;
    $('#ask-sugg').innerHTML = suggestions(s.selectedCity, s.now || new Date())
      .map((q) => `<button type="button" class="ask-chip" data-q="${escapeHTML(q)}" ${pending ? 'disabled' : ''}>${escapeHTML(q)}</button>`)
      .join('');
  }

  function renderTranscript() {
    const el = $('#ask-transcript');
    const parts = [];
    if (!turns.length && !error) {
      parts.push(`<p class="ask-empty">Ask whether you can get on the beach in a city, whether the ramps will be open at a time this week, or which day looks best. Answers are the board's own outlook, in its own words.</p>`);
    }
    for (const t of turns) {
      parts.push(`<div class="ask-turn ask-turn--${t.role}"><p>${escapeHTML(t.text)}</p></div>`);
    }
    const last = turns[turns.length - 1];
    if (last?.role === 'assistant' && sources.length) parts.push(renderCard(sources));
    if (pending) parts.push(`<p class="ask-pending">Checking the outlook…</p>`);
    if (error && currentKey()) parts.push(`<p class="ask-error">${escapeHTML(error)}</p>`);
    if (turns.length || currentKey()) {
      const links = [];
      if (turns.length) links.push(`<button type="button" id="ask-clear">Clear</button>`);
      if (currentKey()) links.push(`<button type="button" id="ask-forget">Forget key</button>`);
      parts.push(`<div class="ask-links">${links.join(' · ')}</div>`);
    }
    el.innerHTML = parts.join('');
    el.scrollTop = el.scrollHeight;
  }

  /** The engine facts behind the last reply — the board's own card. */
  function renderCard(list) {
    const blocks = [];
    for (const s of list) {
      if (s.kind === 'ramp_outlook') {
        blocks.push(`
          <div class="ask-fact${s.risk === 'closed_now' ? ' ask-fact--closed' : ''}">
            <div class="ask-fact-k">${escapeHTML([s.name, s.at_label].filter(Boolean).join(' · '))}</div>
            ${s.headline ? `<p class="ask-fact-h">${escapeHTML(s.headline)}</p>` : ''}
            ${s.detail ? `<p class="ask-fact-d">${escapeHTML(s.detail)}</p>` : ''}
          </div>`);
      } else if (s.kind === 'city_now' || s.kind === 'city_outlook') {
        const count = s.kind === 'city_now' && s.open_count != null && s.ramp_count != null
          ? ` · ${s.open_count} of ${s.ramp_count} open` : '';
        const rows = (s.ramps || []).map((r) => {
          const state = s.kind === 'city_now'
            ? (r.status || '').toLowerCase().replace(/^closed - /, '').replace(/^closed for /, 'closed · ')
            : (r.risk || '').replace('_', ' ');
          const closed = r.risk === 'closed_now' || /^closed/i.test(r.status || '');
          return `<div class="ask-ramp${closed ? ' ask-ramp--closed' : ''}"><span class="ask-ramp-n">${escapeHTML(r.name)}</span><span class="ask-ramp-s">${escapeHTML(state)}</span><span class="ask-ramp-h">${escapeHTML(r.headline || '')}</span></div>`;
        }).join('');
        blocks.push(`
          <div class="ask-fact">
            <div class="ask-fact-k">${escapeHTML([s.city, s.at_label || (s.kind === 'city_now' ? 'right now' : '')].filter(Boolean).join(' · '))}${escapeHTML(count)}</div>
            ${s.headline ? `<p class="ask-fact-h">${escapeHTML(s.headline)}</p>` : ''}
            ${s.detail ? `<p class="ask-fact-d">${escapeHTML(s.detail)}</p>` : ''}
            ${rows ? `<div class="ask-ramps">${rows}</div>` : ''}
          </div>`);
      }
    }
    const days = list.filter((s) => s.kind === 'weekend_day');
    if (days.length) {
      blocks.push(`
        <div class="ask-fact">
          <div class="ask-days">${days.map((d) => `
            <div class="ask-day" data-verdict="${escapeHTML(d.verdict || '')}">
              <span class="ask-day-n">${escapeHTML((d.weekday || d.date || '').slice(0, 3))}</span>
              <span class="ask-day-v">${escapeHTML((d.verdict || '').replace('_', ' '))}</span>
              <span class="ask-day-h">${escapeHTML(d.headline || '')}</span>
            </div>`).join('')}</div>
        </div>`);
    }
    return blocks.length ? `<div class="ask-card" id="ask-card">${blocks.join('')}</div>` : '';
  }

  return { mount, unmount };
}
