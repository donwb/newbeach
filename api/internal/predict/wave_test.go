package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func ws(t time.Time, ft float64) models.WaveSample {
	return models.WaveSample{Time: t, HeightFt: ft}
}

func TestWaveNearTime(t *testing.T) {
	base := time.Date(2026, 6, 16, 12, 0, 0, 0, time.UTC)
	samples := []models.WaveSample{
		ws(base, 1.0),
		ws(base.Add(30*time.Minute), 2.0),
		ws(base.Add(8*time.Hour), 3.0),
	}

	t.Run("picks the nearer neighbor", func(t *testing.T) {
		got := waveNearTime(samples, base.Add(20*time.Minute))
		require.NotNil(t, got)
		assert.Equal(t, 2.0, got.HeightFt)
	})

	t.Run("exact match", func(t *testing.T) {
		got := waveNearTime(samples, base)
		require.NotNil(t, got)
		assert.Equal(t, 1.0, got.HeightFt)
	})

	t.Run("outage gap beyond the match window", func(t *testing.T) {
		assert.Nil(t, waveNearTime(samples, base.Add(4*time.Hour)),
			"3.5h from both neighbors — no sea state to claim")
	})

	t.Run("before the series within the window", func(t *testing.T) {
		got := waveNearTime(samples, base.Add(-time.Hour))
		require.NotNil(t, got)
		assert.Equal(t, 1.0, got.HeightFt)
	})

	t.Run("empty and nil", func(t *testing.T) {
		assert.Nil(t, waveNearTime(nil, base))
		assert.Nil(t, waveNearTime([]models.WaveSample{}, base))
	})
}

func TestWaveShift(t *testing.T) {
	waves := &WaveParams{CalmMaxFt: 1.5, RoughMinFt: 3.0, CalmRaiseFt: 0.5, RoughDropFt: 0.4}
	p := Params{Waves: waves}

	tests := []struct {
		name   string
		waveFt *float64
		want   float64
	}{
		{"calm raises", ptrF(1.2), 0.5},
		{"calm boundary", ptrF(1.5), 0.5},
		{"neutral is zero", ptrF(2.0), 0},
		{"rough drops", ptrF(3.4), -0.4},
		{"rough boundary", ptrF(3.0), -0.4},
		{"nil height is zero", nil, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.InDelta(t, tt.want, p.waveShift(tt.waveFt), 0.001)
		})
	}

	t.Run("unlearned params are zero", func(t *testing.T) {
		assert.Zero(t, Params{}.waveShift(ptrF(1.0)))
	})

	t.Run("shifts clamp to the cap", func(t *testing.T) {
		wild := Params{Waves: &WaveParams{CalmMaxFt: 1.5, RoughMinFt: 3.0, CalmRaiseFt: 5, RoughDropFt: -1}}
		assert.InDelta(t, maxWaveShiftFt, wild.waveShift(ptrF(1.0)), 0.001)
		assert.Zero(t, wild.waveShift(ptrF(4.0)), "negative drop clamps to no shift")
	})
}

// syntheticWavePool builds a pool where calm-day peaks in the band above the
// threshold never closed (so a calm raise helps) and everything else follows
// the threshold.
func syntheticWavePool(n int) []wavePeakSample {
	var pool []wavePeakSample
	for i := 0; i < n; i++ {
		calm := i%2 == 0
		waveFt := 3.5
		if calm {
			waveFt = 1.0
		}
		// Peaks alternate around a 2.6 threshold.
		peakFt := 2.2 + 0.1*float64(i%8) // 2.2 … 2.9
		label := peakFt >= 2.6
		if calm && peakFt < 3.0 {
			label = false // flat ocean: the band above threshold stays open
		}
		pool = append(pool, wavePeakSample{peakFt: peakFt, thresholdFt: 2.6, label: label, waveFt: waveFt})
	}
	return pool
}

func TestTrainWaveParams(t *testing.T) {
	t.Run("learns calm suppression", func(t *testing.T) {
		wp := trainWaveParams(syntheticWavePool(120))
		require.NotNil(t, wp)
		assert.Greater(t, wp.CalmRaiseFt, 0.0, "calm days that never close should raise the bar")
		assert.LessOrEqual(t, wp.CalmRaiseFt, maxWaveShiftFt)
		assert.Equal(t, 120, wp.NSamples)
	})

	t.Run("thin pool stays nil", func(t *testing.T) {
		assert.Nil(t, trainWaveParams(syntheticWavePool(minWavePoolSamples-1)))
		assert.Nil(t, trainWaveParams(nil))
	})

	t.Run("no gain stays zero", func(t *testing.T) {
		// Labels follow the tide threshold exactly, wave height carries no
		// signal — both shifts must stay 0.
		var pool []wavePeakSample
		for i := 0; i < 100; i++ {
			peakFt := 2.0 + 0.1*float64(i%12)
			pool = append(pool, wavePeakSample{
				peakFt:      peakFt,
				thresholdFt: 2.6,
				label:       peakFt >= 2.6,
				waveFt:      1.0 + 0.03*float64(i%80),
			})
		}
		wp := trainWaveParams(pool)
		require.NotNil(t, wp)
		assert.Zero(t, wp.CalmRaiseFt)
		assert.Zero(t, wp.RoughDropFt)
	})
}

