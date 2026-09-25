package noaa

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func TestSeriesFromResponse(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		want    int
		wantErr bool
	}{
		{
			name: "water_level rows",
			raw:  `{"metadata":{"id":"8721604"},"data":[{"t":"2026-09-20 00:00","v":"2.329","s":"0.01","f":"0,0,0,0","q":"p"},{"t":"2026-09-20 00:06","v":"","s":"","f":"","q":""}]}`,
			want: 1,
		},
		{
			name: "predictions rows",
			raw:  `{"predictions":[{"t":"2026-09-20 00:00","v":"1.801"},{"t":"2026-09-20 00:06","v":"1.790"}]}`,
			want: 2,
		},
		{
			name: "no data in range is an empty series, not a failure",
			raw:  `{"error":{"message":"No data was found. This product may not be offered at this station at the requested time."}}`,
			want: 0,
		},
		{
			name:    "any other NOAA error fails",
			raw:     `{"error":{"message":" Wrong Date: The requested begin/end date or range are not valid."}}`,
			wantErr: true,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var raw noaaSeriesResponse
			require.NoError(t, json.Unmarshal([]byte(tc.raw), &raw))
			got, err := seriesFromResponse(raw)
			if tc.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Len(t, got, tc.want)
		})
	}
}

func TestHourlyResiduals(t *testing.T) {
	base := time.Date(2026, 9, 24, 10, 0, 0, 0, time.UTC)
	obs := map[time.Time]float64{}
	pred := map[time.Time]float64{}
	// Hour 10: ten full pairs, observed 1.2 ft over prediction.
	for i := 0; i < 10; i++ {
		ts := base.Add(time.Duration(i*6) * time.Minute)
		pred[ts] = 2.0
		obs[ts] = 3.2
	}
	// Hour 11: only three pairs — too thin to trust.
	for i := 0; i < 3; i++ {
		ts := base.Add(time.Hour + time.Duration(i*6)*time.Minute)
		pred[ts] = 2.0
		obs[ts] = 2.5
	}
	// An observation with no prediction partner is ignored.
	obs[base.Add(2*time.Hour)] = 9.9

	got := hourlyResiduals("8721604", obs, pred)
	require.Len(t, got, 1)
	assert.Equal(t, models.WaterLevelSample{Station: "8721604", Time: base.Add(time.Hour), ResidualFt: 1.2}, got[0],
		"stamped at the hour's end, so a trailing window never reads water not yet observed")
}

func TestDedupeHours(t *testing.T) {
	ts := time.Date(2026, 9, 24, 10, 0, 0, 0, time.UTC)
	got := dedupeHours([]models.WaterLevelSample{
		{Station: "A", Time: ts, ResidualFt: 0.1},
		{Station: "A", Time: ts.Add(time.Hour), ResidualFt: 0.2},
		{Station: "A", Time: ts, ResidualFt: 0.3},
	})
	require.Len(t, got, 2)
	assert.Equal(t, 0.3, got[0].ResidualFt, "the later chunk wins")
	assert.True(t, got[0].Time.Before(got[1].Time))
}
