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
