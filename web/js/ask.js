/**
 * Ask: a question box over the prediction engine (POST /api/v2/chat).
 *
 * The server does the thinking — a model picks from deterministic engine
 * tools and relays the engine's own copy — and hands back `reply` plus the
 * `sources` it rested on. This module is deliberately not a chat: one
 * input line, three suggested questions as text links, and the answer
 * rendered in the board's own voice (kicker · headline · detail) with a
 * short list of only the rows that carry news (a closure, a tide risk).
 * The conversation still carries context server-side for follow-ups, but
 * only the latest answer is shown.
 *
 * The route is locked behind a chat key, kept in localStorage after a
 * first-run prompt. 404 means the feature is off (the section hides);
 * 401/503 means the key is wrong or missing (the key form shows).
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

/** First sentence and the rest, for the headline/detail split. */
export function splitLead(text) {
  const t = (text || '').trim();
  const m = t.match(/^(.+?[.!?])(\s+|$)([\s\S]*)$/);
  if (!m || m[1].length > 140) return { lead: t, rest: '' };
  return { lead: m[1], rest: m[3].trim() };
}

export function createAsk(store) {
  let root = null;
  let key = readKey();
  let memoryKey = ''; // fallback when localStorage is unavailable
  let turns = [];     // the conversation, for server-side context
  let answer = null;  // { question, reply, sources }
  let pending = false;
  let featureOff = false;
  let error = '';
  let unsub = null;

  const $ = (sel) => root.querySelector(sel);
  const currentKey = () => key || memoryKey;

  function mount(section) {
    root = section;
    root.innerHTML = `
      <div class="section-head">
        <span class="kicker">Ask</span>
        <span class="section-note">The outlook, in its own words</span>
      </div>
      <div class="ask-body">
        <form class="ask-row" id="ask-form">
          <input class="ask-input" id="ask-input" type="text" autocomplete="off" enterkeyhint="send"
                 placeholder="Can I get on the beach in New Smyrna this afternoon?" aria-label="Your question" maxlength="1000">
          <button class="ask-send" id="ask-send" type="submit">Ask</button>
        </form>
        <p class="ask-try" id="ask-try"></p>
        <form class="ask-key" id="ask-key" hidden>
          <p class="ask-key-text" id="ask-key-text"></p>
          <div class="ask-row">
            <input class="ask-input" id="ask-key-input" type="password" autocomplete="off" placeholder="Chat key" aria-label="Chat key">
            <button class="ask-send" type="submit">Save</button>
          </div>
        </form>
        <div class="ask-answer" id="ask-answer" aria-live="polite"></div>
      </div>
    `;
    bind();
    unsub = store.subscribe(['selectedCity'], () => renderTry(store.state));
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
      send($('#ask-input').value);
    });
    $('#ask-try').addEventListener('click', (e) => {
      const btn = e.target.closest('button[data-q]');
      if (btn) {
        $('#ask-input').value = btn.dataset.q;
        send(btn.dataset.q);
      }
    });
    $('#ask-key').addEventListener('submit', (e) => {
      e.preventDefault();
      const value = $('#ask-key-input').value.trim();
      if (!value) return;
      key = value;
      memoryKey = value;
      writeKey(value);
      $('#ask-key-input').value = '';
      error = '';
      render();
      const draft = $('#ask-input').value.trim();
      if (draft) send(draft);
      else $('#ask-input').focus();
    });
    $('#ask-answer').addEventListener('click', (e) => {
      if (e.target.closest('#ask-followup')) {
        const input = $('#ask-input');
        input.value = '';
        input.focus();
      }
      if (e.target.closest('#ask-clear')) {
        turns = [];
        answer = null;
        error = '';
        $('#ask-input').value = '';
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
        error = res.status === 504
          ? 'The outlook took too long to answer. Try again.'
          : "Couldn't reach the outlook. Try again in a moment.";
        return;
      }
      const data = await res.json();
      turns.push({ role: 'assistant', text: data.reply || '' });
      answer = { question: q, reply: data.reply || '', sources: Array.isArray(data.sources) ? data.sources : [] };
    } catch {
      turns.pop();
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
    if (needsKey) {
      $('#ask-key-text').textContent = error || 'Ask is locked. Enter the chat key once; it stays in this browser.';
    }
    $('#ask-send').disabled = pending;
    $('#ask-input').disabled = pending;
    renderTry(store.state);
    renderAnswer();
  }

  function renderTry(s) {
    if (!root) return;
    const items = suggestions(s.selectedCity, s.now || new Date())
      .map((q) => `<button type="button" data-q="${escapeHTML(q)}" ${pending ? 'disabled' : ''}>${escapeHTML(q)}</button>`)
      .join('<span class="ask-sep"> · </span>');
    $('#ask-try').innerHTML = `<span class="ask-try-label">Try</span> ${items}`;
  }

  function renderAnswer() {
    const el = $('#ask-answer');
    const parts = [];
    if (pending) {
      parts.push(`<p class="ask-pending">Checking the outlook…</p>`);
    } else if (error && currentKey()) {
      parts.push(`<p class="ask-error">${escapeHTML(error)}</p>`);
    } else if (answer) {
      parts.push(renderBlock(answer));
    }
    const links = [];
    if (answer && !pending) links.push(`<button type="button" id="ask-followup">Ask a follow-up ›</button>`);
    if (answer && !pending) links.push(`<button type="button" id="ask-clear">Clear</button>`);
    if (currentKey()) links.push(`<button type="button" id="ask-forget">Forget key</button>`);
    if (links.length) parts.push(`<div class="ask-links">${links.join('<span class="ask-sep"> · </span>')}</div>`);
    el.innerHTML = parts.join('');
  }

  /** The answer in the board's voice: kicker from the facts, the reply's
   *  first sentence as the headline, the rest as detail, then only the
   *  rows that carry news. */
  function renderBlock({ reply, sources }) {
    const { lead, rest } = splitLead(reply);
    const kicker = kickerFor(sources);
    const rows = newsRows(sources);
    const days = sources.filter((s) => s.kind === 'weekend_day');
    return `
      <div class="ask-block">
        ${kicker ? `<div class="ask-kicker">${escapeHTML(kicker)}</div>` : ''}
        <p class="ask-lead">${escapeHTML(lead)}</p>
        ${rest ? `<p class="ask-rest">${escapeHTML(rest)}</p>` : ''}
        ${rows.length ? `<div class="ask-rows">${rows.join('')}</div>` : ''}
        ${days.length ? renderDays(days) : ''}
      </div>`;
  }

  function kickerFor(sources) {
    const s = sources.find((x) => x.kind === 'city_now' || x.kind === 'city_outlook' || x.kind === 'ramp_outlook');
    if (!s) return sources.some((x) => x.kind === 'weekend_day') ? 'The week ahead' : '';
    const parts = [];
    if (s.kind === 'ramp_outlook') parts.push(s.name, s.at_label);
    else parts.push(s.city, s.kind === 'city_now' ? 'right now' : s.at_label);
    if (s.kind === 'city_now' && s.open_count != null && s.ramp_count != null) {
      parts.push(`${s.open_count} of ${s.ramp_count} open`);
    }
    return parts.filter(Boolean).join(' · ');
  }

  /** Rows worth a line: a closed ramp, or one the tide could close. An
   *  open ramp with nothing but the day's close is the default and is
   *  not repeated. */
  function newsRows(sources) {
    const rows = [];
    for (const s of sources) {
      if (s.kind === 'ramp_outlook') {
        const closed = s.risk === 'closed_now';
        rows.push(row(s.name, closed, s.headline, s.detail));
      }
      if (s.kind === 'city_now' || s.kind === 'city_outlook') {
        for (const r of s.ramps || []) {
          const closed = r.risk === 'closed_now' || /^closed/i.test(r.status || '');
          const risky = r.risk === 'possible' || r.risk === 'likely';
          if (!closed && !risky) continue;
          const state = s.kind === 'city_now' && r.status
            ? statusWords(r.status)
            : (r.risk === 'likely' ? 'Tide · likely' : 'Tide · possible');
          rows.push(row(r.name, closed, state, r.headline));
        }
      }
    }
    return rows;
  }

  function row(name, closed, state, note) {
    return `
      <div class="ask-r${closed ? ' ask-r--closed' : ''}">
        <span class="ask-r-n">${escapeHTML(name || '')}</span>
        <span class="ask-r-s">${escapeHTML(state || '')}</span>
        <span class="ask-r-h">${escapeHTML(note || '')}</span>
      </div>`;
  }

  function statusWords(raw) {
    const s = (raw || '').toUpperCase().trim();
    if (s === 'OPEN') return 'Open';
    if (s === 'CLOSED FOR HIGH TIDE') return 'Closed · high tide';
    if (s === 'CLOSED - CLEARED FOR TURTLES') return 'Closed · turtles';
    if (s === 'CLOSED') return 'Closed';
    return titleCase(raw);
  }

  function renderDays(days) {
    return `<div class="ask-days">${days.map((d) => `
      <div class="ask-day" data-verdict="${escapeHTML(d.verdict || '')}">
        <span class="ask-day-n">${escapeHTML((d.weekday || d.date || '').slice(0, 3))}</span>
        <span class="ask-day-v">${escapeHTML((d.verdict || '').replace('_', ' '))}</span>
        <span class="ask-day-h">${escapeHTML(d.headline || '')}</span>
      </div>`).join('')}</div>`;
  }

  return { mount, unmount };
}
