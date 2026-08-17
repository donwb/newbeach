package handlers

import (
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
