package handlers

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func TestBuildIntervals(t *testing.T) {
	windowStart := time.Date(2026, 8, 13, 14, 0, 0, 0, time.UTC)
	windowEnd := time.Date(2026, 8, 15, 14, 0, 0, 0, time.UTC)
	at := func(h int) time.Time { return windowStart.Add(time.Duration(h) * time.Hour) }

	tests := []struct {
		name          string
		events        []models.StatusEvent
		currentStatus string
		want          []models.RampStatusInterval
	}{
		{
			name:          "no events falls back to current status across the window",
			events:        nil,
			currentStatus: "OPEN",
			want: []models.RampStatusInterval{
				{Status: "OPEN", Category: "open", Start: windowStart, End: windowEnd},
			},
		},
		{
			name: "baseline only spans the whole window clamped to window start",
			events: []models.StatusEvent{
				{AccessStatus: "OPEN", RecordedAt: windowStart.Add(-6 * time.Hour)},
			},
			currentStatus: "OPEN",
			want: []models.RampStatusInterval{
				{Status: "OPEN", Category: "open", Start: windowStart, End: windowEnd},
			},
		},
		{
			name: "baseline plus changes",
			events: []models.StatusEvent{
				{AccessStatus: "OPEN", RecordedAt: windowStart.Add(-6 * time.Hour)},
				{AccessStatus: "CLOSED FOR HIGH TIDE", RecordedAt: at(30)},
				{AccessStatus: "OPEN", RecordedAt: at(34)},
			},
			currentStatus: "OPEN",
			want: []models.RampStatusInterval{
				{Status: "OPEN", Category: "open", Start: windowStart, End: at(30)},
				{Status: "CLOSED FOR HIGH TIDE", Category: "closed", Start: at(30), End: at(34)},
				{Status: "OPEN", Category: "open", Start: at(34), End: windowEnd},
			},
		},
		{
			name: "no baseline leaves an honest gap at the head",
			events: []models.StatusEvent{
				{AccessStatus: "CLOSED", RecordedAt: at(5)},
				{AccessStatus: "OPEN", RecordedAt: at(12)},
			},
			currentStatus: "OPEN",
			want: []models.RampStatusInterval{
				{Status: "CLOSED", Category: "closed", Start: at(5), End: at(12)},
				{Status: "OPEN", Category: "open", Start: at(12), End: windowEnd},
			},
		},
		{
			name: "event exactly at window start is not clamped or dropped",
			events: []models.StatusEvent{
				{AccessStatus: "4X4 ONLY", RecordedAt: windowStart},
				{AccessStatus: "OPEN", RecordedAt: at(3)},
			},
			currentStatus: "OPEN",
			want: []models.RampStatusInterval{
				{Status: "4X4 ONLY", Category: "limited", Start: windowStart, End: at(3)},
				{Status: "OPEN", Category: "open", Start: at(3), End: windowEnd},
			},
		},
		{
			name: "consecutive identical statuses merge",
			events: []models.StatusEvent{
				{AccessStatus: "OPEN", RecordedAt: windowStart.Add(-1 * time.Hour)},
				{AccessStatus: "OPEN", RecordedAt: at(8)},
				{AccessStatus: "CLOSING IN PROGRESS", RecordedAt: at(20)},
				{AccessStatus: "CLOSING IN PROGRESS", RecordedAt: at(21)},
				{AccessStatus: "CLOSED", RecordedAt: at(22)},
			},
			currentStatus: "CLOSED",
			want: []models.RampStatusInterval{
				{Status: "OPEN", Category: "open", Start: windowStart, End: at(20)},
				{Status: "CLOSING IN PROGRESS", Category: "limited", Start: at(20), End: at(22)},
				{Status: "CLOSED", Category: "closed", Start: at(22), End: windowEnd},
			},
		},
		{
			name: "event at or past window end is dropped",
			events: []models.StatusEvent{
				{AccessStatus: "OPEN", RecordedAt: windowStart.Add(-1 * time.Hour)},
				{AccessStatus: "CLOSED", RecordedAt: windowEnd},
			},
			currentStatus: "CLOSED",
			want: []models.RampStatusInterval{
				{Status: "OPEN", Category: "open", Start: windowStart, End: windowEnd},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := buildIntervals(tt.events, windowStart, windowEnd, tt.currentStatus)
			require.Len(t, got, len(tt.want))
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestParseIntervalHours(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		want    int
		wantErr bool
	}{
		{"empty defaults to 48", "", 48, false},
		{"plain value", "24", 24, false},
		{"clamps low", "0", 1, false},
		{"clamps negative", "-5", 1, false},
		{"clamps high", "500", 168, false},
		{"garbage errors", "abc", 0, true},
		{"float errors", "48.5", 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseIntervalHours(tt.raw)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestBuildIntervalsContiguity(t *testing.T) {
	// Whatever the input, produced intervals must tile without overlap:
	// each interval ends exactly where the next begins, and the last ends
	// at the window end.
	windowStart := time.Date(2026, 8, 13, 0, 0, 0, 0, time.UTC)
	windowEnd := time.Date(2026, 8, 15, 0, 0, 0, 0, time.UTC)

	events := []models.StatusEvent{
		{AccessStatus: "OPEN", RecordedAt: windowStart.Add(-2 * time.Hour)},
		{AccessStatus: "OPEN - ENTRANCE ONLY", RecordedAt: windowStart.Add(9 * time.Hour)},
		{AccessStatus: "CLOSED FOR HIGH TIDE", RecordedAt: windowStart.Add(11 * time.Hour)},
		{AccessStatus: "OPEN", RecordedAt: windowStart.Add(15 * time.Hour)},
		{AccessStatus: "CLOSED", RecordedAt: windowStart.Add(43 * time.Hour)},
	}

	got := buildIntervals(events, windowStart, windowEnd, "CLOSED")
	require.NotEmpty(t, got)
	for i := 1; i < len(got); i++ {
		assert.Equal(t, got[i-1].End, got[i].Start, "interval %d must start where %d ends", i, i-1)
	}
	assert.Equal(t, windowEnd, got[len(got)-1].End)
}
