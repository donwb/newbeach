package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

// flatLevels returns hourly residuals for station at a constant value over
// [from, to].
func flatLevels(station string, from, to time.Time, residualFt float64) []models.WaterLevelSample {
	var out []models.WaterLevelSample
	for t := from; !t.After(to); t = t.Add(time.Hour) {
		out = append(out, models.WaterLevelSample{Station: station, Time: t, ResidualFt: residualFt})
	}
	return out
}

func surgeParams() Params {
	return Params{Default: DefaultParams, Surge: &SurgeParams{BaselineFt: map[string]float64{"A": 0.5, "B": 0.25}}}
}

func TestTrainSurgeParams(t *testing.T) {
	now := et(20, 0, 0)
	long := flatLevels("A", now.Add(-20*24*time.Hour), now, 0.5)
	short := flatLevels("B", now.Add(-5*24*time.Hour), now, 0.3) // under the two-week floor
	future := flatLevels("A", now.Add(time.Hour), now.Add(48*time.Hour), 9.0)

	sp := trainSurgeParams(newLevelSeries(append(append(long, short...), future...)), now)
	require.NotNil(t, sp)
	assert.Equal(t, map[string]float64{"A": 0.5}, sp.BaselineFt, "short gauge skipped; future samples never set the baseline")

	assert.Nil(t, trainSurgeParams(newLevelSeries(short), now), "no gauge with enough history → nil")
	assert.Nil(t, trainSurgeParams(nil, now))
}

func TestAnomalyAt(t *testing.T) {
	now := et(20, 12, 0)
	p := surgeParams()

	tests := []struct {
		name     string
		levels   []models.WaterLevelSample
		fresh    bool
		wantOK   bool
		wantFt   float64
		stations []string
	}{
		{
			name:     "deviation from each gauge's own baseline, averaged",
			levels:   append(flatLevels("A", now.Add(-12*time.Hour), now, 1.5), flatLevels("B", now.Add(-12*time.Hour), now, 1.05)...),
			fresh:    true,
			wantOK:   true,
			wantFt:   0.9, // A +1.0, B +0.8
			stations: []string{"A", "B"},
		},
		{
			name:     "one gauge reporting is enough",
			levels:   flatLevels("B", now.Add(-12*time.Hour), now, 1.25),
			fresh:    true,
			wantOK:   true,
			wantFt:   1.0,
			stations: []string{"B"},
		},
		{
			name:     "below-normal water counts half",
			levels:   flatLevels("A", now.Add(-12*time.Hour), now, 0.1),
			fresh:    true,
			wantOK:   true,
			wantFt:   -0.2, // −0.4 × 0.5
			stations: []string{"A"},
		},
		{
			name:     "clamped",
			levels:   flatLevels("A", now.Add(-12*time.Hour), now, 5.0),
			fresh:    true,
			wantOK:   true,
			wantFt:   maxSurgeFt,
			stations: []string{"A"},
		},
		{
			name:   "too few samples in the window",
			levels: flatLevels("A", now.Add(-3*time.Hour), now, 1.5),
			fresh:  true,
		},
		{
			name:   "stale gauge sits out at serve time",
			levels: flatLevels("A", now.Add(-11*time.Hour), now.Add(-4*time.Hour), 1.5),
			fresh:  true,
		},
		{
			name:     "replaying history skips the freshness check",
			levels:   flatLevels("A", now.Add(-11*time.Hour), now.Add(-4*time.Hour), 1.5),
			fresh:    false,
			wantOK:   true,
			wantFt:   1.0,
			stations: []string{"A"},
		},
		{
			name:   "samples after t are never read",
			levels: flatLevels("A", now.Add(time.Hour), now.Add(12*time.Hour), 1.5),
			fresh:  false,
		},
		{
			name:   "gauge without a learned baseline is ignored",
			levels: flatLevels("C", now.Add(-12*time.Hour), now, 3.0),
			fresh:  true,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ft, _, stations, ok := p.anomalyAt(newLevelSeries(tc.levels), now, tc.fresh)
			require.Equal(t, tc.wantOK, ok)
			if ok {
				assert.InDelta(t, tc.wantFt, ft, 0.001)
				assert.Equal(t, tc.stations, stations)
			}
		})
	}
}

