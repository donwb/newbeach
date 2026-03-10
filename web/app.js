/**
 * Beach Ramp Status — Volusia County, Florida
 * Vanilla JS application (no frameworks, no build step)
 */

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
const state = {
    ramps: [],
    tideInfo: null,
    weatherInfo: null,
    config: null,
    selectedCity: 'NEW SMYRNA BEACH',
    selectedStatus: 'all',
    favorites: JSON.parse(localStorage.getItem('beach-favorites') || '[]'),
};

// ---------------------------------------------------------------------------
// DOM refs
// ---------------------------------------------------------------------------
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

// ---------------------------------------------------------------------------
// Theme (dark mode)
// ---------------------------------------------------------------------------
function initTheme() {
    const stored = localStorage.getItem('beach-theme');
    if (stored === 'dark' || (!stored && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        document.documentElement.classList.add('dark');
    }
    updateThemeIcons();

    $('#theme-toggle').addEventListener('click', () => {
        document.documentElement.classList.toggle('dark');
        const isDark = document.documentElement.classList.contains('dark');
        localStorage.setItem('beach-theme', isDark ? 'dark' : 'light');
        updateThemeIcons();
    });
}

function updateThemeIcons() {
    const isDark = document.documentElement.classList.contains('dark');
    $('#icon-sun').classList.toggle('hidden', !isDark);
    $('#icon-moon').classList.toggle('hidden', isDark);
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------
function isFavorite(accessId) {
    return state.favorites.includes(accessId);
}

function toggleFavorite(accessId) {
    const idx = state.favorites.indexOf(accessId);
    if (idx >= 0) {
        state.favorites.splice(idx, 1);
    } else {
        state.favorites.push(accessId);
    }
    localStorage.setItem('beach-favorites', JSON.stringify(state.favorites));
    renderRamps();
}

// ---------------------------------------------------------------------------
// API calls
// ---------------------------------------------------------------------------
async function fetchJSON(path) {
    const res = await fetch(path);
    if (!res.ok) throw new Error(`${path}: ${res.status}`);
    return res.json();
}

async function loadAllData() {
    try {
        const [ramps, tideInfo, config, weather, activity] = await Promise.allSettled([
            fetchJSON('/api/v2/ramps'),
            fetchJSON('/api/v2/tides'),
            fetchJSON('/api/v2/config'),
            fetchJSON('/api/v2/weather'),
            fetchJSON('/api/v2/activity?limit=20'),
        ]);

        if (ramps.status === 'fulfilled') {
            state.ramps = ramps.value;
        }
        if (tideInfo.status === 'fulfilled') {
            state.tideInfo = tideInfo.value;
            renderHeaderTide();
        }
        if (config.status === 'fulfilled') {
            state.config = config.value;
            renderWebcam();
        }
        if (weather.status === 'fulfilled') {
            state.weatherInfo = weather.value;
            renderHeaderWeather();
            renderWeatherForecast();
        }
        if (activity.status === 'fulfilled') {
            renderActivityFeed(activity.value);
        }

        buildCityFilters();
        renderRamps();
        renderCounts();
        updateLastUpdated();

        $('#loading').classList.add('hidden');

        // Load tide chart separately (slightly slower)
        loadTideChart();

    } catch (err) {
        console.error('Failed to load data:', err);
        $('#loading').innerHTML = '<p class="text-red-500">Failed to load data. Please try again.</p>';
    }
}

// ---------------------------------------------------------------------------
// Header displays
// ---------------------------------------------------------------------------
function renderHeaderTide() {
    if (!state.tideInfo) return;
    const dir = state.tideInfo.direction || state.tideInfo.tide_direction;
    const pct = state.tideInfo.percentage ?? state.tideInfo.tide_percentage;
    const avgTemp = state.tideInfo.water_temp_avg ?? state.tideInfo.waterTempAvg;

    if (dir) {
        const arrow = dir === 'Rising' ? '&#x2191;' : '&#x2193;';
        $('#tide-direction-icon').innerHTML = arrow;
        $('#tide-direction-text').textContent = dir;
        $('#tide-pct').textContent = pct != null ? `${pct}%` : '';
        $('#header-tide').classList.remove('hidden');
        $('#header-tide').classList.add('sm:flex');
    }

    if (avgTemp) {
        $('#water-temp-val').textContent = `${Math.round(avgTemp)}\u00B0F`;
        $('#header-temp').classList.remove('hidden');
        $('#header-temp').classList.add('sm:flex');
    }
}

function renderHeaderWeather() {
    if (!state.weatherInfo?.current) return;
    const c = state.weatherInfo.current;
    $('#weather-desc').textContent = c.description || '';
    $('#weather-temp').textContent = c.temperature_f ? `${Math.round(c.temperature_f)}\u00B0` : '';
    $('#header-weather').classList.remove('hidden');
    $('#header-weather').classList.add('md:flex');

    // Wind pill
    if (c.wind_speed) {
        const isCalm = c.wind_speed === '0 mph';
        $('#wind-speed').textContent = isCalm ? 'Calm' : `${c.wind_direction || ''} ${c.wind_speed}`.trim();
        if (c.wind_gust && !isCalm) {
            $('#wind-gust').textContent = `Gusts ${c.wind_gust}`;
        }
        $('#header-wind').classList.remove('hidden');
        $('#header-wind').classList.add('md:flex');
    }
}

// ---------------------------------------------------------------------------
// City filters
// ---------------------------------------------------------------------------
function buildCityFilters() {
    const cities = [...new Set(state.ramps.map(r => r.city))].sort();
    const container = $('#city-filters');

    // Keep the label, clear the rest
    const label = container.querySelector('span');
    container.innerHTML = '';
    container.appendChild(label);

    // "All Cities" button
    const allBtn = createFilterPill('All Cities', 'all');
    applyPillState(allBtn, state.selectedCity === 'all');
    allBtn.addEventListener('click', () => {
        state.selectedCity = 'all';
        updateCityFilterUI();
        renderRamps();
        renderCounts();
    });
    container.appendChild(allBtn);

    cities.forEach(city => {
        const btn = createFilterPill(titleCase(city), city);
        applyPillState(btn, state.selectedCity === city);
        btn.addEventListener('click', () => {
            state.selectedCity = city;
            updateCityFilterUI();
            renderRamps();
            renderCounts();
        });
        container.appendChild(btn);
    });
}

const PILL_BASE = 'px-3 py-1.5 text-sm rounded-full border transition-all cursor-pointer select-none whitespace-nowrap';
const PILL_INACTIVE = 'border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-300 bg-white dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-700';
const PILL_ACTIVE = 'bg-teal-600 text-white border-teal-600 dark:bg-teal-700 dark:border-teal-700 hover:bg-teal-700 dark:hover:bg-teal-600';

function createFilterPill(label, value) {
    const btn = document.createElement('button');
    btn.className = `filter-pill ${PILL_BASE} ${PILL_INACTIVE}`;
    btn.dataset.value = value;
    btn.textContent = label;
    return btn;
}

function applyPillState(btn, isActive) {
    // Remove all variable classes, reapply
    btn.className = `filter-pill ${PILL_BASE} ${isActive ? PILL_ACTIVE : PILL_INACTIVE}`;
    if (isActive) btn.classList.add('active');
}

function updateCityFilterUI() {
    $('#city-filters').querySelectorAll('.filter-pill').forEach(btn => {
        applyPillState(btn, btn.dataset.value === state.selectedCity);
    });
}

// Status filter listeners
function initStatusFilters() {
    // Apply initial Tailwind classes to the hardcoded status pills
    $('#status-filters').querySelectorAll('.filter-pill').forEach(btn => {
        const isActive = btn.dataset.status === state.selectedStatus;
        btn.className = `filter-pill ${PILL_BASE} ${isActive ? PILL_ACTIVE : PILL_INACTIVE}`;
        if (isActive) btn.classList.add('active');

        btn.addEventListener('click', () => {
            state.selectedStatus = btn.dataset.status;
            $('#status-filters').querySelectorAll('.filter-pill').forEach(b => {
                applyPillState(b, b.dataset.status === state.selectedStatus);
            });
            renderRamps();
            renderCounts();
        });
    });
}

// ---------------------------------------------------------------------------
// Ramp cards
// ---------------------------------------------------------------------------
function getFilteredRamps() {
    let filtered = [...state.ramps];

    // City filter
    if (state.selectedCity !== 'all') {
        filtered = filtered.filter(r => r.city === state.selectedCity);
    }

    // Status filter
    if (state.selectedStatus !== 'all') {
        filtered = filtered.filter(r => r.status_category === state.selectedStatus);
    }

    // Sort: favorites first, then by name
    filtered.sort((a, b) => {
        const aFav = isFavorite(a.access_id) ? 0 : 1;
        const bFav = isFavorite(b.access_id) ? 0 : 1;
        if (aFav !== bFav) return aFav - bFav;
        return a.ramp_name.localeCompare(b.ramp_name);
    });

    return filtered;
}

function renderRamps() {
    const grid = $('#ramp-grid');
    const filtered = getFilteredRamps();

    grid.innerHTML = '';

    if (filtered.length === 0) {
        $('#empty-state').classList.remove('hidden');
    } else {
        $('#empty-state').classList.add('hidden');
    }

    const borderColors = {
        open: 'border-l-4 border-l-emerald-500',
        limited: 'border-l-4 border-l-amber-500',
        closed: 'border-l-4 border-l-red-500',
    };
    const badgeColors = {
        open: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/50 dark:text-emerald-300',
        limited: 'bg-amber-100 text-amber-800 dark:bg-amber-900/50 dark:text-amber-300',
        closed: 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300',
    };

    filtered.forEach((ramp, i) => {
        const card = document.createElement('div');
        const cat = ramp.status_category || 'closed';
        const border = borderColors[cat] || borderColors.closed;
        const badge = badgeColors[cat] || badgeColors.closed;
        card.className = `ramp-card bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm border border-gray-100 dark:border-gray-700 hover:shadow-md transition-shadow duration-200 ${border}`;
        card.style.animationDelay = `${i * 0.03}s`;

        const fav = isFavorite(ramp.access_id);
        const starColor = fav
            ? 'text-amber-400 hover:text-amber-500'
            : 'text-gray-300 dark:text-gray-600 hover:text-amber-400 dark:hover:text-amber-400';
        const starSvg = fav
            ? '<svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20"><path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z"/></svg>'
            : '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"/></svg>';

        card.innerHTML = `
            <div class="flex items-start justify-between gap-2">
                <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-1">
                        <h3 class="font-bold text-sm uppercase tracking-wide truncate">${escapeHTML(ramp.ramp_name)}</h3>
                        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${badge}">
                            ${escapeHTML(ramp.access_status)}
                        </span>
                    </div>
                    <p class="text-xs text-gray-500 dark:text-gray-400">${escapeHTML(titleCase(ramp.city))}</p>
                    <p class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">${escapeHTML(titleCase(ramp.location))}</p>
                </div>
                <button class="${starColor} transition-colors cursor-pointer" onclick="toggleFavorite('${escapeHTML(ramp.access_id)}')" aria-label="Toggle favorite">
                    ${starSvg}
                </button>
            </div>
        `;

        grid.appendChild(card);
    });
}

// ---------------------------------------------------------------------------
// Counts
// ---------------------------------------------------------------------------
function renderCounts() {
    const filtered = getFilteredRamps();
    const open = filtered.filter(r => r.status_category === 'open').length;
    const limited = filtered.filter(r => r.status_category === 'limited').length;
    const closed = filtered.filter(r => r.status_category === 'closed').length;

    $('#count-total').textContent = filtered.length;
    $('#count-open').textContent = open;
    $('#count-limited').textContent = limited;
    $('#count-closed').textContent = closed;
}

// ---------------------------------------------------------------------------
// Webcam
// ---------------------------------------------------------------------------
function renderWebcam() {
    if (!state.config?.webcam_url) {
        $('#webcam-section').classList.add('hidden');
        return;
    }
    const img = $('#webcam-img');
    img.src = state.config.webcam_url;
    img.onload = () => $('#webcam-loading').classList.add('hidden');
    img.onerror = () => {
        $('#webcam-loading').textContent = 'Webcam unavailable';
    };

    // Refresh webcam every 60 seconds
    setInterval(() => {
        img.src = state.config.webcam_url + '?t=' + Date.now();
    }, 60000);
}

// ---------------------------------------------------------------------------
// Weather forecast cards
// ---------------------------------------------------------------------------
function renderWeatherForecast() {
    if (!state.weatherInfo?.forecast) {
        $('#weather-section').classList.add('hidden');
        return;
    }

    const grid = $('#weather-grid');
    grid.innerHTML = '';

    // Show first 6 forecast periods
    state.weatherInfo.forecast.slice(0, 6).forEach(period => {
        const card = document.createElement('div');
        card.className = 'text-center p-3 rounded-lg bg-gray-50 dark:bg-gray-700/50';

        const gustHtml = period.wind_gust
            ? `<div class="text-xs text-amber-600 dark:text-amber-400 mt-0.5">Gusts ${escapeHTML(period.wind_gust)}</div>`
            : '';

        card.innerHTML = `
            <div class="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">${escapeHTML(period.name)}</div>
            <div class="text-xl font-bold mb-1">${period.temperature}\u00B0${period.temp_unit || 'F'}</div>
            <div class="text-xs text-gray-600 dark:text-gray-300">${escapeHTML(period.short_description)}</div>
            <div class="text-xs text-gray-400 dark:text-gray-500 mt-1">${escapeHTML(period.wind_speed)} ${escapeHTML(period.wind_direction)}</div>
            ${gustHtml}
        `;
        grid.appendChild(card);
    });
}

// ---------------------------------------------------------------------------
// Activity feed
// ---------------------------------------------------------------------------
function renderActivityFeed(entries) {
    const feed = $('#activity-feed');
    if (!entries || entries.length === 0) {
        feed.innerHTML = '<p class="text-sm text-gray-400">No recent activity.</p>';
        return;
    }

    feed.innerHTML = '';
    entries.forEach(entry => {
        const time = formatRelativeTime(entry.recorded_at);
        const cat = categoryFromStatus(entry.access_status);
        const dotColor = cat === 'open' ? 'bg-emerald-500' : cat === 'limited' ? 'bg-amber-500' : 'bg-red-500';

        const item = document.createElement('div');
        item.className = 'flex items-center gap-3 py-1.5 text-sm';
        item.innerHTML = `
            <span class="flex-shrink-0 w-2 h-2 rounded-full ${dotColor}"></span>
            <span class="flex-1 min-w-0">
                <span class="font-medium">${escapeHTML(entry.ramp_name || entry.access_id)}</span>
                <span class="text-gray-500 dark:text-gray-400"> changed to </span>
                <span class="font-medium">${escapeHTML(entry.access_status)}</span>
            </span>
            <span class="text-xs text-gray-400 dark:text-gray-500 flex-shrink-0">${time}</span>
        `;
        feed.appendChild(item);
    });
}

// ---------------------------------------------------------------------------
// Tide chart (Canvas)
// ---------------------------------------------------------------------------
async function loadTideChart() {
    try {
        const data = await fetchJSON('/api/v2/tides/chart');
        renderTideChart(data);
    } catch (err) {
        console.warn('Tide chart unavailable:', err);
        $('#tide-chart-loading').textContent = 'Tide chart unavailable';
    }
}

function renderTideChart(data) {
    const canvas = $('#tide-chart');
    const ctx = canvas.getContext('2d');
    const dpr = window.devicePixelRatio || 1;

    // Resize canvas for sharp rendering
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const W = rect.width;
    const H = rect.height;
    const pad = { top: 20, right: 15, bottom: 30, left: 40 };

    const hourly = data.hourly || [];
    if (hourly.length === 0) {
        $('#tide-chart-loading').textContent = 'No tide data available';
        return;
    }

    $('#tide-chart-loading').classList.add('hidden');

    // Parse times and find bounds
    const points = hourly.map(p => ({
        time: new Date(p.time),
        height: p.height,
    }));

    const minTime = points[0].time.getTime();
    const maxTime = points[points.length - 1].time.getTime();
    const minH = Math.min(...points.map(p => p.height));
    const maxH = Math.max(...points.map(p => p.height));
    const hRange = maxH - minH || 1;

    const xScale = (t) => pad.left + ((t - minTime) / (maxTime - minTime)) * (W - pad.left - pad.right);
    const yScale = (h) => pad.top + (1 - (h - minH) / hRange) * (H - pad.top - pad.bottom);

    const isDark = document.documentElement.classList.contains('dark');
    const textColor = isDark ? '#9ca3af' : '#6b7280';
    const gridColor = isDark ? '#374151' : '#e5e7eb';
    const lineColor = isDark ? '#14b8a6' : '#0d9488';
    const fillColor = isDark ? 'rgba(20, 184, 166, 0.15)' : 'rgba(13, 148, 136, 0.1)';

    // Grid lines
    ctx.strokeStyle = gridColor;
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= 4; i++) {
        const y = pad.top + (i / 4) * (H - pad.top - pad.bottom);
        ctx.beginPath();
        ctx.moveTo(pad.left, y);
        ctx.lineTo(W - pad.right, y);
        ctx.stroke();
    }

    // Y-axis labels
    ctx.fillStyle = textColor;
    ctx.font = '11px system-ui, sans-serif';
    ctx.textAlign = 'right';
    for (let i = 0; i <= 4; i++) {
        const val = minH + (1 - i / 4) * hRange;
        const y = pad.top + (i / 4) * (H - pad.top - pad.bottom);
        ctx.fillText(val.toFixed(1) + ' ft', pad.left - 5, y + 4);
    }

    // X-axis labels (every 3 hours)
    ctx.textAlign = 'center';
    for (let h = 0; h <= 23; h += 3) {
        const d = new Date(points[0].time);
        d.setHours(h, 0, 0, 0);
        const x = xScale(d.getTime());
        if (x >= pad.left && x <= W - pad.right) {
            const label = h === 0 ? '12a' : h < 12 ? `${h}a` : h === 12 ? '12p' : `${h - 12}p`;
            ctx.fillText(label, x, H - pad.bottom + 15);
        }
    }

    // Filled area under curve
    ctx.beginPath();
    ctx.moveTo(xScale(points[0].time.getTime()), yScale(points[0].height));
    points.forEach(p => ctx.lineTo(xScale(p.time.getTime()), yScale(p.height)));
    ctx.lineTo(xScale(points[points.length - 1].time.getTime()), H - pad.bottom);
    ctx.lineTo(xScale(points[0].time.getTime()), H - pad.bottom);
    ctx.closePath();
    ctx.fillStyle = fillColor;
    ctx.fill();

    // Tide curve line
    ctx.beginPath();
    ctx.moveTo(xScale(points[0].time.getTime()), yScale(points[0].height));
    points.forEach(p => ctx.lineTo(xScale(p.time.getTime()), yScale(p.height)));
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 2.5;
    ctx.lineJoin = 'round';
    ctx.stroke();

    // High/Low markers
    if (data.high_low) {
        data.high_low.forEach(hl => {
            const t = new Date(hl.time).getTime();
            // Find closest hourly point for height
            let closest = points[0];
            let closestDist = Math.abs(points[0].time.getTime() - t);
            points.forEach(p => {
                const d = Math.abs(p.time.getTime() - t);
                if (d < closestDist) { closest = p; closestDist = d; }
            });

            const x = xScale(t);
            const y = yScale(closest.height);

            // Dot
            ctx.beginPath();
            ctx.arc(x, y, 4, 0, Math.PI * 2);
            ctx.fillStyle = hl.type === 'H' ? '#0d9488' : '#6366f1';
            ctx.fill();
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 1.5;
            ctx.stroke();

            // Label
            const label = hl.type === 'H' ? 'H' : 'L';
            const timeStr = new Date(hl.time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
            ctx.fillStyle = textColor;
            ctx.font = 'bold 11px system-ui, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText(`${label} ${timeStr}`, x, y + (hl.type === 'H' ? -12 : 18));
        });
    }

    // "Now" marker
    const now = new Date(data.current_time || Date.now()).getTime();
    if (now >= minTime && now <= maxTime) {
        const nx = xScale(now);
        ctx.beginPath();
        ctx.setLineDash([4, 3]);
        ctx.moveTo(nx, pad.top);
        ctx.lineTo(nx, H - pad.bottom);
        ctx.strokeStyle = isDark ? '#f59e0b' : '#d97706';
        ctx.lineWidth = 1.5;
        ctx.stroke();
        ctx.setLineDash([]);

        // "Now" label
        ctx.fillStyle = isDark ? '#f59e0b' : '#d97706';
        ctx.font = 'bold 10px system-ui, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('NOW', nx, pad.top - 5);
    }

    // Tide detail text
    renderTideDetails(data);
}

function renderTideDetails(data) {
    const container = $('#tide-details');
    if (!data.high_low || data.high_low.length === 0) return;

    container.innerHTML = data.high_low.map(hl => {
        const type = hl.type === 'H' ? 'High' : 'Low';
        const time = new Date(hl.time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        const icon = hl.type === 'H' ? '&#x2191;' : '&#x2193;';
        return `<span class="inline-flex items-center gap-1"><span class="text-ocean-600 dark:text-ocean-400">${icon}</span> ${type} at ${time}</span>`;
    }).join('');
}

// ---------------------------------------------------------------------------
// Last updated
// ---------------------------------------------------------------------------
function updateLastUpdated() {
    const now = new Date();
    const timeStr = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    $('#last-updated').textContent = `Last updated: ${timeStr}`;
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------
function titleCase(str) {
    if (!str) return '';
    return str.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
}

function escapeHTML(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function categoryFromStatus(status) {
    if (!status) return 'closed';
    const upper = status.toUpperCase();
    if (upper === 'OPEN') return 'open';
    if (['4X4 ONLY', 'CLOSING IN PROGRESS', 'OPEN - ENTRANCE ONLY'].includes(upper)) return 'limited';
    return 'closed';
}

function formatRelativeTime(dateStr) {
    if (!dateStr) return '';
    const now = Date.now();
    const then = new Date(dateStr).getTime();
    const diffMs = now - then;
    const diffMin = Math.floor(diffMs / 60000);
    const diffHr = Math.floor(diffMs / 3600000);
    const diffDay = Math.floor(diffMs / 86400000);

    if (diffMin < 1) return 'just now';
    if (diffMin < 60) return `${diffMin}m ago`;
    if (diffHr < 24) return `${diffHr}h ago`;
    if (diffDay < 7) return `${diffDay}d ago`;
    return new Date(dateStr).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// ---------------------------------------------------------------------------
// PWA: Service Worker registration
// ---------------------------------------------------------------------------
function registerServiceWorker() {
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/sw.js').catch(err => {
            console.warn('SW registration failed:', err);
        });
    }
}

// ---------------------------------------------------------------------------
// Auto-refresh
// ---------------------------------------------------------------------------
function startAutoRefresh() {
    // Refresh data every 60 seconds
    setInterval(() => {
        loadAllData();
    }, 60000);
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    initStatusFilters();
    registerServiceWorker();
    loadAllData();
    startAutoRefresh();
});
