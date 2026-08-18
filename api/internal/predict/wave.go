package predict

import (
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// maxWaveMatchGap bounds how far a wave observation can sit from a tide peak
// (or a serve moment) and still describe its sea state. Buoy 41113 reports
// every 30 minutes, so 3 hours only comes into play across outage gaps.
const maxWaveMatchGap = 3 * time.Hour

// maxWaveAge is the serve-time staleness cutoff: an observation older than
// this (buoy adrift, feed down) is treated as no wave data at all, and the
// outlook falls back to tide-only behavior.
const maxWaveAge = 6 * time.Hour

// maxWaveShiftFt clamps each learned regime shift. The whole point of the
// wave modifier is a nudge across the threshold band, never a rewrite of
// the tide model.
const maxWaveShiftFt = 0.8

// waveShift maps a current wave height to the effective-threshold shift:
// positive on calm water (more tide needed to close), negative under a real
// swell. Nil height or unlearned Waves → 0 → exactly the tide-only model.
func (p Params) waveShift(waveFt *float64) float64 {
	if waveFt == nil || p.Waves == nil {
		return 0
	}
	w := p.Waves
	switch {
	case *waveFt <= w.CalmMaxFt:
		return clampShift(w.CalmRaiseFt)
	case *waveFt >= w.RoughMinFt:
		return -clampShift(w.RoughDropFt)
	default:
		return 0
	}
}

func clampShift(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > maxWaveShiftFt {
		return maxWaveShiftFt
	}
	return v
}

// waveNearTime returns the sample nearest t within maxWaveMatchGap, or nil.
// samples must be ascending by time (sortWaveSamples arranges that).
func waveNearTime(samples []models.WaveSample, t time.Time) *models.WaveSample {
	if len(samples) == 0 {
		return nil
	}
	i := sort.Search(len(samples), func(i int) bool {
		return !samples[i].Time.Before(t)
	})

	best := -1
	bestGap := maxWaveMatchGap
	for _, j := range []int{i - 1, i} {
		if j < 0 || j >= len(samples) {
			continue
		}
		gap := samples[j].Time.Sub(t)
		if gap < 0 {
			gap = -gap
		}
		if gap <= bestGap {
			bestGap = gap
			best = j
		}
	}
	if best < 0 {
		return nil
	}
	return &samples[best]
}

// sortWaveSamples sorts samples ascending by time, in place — the order
// waveNearTime requires. NDBC realtime2 files arrive newest-first.
func sortWaveSamples(samples []models.WaveSample) {
	sort.Slice(samples, func(i, j int) bool {
		return samples[i].Time.Before(samples[j].Time)
	})
}
