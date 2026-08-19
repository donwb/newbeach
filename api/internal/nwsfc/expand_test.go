package nwsfc

import (
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestExpandValidTime(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		start   string
		dur     time.Duration
		wantErr bool
	}{
		{name: "one hour", in: "2026-08-18T18:00:00+00:00/PT1H", start: "2026-08-18T18:00:00Z", dur: time.Hour},
		{name: "thirteen hours", in: "2026-08-18T18:00:00+00:00/PT13H", start: "2026-08-18T18:00:00Z", dur: 13 * time.Hour},
		{name: "one day", in: "2026-08-18T18:00:00+00:00/P1D", start: "2026-08-18T18:00:00Z", dur: 24 * time.Hour},
		{name: "day plus hours", in: "2026-08-20T03:00:00+00:00/P1DT6H", start: "2026-08-20T03:00:00Z", dur: 30 * time.Hour},
		{name: "minutes", in: "2026-08-18T18:00:00+00:00/PT30M", start: "2026-08-18T18:00:00Z", dur: 30 * time.Minute},
		{name: "missing duration", in: "2026-08-18T18:00:00+00:00", wantErr: true},
		{name: "garbage duration", in: "2026-08-18T18:00:00+00:00/banana", wantErr: true},
		{name: "zero duration", in: "2026-08-18T18:00:00+00:00/PT0H", wantErr: true},
		{name: "garbage start", in: "not-a-time/PT1H", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			start, dur, err := expandValidTime(tt.in)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			want, _ := time.Parse(time.RFC3339, tt.start)
			assert.True(t, start.Equal(want), "start %v != %v", start, want)
			assert.Equal(t, tt.dur, dur)
		})
	}
}

func loadFixture(t *testing.T, name string) *gridpointResponse {
	t.Helper()
	raw, err := os.ReadFile("testdata/" + name)
	require.NoError(t, err)
	var resp gridpointResponse
	require.NoError(t, json.Unmarshal(raw, &resp))
	return &resp
}

func TestExpandLandFixture(t *testing.T) {
	resp := loadFixture(t, "land_gridpoint.json")
	// FetchedAt near the fixture's capture time so the horizon covers it.
	fetched := earliestSeriesStart(t, resp)
	lf := expandLand(resp, fetched)

	require.NotEmpty(t, lf.Hours)

	// Hours are sorted and unique.
	for i := 1; i < len(lf.Hours); i++ {
		assert.True(t, lf.Hours[i-1].Time.Before(lf.Hours[i].Time), "hours out of order at %d", i)
	}

	// The land grid always carries temperature; the first covered hour must
	// have a plausible Florida Fahrenheit value (i.e. C→F conversion ran).
	var sawTemp, sawWind, sawPoP bool
	for _, h := range lf.Hours {
		if h.TempF != nil {
			sawTemp = true
			assert.Greater(t, *h.TempF, 30.0, "temperature not converted to F")
			assert.Less(t, *h.TempF, 130.0)
		}
		if h.WindMph != nil {
			sawWind = true
			assert.Less(t, *h.WindMph, 120.0, "wind not converted to mph")
		}
		if h.PoPPct != nil {
			sawPoP = true
			assert.GreaterOrEqual(t, *h.PoPPct, 0.0)
			assert.LessOrEqual(t, *h.PoPPct, 100.0)
		}
	}
	assert.True(t, sawTemp, "no temperature samples expanded")
	assert.True(t, sawWind, "no wind samples expanded")
	assert.True(t, sawPoP, "no PoP samples expanded")

	// The horizon cap holds.
	last := lf.Hours[len(lf.Hours)-1].Time
	assert.True(t, last.Before(fetched.Add(landHorizon)), "expansion exceeded horizon")
}

