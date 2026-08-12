package ingester

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestHealthStatus(t *testing.T) {
	now := time.Date(2026, 8, 12, 12, 0, 0, 0, time.UTC)
	interval := time.Minute

	tests := []struct {
		name   string
		health Health
		want   string
	}{
		{
			name:   "no poll yet",
			health: Health{PollInterval: interval},
			want:   "starting",
		},
		{
			name: "clean recent poll",
			health: Health{
				LastPollAt:      now.Add(-30 * time.Second),
				LastCleanPollAt: now.Add(-30 * time.Second),
				PollInterval:    interval,
			},
			want: "ok",
		},
		{
			name: "query failures last cycle",
			health: Health{
				LastPollAt:      now.Add(-30 * time.Second),
				LastCleanPollAt: now.Add(-30 * time.Second),
				QueriesFailed:   2,
				PollInterval:    interval,
			},
			want: "degraded",
		},
		{
			name: "feature failures last cycle",
			health: Health{
				LastPollAt:      now.Add(-30 * time.Second),
				LastCleanPollAt: now.Add(-2 * time.Hour),
				FeaturesFailed:  12,
				PollInterval:    interval,
			},
			want: "degraded",
		},
		{
			name: "polling but no clean poll within 5 intervals",
			health: Health{
				LastPollAt:      now.Add(-30 * time.Second),
				LastCleanPollAt: now.Add(-6 * time.Minute),
				PollInterval:    interval,
			},
			want: "degraded",
		},
		{
			name: "clean poll just inside the staleness window",
			health: Health{
				LastPollAt:      now.Add(-4 * time.Minute),
				LastCleanPollAt: now.Add(-4 * time.Minute),
				PollInterval:    interval,
			},
			want: "ok",
		},
		{
			name: "poll loop stalled entirely",
			health: Health{
				LastPollAt:      now.Add(-time.Hour),
				LastCleanPollAt: now.Add(-time.Hour),
				PollInterval:    interval,
			},
			want: "degraded",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, tt.health.Status(now))
		})
	}
}
