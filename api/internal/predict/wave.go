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

// longPeriodS is the dominant period at or above which the sea state counts
// as rough whatever the buoy height reads. A 14-second groundswell at 1.3 ft
// carries far more run-up than 4-second chop at 1.3 ft — 2026-08-22 was the
// case study: flat height all day, period 4 s → 14 s at 10am, four NS ramps
// closed at 3:30pm under a height-only "calm" read. Fixture evidence: in the
// not-calm height regime long-period peaks close 63% vs 50% (Daytona ramps
// 85% vs 53%). Backtest (2026-08-23, six ramps, five months): this rule
// catches 6 more closure days for 20 fewer quiet days, monotonic across
// 9–12 s cutoffs — no cliff.
//
// Fallback plan (Don, 2026-08-23): if a week of scorecards says this is
// over-hedging, the next thing to try is the conservative variant — a long
// period only *disqualifies* calm (shift 0) instead of counting as rough.
// Measured: 3 more closure days caught for 7 fewer quiet days.
const longPeriodS = 10.0

// waveShift maps a current wave height to the effective-threshold shift:
// positive on calm water (more tide needed to close), negative under a real
// swell. Nil height or unlearned Waves → 0 → exactly the tide-only model.
// Height-only; use waveShiftFor when the period is known.
func (p Params) waveShift(waveFt *float64) float64 {
	return p.waveShiftFor(waveFt, nil)
}

// waveShiftFor is waveShift with the dominant period: a period at or above
// longPeriodS is rough regardless of height (see longPeriodS). Nil period
// falls back to the height regimes alone.
func (p Params) waveShiftFor(waveFt, periodS *float64) float64 {
	if waveFt == nil || p.Waves == nil {
		return 0
	}
	w := p.Waves
	switch {
	case isLongPeriod(periodS):
		return -clampShift(w.RoughDropFt)
	case *waveFt <= w.CalmMaxFt:
		return clampShift(w.CalmRaiseFt)
	case *waveFt >= w.RoughMinFt:
		return -clampShift(w.RoughDropFt)
	default:
		return 0
	}
}

func isLongPeriod(periodS *float64) bool {
	return periodS != nil && *periodS >= longPeriodS
}

// waveRegime names the regime waveShiftFor applied, for payload echoes.
func (p Params) waveRegime(waveFt float64, periodS *float64) string {
	if p.Waves == nil {
		return ""
	}
	switch {
	case isLongPeriod(periodS), waveFt >= p.Waves.RoughMinFt:
		return "rough"
	case waveFt <= p.Waves.CalmMaxFt:
		return "calm"
	default:
		return "neutral"
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