func TestWithSurge(t *testing.T) {
	now := et(20, 9, 0)
	preds := []models.TidePrediction{
		h(et(20, 3, 0), 2.0),             // earlier today: observed anomaly at the time
		h(et(20, 15, 0), 2.5),            // later today: the reading now, full strength
		h(et(21, 15, 0), 2.5),            // tomorrow: decayed one day
		h(et(23, 15, 0), 2.5),            // three days out
		{Time: et(20, 21, 0), Type: "L"}, // no height: untouched
	}
	// +1.0 over baseline A through 3am, then +0.6 through now.
	levels := append(flatLevels("A", et(19, 12, 0), et(20, 3, 0), 1.5), flatLevels("A", et(20, 4, 0), now, 1.1)...)

	p := surgeParams()
	water, ctx := p.withSurge(preds, levels, now)
	require.NotNil(t, ctx)
	assert.InDelta(t, 0.8, ctx.AnomalyFt, 0.001, "the 12h window straddles the step: six hours at +1.0, six at +0.6")
	assert.Equal(t, []string{"A"}, ctx.Stations)

	assert.InDelta(t, 3.0, *water[0].Height, 0.001, "past peak uses the anomaly observed then")
	assert.InDelta(t, 2.5+ctx.AnomalyFt, *water[1].Height, 0.001)
	assert.InDelta(t, 2.5+ctx.AnomalyFt*surgeDailyCarry, *water[2].Height, 0.001)
	assert.InDelta(t, 2.5+ctx.AnomalyFt*surgeDailyCarry*surgeDailyCarry*surgeDailyCarry, *water[3].Height, 0.001)
	assert.Nil(t, water[4].Height)
	assert.Equal(t, 2.5, *preds[1].Height, "the caller's predictions are never mutated")

	t.Run("nil everywhere is the predicted-tide engine exactly", func(t *testing.T) {
		out, ctx := Params{Default: DefaultParams}.withSurge(preds, levels, now)
		assert.Equal(t, preds, out)
		assert.Nil(t, ctx)
		out, ctx = p.withSurge(preds, nil, now)
		assert.Equal(t, preds, out)
		assert.Nil(t, ctx)
	})

	t.Run("stale series: history still adjusts, the future assumes normal water", func(t *testing.T) {
		stale := flatLevels("A", et(19, 12, 0), et(20, 4, 0), 1.5)
		out, ctx := p.withSurge(preds, stale, now)
		assert.Nil(t, ctx)
		assert.InDelta(t, 3.0, *out[0].Height, 0.001)
		assert.Equal(t, 2.5, *out[1].Height)
	})
}

// The outlook must read risk off the water, but keep NOAA's own numbers in
// the tide context clients display.
func TestBuildOutlookSurge(t *testing.T) {
	now := et(16, 9, 0)
	preds := []models.TidePrediction{h(et(16, 14, 0), 2.4), {Time: et(16, 20, 0), Type: "L", Height: new(float64)}}
	params := Params{
		Default:     DefaultParams,
		HardOpenFt:  2.0,
		HardCloseFt: 3.5,
		Ramps:       map[string]RampParams{"NS-141": {ThresholdFt: 2.9, CloseRate: 0.2, LeadMin: 90, LagMin: 60}},
		Surge:       &SurgeParams{BaselineFt: map[string]float64{"A": 0.5}},
	}
	ramps := []models.RampStatusWithSince{ramp(1, "NS-141", "OPEN")}

	calm := BuildOutlook(now, ramps, params, preds, nil, nil, nil)
	assert.Equal(t, RiskScheduled, calm.Ramps[0].Risk, "2.4 ft predicted, normal water: no tide story")
	assert.Nil(t, calm.Surge)

	high := flatLevels("A", now.Add(-12*time.Hour), now, 1.7) // +1.2 ft
	surged := BuildOutlook(now, ramps, params, preds, nil, high, nil)
	assert.Equal(t, RiskLikely, surged.Ramps[0].Risk, "3.6 ft of real water clears the hard cutoff")
	require.NotNil(t, surged.Surge)
	assert.InDelta(t, 1.2, surged.Surge.AnomalyFt, 0.001)
	assert.Equal(t, 2.4, *surged.Tide.NextPeakFt, "the tide context carries NOAA's prediction")
}