func TestBuildOutlookWaveHandling(t *testing.T) {
	// afternoonScenario: 3.4 ft peak at 3:30 PM ET. NS-106 (threshold 3.25,
	// close rate 0.26) reads it "possible" tide-only; a calm raise of 0.6
	// moves its band above the peak and the mid-range rule doesn't catch it
	// (low close rate) → "none". NS-141 (threshold 2.1) stays "likely"
	// either way — a peak that decisively clears the band is not for the
	// buoy to wave off.
	now, preds := afternoonScenario()
	ramps := []models.RampStatusWithSince{
		ramp(1, "NS-141", "OPEN"),
		ramp(2, "NS-106", "OPEN"),
	}
	params := testParams()
	params.Waves = &WaveParams{CalmMaxFt: 1.5, RoughMinFt: 3.0, CalmRaiseFt: 0.6, RoughDropFt: 0.3}

	riskByID := func(out Outlook) map[string]string {
		m := make(map[string]string)
		for _, ro := range out.Ramps {
			m[ro.AccessID] = ro.Risk
		}
		return m
	}

	t.Run("fresh calm observation demotes marginal risk and surfaces surf", func(t *testing.T) {
		calm := &models.WaveSample{Time: now.Add(-30 * time.Minute), HeightFt: 1.2}
		out := BuildOutlook(now, ramps, params, preds, calm)
		require.NotNil(t, out.Surf)
		assert.Equal(t, "calm", out.Surf.Regime)
		assert.InDelta(t, 1.2, out.Surf.WaveHeightFt, 0.001)
		risks := riskByID(out)
		assert.Equal(t, RiskLikely, risks["NS-141"], "decisive peaks ignore the buoy")
		assert.Equal(t, RiskScheduled, risks["NS-106"], "flat ocean silences the marginal call")
	})

	t.Run("rough observation keeps the marginal call flagged", func(t *testing.T) {
		rough := &models.WaveSample{Time: now.Add(-30 * time.Minute), HeightFt: 3.6}
		out := BuildOutlook(now, ramps, params, preds, rough)
		require.NotNil(t, out.Surf)
		assert.Equal(t, "rough", out.Surf.Regime)
		// The drop widens NS-106's possible band downward, but never
		// promotes to likely — only tide evidence does that.
		assert.Equal(t, RiskPossible, riskByID(out)["NS-106"])
	})

	t.Run("stale observation is ignored", func(t *testing.T) {
		stale := &models.WaveSample{Time: now.Add(-7 * time.Hour), HeightFt: 1.2}
		out := BuildOutlook(now, ramps, params, preds, stale)
		assert.Nil(t, out.Surf, "a 7h-old reading is no reading")
		assert.Equal(t, RiskPossible, riskByID(out)["NS-106"], "tide-only behavior")
	})

	t.Run("nil wave is tide-only", func(t *testing.T) {
		out := BuildOutlook(now, ramps, params, preds, nil)
		assert.Nil(t, out.Surf)
		assert.Equal(t, RiskPossible, riskByID(out)["NS-106"])
	})
}

func ptrF(f float64) *float64 { return &f }

func TestScorecardCarriesWaveContext(t *testing.T) {
	history := map[string][]models.StatusEvent{
		"NS-141": statusEvents(ev("OPEN", et(1, 8, 0))),
	}
	dpd := 11.0
	waves := []models.WaveSample{
		// Newest-first on purpose — BuildScorecard must sort before matching.
		{Time: et(16, 16, 0), HeightFt: 1.7, DominantPeriodS: &dpd},
		{Time: et(16, 8, 0), HeightFt: 2.4},
	}

	sc := BuildScorecard(et(16, 0, 0), history, nil, testParams(), scorecardPreds(), waves)

	require.Len(t, sc.Ramps, 1)
	require.Len(t, sc.Ramps[0].Peaks, 1)
	pg := sc.Ramps[0].Peaks[0]
	require.NotNil(t, pg.WaveHeightFt, "peak at 15:30 matches the 16:00 observation")
	assert.InDelta(t, 1.7, *pg.WaveHeightFt, 0.001)
	require.NotNil(t, pg.DominantPeriodS)
	assert.InDelta(t, 11.0, *pg.DominantPeriodS, 0.001)
	require.NotNil(t, pg.WaveObservedAt)
	assert.Equal(t, et(16, 16, 0), pg.WaveObservedAt.In(eastern))
}
