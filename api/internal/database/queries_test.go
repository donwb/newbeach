package database

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// normalizeSQL collapses all whitespace runs to single spaces so tests can
// compare query text without caring about indentation.
func normalizeSQL(q string) string {
	return strings.Join(strings.Fields(q), " ")
}

func TestBuildRecentHistoryQuery(t *testing.T) {
	since := time.Date(2026, 8, 15, 12, 0, 0, 0, time.UTC)

	const base = "SELECT h.id, h.access_id, h.access_status, h.recorded_at, r.ramp_name, r.city " +
		"FROM ramp_status_history h " +
		"JOIN ramp_status r ON h.access_id = r.access_id"

	tests := []struct {
		name     string
		city     string
		ramp     string
		since    *time.Time
		wantSQL  string
		wantArgs []interface{}
	}{
		{
			name:     "no filters matches the original unfiltered query",
			wantSQL:  base + " ORDER BY h.recorded_at DESC LIMIT $1",
			wantArgs: []interface{}{50},
		},
		{
			name:     "city only",
			city:     "New Smyrna Beach",
			wantSQL:  base + " WHERE r.city = $1 ORDER BY h.recorded_at DESC LIMIT $2",
			wantArgs: []interface{}{"New Smyrna Beach", 50},
		},
		{
			name:     "ramp only",
			ramp:     "NSB-001",
			wantSQL:  base + " WHERE h.access_id = $1 ORDER BY h.recorded_at DESC LIMIT $2",
			wantArgs: []interface{}{"NSB-001", 50},
		},
		{
			name:     "since only",
			since:    &since,
			wantSQL:  base + " WHERE h.recorded_at >= $1 ORDER BY h.recorded_at DESC LIMIT $2",
			wantArgs: []interface{}{since, 50},
		},
		{
			name:  "all filters keep placeholder numbering in order",
			city:  "New Smyrna Beach",
			ramp:  "NSB-001",
			since: &since,
			wantSQL: base + " WHERE r.city = $1 AND h.access_id = $2 AND h.recorded_at >= $3" +
				" ORDER BY h.recorded_at DESC LIMIT $4",
			wantArgs: []interface{}{"New Smyrna Beach", "NSB-001", since, 50},
		},
		{
			name:     "city and since without ramp renumbers correctly",
			city:     "New Smyrna Beach",
			since:    &since,
			wantSQL:  base + " WHERE r.city = $1 AND h.recorded_at >= $2 ORDER BY h.recorded_at DESC LIMIT $3",
			wantArgs: []interface{}{"New Smyrna Beach", since, 50},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotSQL, gotArgs := buildRecentHistoryQuery(50, tt.city, tt.ramp, tt.since)
			assert.Equal(t, tt.wantSQL, normalizeSQL(gotSQL))
			require.Equal(t, tt.wantArgs, gotArgs)
			// The limit is always the last placeholder.
			assert.Equal(t, 50, gotArgs[len(gotArgs)-1])
		})
	}
}