func TestExpandMarineFixture(t *testing.T) {
	resp := loadFixture(t, "marine_gridpoint.json")
	fetched := earliestSeriesStart(t, resp)
	mf := expandMarine(resp, fetched)

	require.NotEmpty(t, mf.Blocks)

	var sawHeight, sawPeriod bool
	for _, b := range mf.Blocks {
		assert.True(t, b.End.After(b.Start))
		if b.HeightFt != nil {
			sawHeight = true
			// Meters→feet conversion: nearshore Atlantic forecast heights in
			// feet are single digits, never sub-meter raw values times nothing.
			assert.Less(t, *b.HeightFt, 60.0)
		}
		if b.PeriodS != nil {
			sawPeriod = true
			assert.Greater(t, *b.PeriodS, 0.0)
			assert.Less(t, *b.PeriodS, 30.0)
		}
	}
	assert.True(t, sawHeight, "no wave height blocks")
	assert.True(t, sawPeriod, "no wave period blocks")
}

func TestMaxHeightFtBetween(t *testing.T) {
	ft := func(v float64) *float64 { return &v }
	t0 := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	mf := &MarineForecast{Blocks: []WaveBlock{
		{Start: t0, End: t0.Add(6 * time.Hour), HeightFt: ft(2.0)},
		{Start: t0.Add(6 * time.Hour), End: t0.Add(12 * time.Hour), HeightFt: ft(4.5)},
		{Start: t0, End: t0.Add(12 * time.Hour), PeriodS: ft(9)}, // period-only block ignored
	}}

	// Window overlapping both height blocks takes the max.
	got := mf.MaxHeightFtBetween(t0.Add(5*time.Hour), t0.Add(7*time.Hour))
	require.NotNil(t, got)
	assert.Equal(t, 4.5, *got)

	// Window inside the first block only.
	got = mf.MaxHeightFtBetween(t0, t0.Add(2*time.Hour))
	require.NotNil(t, got)
	assert.Equal(t, 2.0, *got)

	// Window with no overlap.
	assert.Nil(t, mf.MaxHeightFtBetween(t0.Add(24*time.Hour), t0.Add(30*time.Hour)))
}

func TestExpandLandHeatHazard(t *testing.T) {
	raw := `{"properties":{
		"temperature":{"uom":"wmoUnit:degC","values":[{"validTime":"2026-08-18T12:00:00+00:00/PT4H","value":35}]},
		"hazards":{"values":[
			{"validTime":"2026-08-18T13:00:00+00:00/PT2H","value":[{"phenomenon":"HT","significance":"Y"}]},
			{"validTime":"2026-08-18T15:00:00+00:00/PT1H","value":[{"phenomenon":"SC","significance":"Y"}]}
		]}
	}}`
	var resp gridpointResponse
	require.NoError(t, json.Unmarshal([]byte(raw), &resp))

	fetched := time.Date(2026, 8, 18, 12, 0, 0, 0, time.UTC)
	lf := expandLand(&resp, fetched)

	byHour := map[int]HourlySample{}
	for _, h := range lf.Hours {
		byHour[h.Time.Hour()] = h
	}
	assert.False(t, byHour[12].HeatAdvisory)
	assert.True(t, byHour[13].HeatAdvisory)
	assert.True(t, byHour[14].HeatAdvisory)
	assert.False(t, byHour[15].HeatAdvisory, "small craft advisory is not a heat hazard")
}

// earliestSeriesStart digs out the earliest validTime in the fixture so tests
// stay valid as fixtures get regenerated with fresh timestamps.
func earliestSeriesStart(t *testing.T, resp *gridpointResponse) time.Time {
	t.Helper()
	var earliest time.Time
	consider := func(vals []valuedPoint) {
		for _, v := range vals {
			start, _, err := expandValidTime(v.ValidTime)
			if err != nil {
				continue
			}
			if earliest.IsZero() || start.Before(earliest) {
				earliest = start
			}
		}
	}
	p := resp.Properties
	for _, s := range []valuedSeries{p.Temperature, p.PoP, p.WindSpeed, p.WaveHeight, p.WavePeriod} {
		consider(s.Values)
	}
	require.False(t, earliest.IsZero(), "fixture has no parseable series")
	return earliest.UTC()
}
