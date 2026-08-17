package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestIsPageView pins which paths count as page navigations: the board, the
// static county page, and SPA deep links — never assets or API calls. A miss
// here either spams the table with asset noise or silently drops the county
// visits the feature exists to catch.
func TestIsPageView(t *testing.T) {
	tests := []struct {
		path string
		want bool
	}{
		{"/", true},
		{"/county", true},
		{"/county/", true},
		{"/tide", true},
		{"/tide/", true},
		{"/water", true},
		{"/wind", true},
		{"/ramp/3", true},
		{"/ramp/12/", true},

		{"/county/web-desktop.jpg", false},
		{"/county/index.css", false},
		{"/api/v2/ramps", false},
		{"/api/v2/health", false},
		{"/rampstatus", false},
		{"/app.js", false},
		{"/sw.js", false},
		{"/styles.css", false},
		{"/icons/icon.svg", false},
		{"/fonts/archivo-800.woff2", false},
		{"/ramp/abc", false},
		{"/tides", false},
		{"/countyx", false},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			assert.Equal(t, tt.want, isPageView(tt.path))
		})
	}
}

// TestParsePageViewSince pins the admin endpoint's window parsing: empty
// defaults to the last 7 days, bare dates mean midnight UTC, RFC 3339 passes
// through, and garbage errors.
func TestParsePageViewSince(t *testing.T) {
	now := time.Date(2026, 8, 17, 12, 0, 0, 0, time.UTC)

	t.Run("empty defaults to 7 days back", func(t *testing.T) {
		got, err := parsePageViewSince("", now)
		require.NoError(t, err)
		assert.Equal(t, now.AddDate(0, 0, -7), got)
	})

	t.Run("bare date", func(t *testing.T) {
		got, err := parsePageViewSince("2026-08-18", now)
		require.NoError(t, err)
		assert.Equal(t, time.Date(2026, 8, 18, 0, 0, 0, 0, time.UTC), got)
	})

	t.Run("rfc3339", func(t *testing.T) {
		got, err := parsePageViewSince("2026-08-18T09:30:00-04:00", now)
		require.NoError(t, err)
		assert.Equal(t, "2026-08-18T09:30:00-04:00", got.Format(time.RFC3339))
	})

	t.Run("garbage errors", func(t *testing.T) {
		_, err := parsePageViewSince("yesterday", now)
		require.Error(t, err)
	})
}

// TestSplitIPs pins exclude_ip parsing: comma-separated, whitespace-tolerant,
// empties dropped.
func TestSplitIPs(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want []string
	}{
		{"empty", "", nil},
		{"single", "1.2.3.4", []string{"1.2.3.4"}},
		{"multiple with spaces", " 1.2.3.4 , 5.6.7.8 ", []string{"1.2.3.4", "5.6.7.8"}},
		{"trailing comma", "1.2.3.4,", []string{"1.2.3.4"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, splitIPs(tt.raw))
		})
	}
}

// TestCleanReferer pins that the service worker's own script URL never lands in
// the log as a referrer. Before navigation preload the worker re-issued
// navigations itself, and the browser stamped Referer as /sw.js — which made
// every repeat visitor look like a self-referral and hid where they came from.
func TestCleanReferer(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{"empty stays empty", "", ""},
		{"own service worker dropped", "https://beach.donwb.com/sw.js", ""},
		{"service worker on any host dropped", "http://localhost:8080/sw.js", ""},
		{"service worker with query dropped", "https://beach.donwb.com/sw.js?v=2", ""},

		{"real external referrer kept", "https://www.google.com/", "https://www.google.com/"},
		{"internal navigation kept", "https://beach.donwb.com/county/", "https://beach.donwb.com/county/"},
		{"portfolio referral kept", "https://donwb.com/", "https://donwb.com/"},
		{"path merely containing sw.js kept", "https://beach.donwb.com/docs/sw.js.html", "https://beach.donwb.com/docs/sw.js.html"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cleanReferer(tt.raw))
		})
	}
}

// TestCleanRefererClips keeps an attacker-supplied Referer from bloating the
// table, matching the 500-byte cap the user agent gets.
func TestCleanRefererClips(t *testing.T) {
	got := cleanReferer("https://example.com/" + strings.Repeat("a", 900))
	require.Len(t, got, 500)
}

// TestIsNavigationRequest pins the header combinations observed in a real
// Chrome + service worker session (see the two-origin harness used to diagnose
// the /sw.js referer leak). The install-time precache of "/" arrives as a cors
// fetch and must never be logged as a visit, while a genuine navigation must
// survive both the navigation-preload path and the worker-forwarded fallback.
func TestIsNavigationRequest(t *testing.T) {
	tests := []struct {
		name string
		mode string
		want bool
	}{
		{"browser-issued navigation", "navigate", true},
		{"worker-forwarded navigation keeps mode", "navigate", true},
		{"service worker precache of / is not a visit", "cors", false},
		{"same-origin script fetch is not a visit", "same-origin", false},
		{"no-cors subresource is not a visit", "no-cors", false},
		{"pre-Fetch-Metadata browser is trusted", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/", nil)
			if tt.mode != "" {
				r.Header.Set("Sec-Fetch-Mode", tt.mode)
			}
			assert.Equal(t, tt.want, isNavigationRequest(r))
		})
	}
}
