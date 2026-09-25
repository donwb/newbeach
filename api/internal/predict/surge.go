package predict

import (
	"math"
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// The water-level anomaly ("surge"): how far the real ocean is running above
// or below NOAA's astronomical prediction. The predicted peak height is only
// the moon's half of the story — wind setup, the fall seasonal high, and
// offshore storms stack on top of it, and the county closes ramps for the
// water that actually arrives. September 2026 was the case study: Trident
// Pier ran +0.4–0.8 ft over prediction for weeks, then +1.2–1.6 ft on 9/24–25,
// and a 2.43 ft predicted peak closed 26 of 27 ramps.
//
// There is no observing gauge in Volusia (8721164 and 8721147 are
// prediction-only), so the reading brackets the county: Trident Pier to the
// south and Mayport to the north, which correlate at 0.84. Each gauge carries
// its own datum bias (Trident runs ~+0.5 ft even on a normal day), so each is
// read as a deviation from its own learned baseline and the deviations are
// averaged over whichever gauges report.
//
// The anomaly shifts the *water*, not the bar: withSurge raises every
// predicted extreme by it, and training learns thresholds on those effective
// heights. Unlike the wave and persistence nudges this is tide evidence — the
// water is physically higher — so it may promote to "likely" and cross the
// hard cutoffs. Evidence (Mar–Sep 2026, 27 ramps, logistic fit on Mar–Aug and
// scored on September): adding the anomaly on top of the wave regimes took
// held-out log-loss 0.540 → 0.432, accuracy 75% → 79%, and it weighs ~1.1–1.3×
// a foot of predicted tide — so plain "predicted + anomaly" is the physical
// model, not a tuned gain.
const (
	// surgeWindow is the trailing span averaged into one reading — long
	// enough to wash out tidal-phase error in the predictions, short enough
	// to catch a nor'easter building.
	surgeWindow = 12 * time.Hour

	// minSurgeSamples is how many hourly residuals a gauge needs inside the
	// window to count.
	minSurgeSamples = 6

	// maxSurgeAge is the serve-time staleness cutoff: when a gauge's newest
	// sample is older than this it sits the reading out, and with no fresh
	// gauge the outlook assumes normal water (predicted tide only).
	maxSurgeAge = 3 * time.Hour

	// maxSurgeFt clamps the adjustment. 9/25's +1.6 ft is the largest
	// deviation in the record; anything past that is a sensor fault.
	maxSurgeFt = 1.5

	// minSurgeBaselineSamples is the hourly sample floor for learning a
	// gauge's baseline — two weeks, so one storm can't define "normal".
	minSurgeBaselineSamples = 14 * 24

	// surgeDailyCarry is the fraction of today's anomaly carried to each
	// later calendar day. Measured autocorrelation of the 12h reading:
	// 0.8 at 24h, 0.5 at 48h, 0.35 at 72h (Trident; Mayport decays faster).
	surgeDailyCarry = 0.75

	// surgeDownFactor discounts below-normal water. High water is strong
	// evidence; low water is weak — the county kept closing ramps on
	// August days with the gauges 0.2–0.6 ft under normal, and a forecast
	// must never promise openness it can't back. Walk-forward, 27 ramps,
	// May–Sep 2026 (misses / likely precision / grade score): symmetric
	// 35 / 0.752 / 0.895, half 28 / 0.764 / 0.893, up-only 25 / 0.746 /
	// 0.890, surge off 114 / 0.631 / 0.862. Half keeps nearly all of the
	// symmetric model's precision for most of up-only's recall.
	surgeDownFactor = 0.5
)

// SurgeParams is the learned water-level baseline per gauge. Nil means the
// anomaly is ignored everywhere — the predicted-tide engine exactly.
type SurgeParams struct {
	// BaselineFt is each gauge's median observed-minus-predicted residual
	// over the training span: its "normal" water.
	BaselineFt map[string]float64 `json:"baseline_ft"`
	// NSamples is how many hourly residuals set the baselines.
	NSamples int `json:"n_samples"`
}

// SurgeContext is the outlook's echo of the anomaly it applied, so an
// operator (and eventually the copy) can see the water the model saw.
type SurgeContext struct {
	AnomalyFt  float64   `json:"anomaly_ft"`
	ObservedAt time.Time `json:"observed_at"`
	Stations   []string  `json:"stations"`
}

// levelSeries is the anomaly input grouped per gauge, ascending by time.
type levelSeries map[string][]models.WaterLevelSample

func newLevelSeries(levels []models.WaterLevelSample) levelSeries {
	if len(levels) == 0 {
		return nil
	}
	s := make(levelSeries)
	for _, l := range levels {
		s[l.Station] = append(s[l.Station], l)
	}
	for _, samples := range s {
		sort.Slice(samples, func(i, j int) bool { return samples[i].Time.Before(samples[j].Time) })
	}
	return s
}

// trainSurgeParams learns each gauge's baseline from the samples before now.
// Gauges under the sample floor are left out; none left → nil.
func trainSurgeParams(series levelSeries, now time.Time) *SurgeParams {
	sp := &SurgeParams{BaselineFt: map[string]float64{}}
	for station, samples := range series {
		var vals []float64
		for _, s := range samples {
			if s.Time.Before(now) {
				vals = append(vals, s.ResidualFt)
			}
		}
		if len(vals) < minSurgeBaselineSamples {
			continue
		}
		sp.BaselineFt[station] = math.Round(median(vals)*1000) / 1000
		sp.NSamples += len(vals)
	}
	if len(sp.BaselineFt) == 0 {
		return nil
	}
	return sp
}

// anomalyAt is the county reading at t: each baselined gauge's trailing
// surgeWindow mean minus its baseline, averaged over the gauges with enough
// samples. fresh additionally requires each gauge's newest sample to be
// within maxSurgeAge of t (serve time); training and grading replay history
// and skip that check. ok is false when no gauge qualifies. newest is the
// latest sample time among the contributing gauges.
func (p Params) anomalyAt(series levelSeries, t time.Time, fresh bool) (ft float64, newest time.Time, stations []string, ok bool) {
	if p.Surge == nil || len(series) == 0 {
		return 0, time.Time{}, nil, false
	}
	var sum float64
	for station, base := range p.Surge.BaselineFt {
		samples := series[station]
		hi := sort.Search(len(samples), func(i int) bool { return samples[i].Time.After(t) })
		lo := sort.Search(len(samples), func(i int) bool { return samples[i].Time.After(t.Add(-surgeWindow)) })
		if hi-lo < minSurgeSamples {
			continue
		}
		last := samples[hi-1].Time
		if fresh && t.Sub(last) > maxSurgeAge {
			continue
		}
		var m float64
		for _, s := range samples[lo:hi] {
			m += s.ResidualFt
		}
		sum += m/float64(hi-lo) - base
		stations = append(stations, station)
		if last.After(newest) {
			newest = last
		}
	}
	if len(stations) == 0 {
		return 0, time.Time{}, nil, false
	}
	sort.Strings(stations)
	ft = sum / float64(len(stations))
	if ft < 0 {
		ft *= surgeDownFactor
	}
	ft = math.Max(-maxSurgeFt, math.Min(maxSurgeFt, ft))
	return math.Round(ft*1000) / 1000, newest, stations, true
}

// withSurge returns preds with every extreme raised by the water-level
// anomaly — the water the county will actually see. Extremes at or before
// now use the anomaly observed then (history is known); later ones use the
// reading at now, decayed by surgeDailyCarry per calendar day ahead. An
// extreme with no reading keeps its predicted height. Heights move, times
// don't. Nil Surge, no series, or no reading anywhere returns preds itself,
// so the engine reproduces the predicted-tide model exactly. The reading at
// now is also returned for the payload echo (nil when stale or absent).
func (p Params) withSurge(preds []models.TidePrediction, levels []models.WaterLevelSample, now time.Time) ([]models.TidePrediction, *SurgeContext) {
	series := newLevelSeries(levels)
	if p.Surge == nil || series == nil {
		return preds, nil
	}

	var nowCtx *SurgeContext
	nowFt, observedAt, stations, nowOK := p.anomalyAt(series, now, true)
	if nowOK {
		nowCtx = &SurgeContext{AnomalyFt: nowFt, ObservedAt: observedAt, Stations: stations}
	}

	today := now.In(eastern)
	todayStart := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, eastern)

	out := make([]models.TidePrediction, len(preds))
	copy(out, preds)
	changed := false
	for i, pr := range out {
		if pr.Height == nil {
			continue
		}
		var adj float64
		if !pr.Time.After(now) {
			ft, _, _, ok := p.anomalyAt(series, pr.Time, false)
			if !ok {
				continue
			}
			adj = ft
		} else {
			if !nowOK {
				continue
			}
			et := pr.Time.In(eastern)
			daysOut := int(math.Round(time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern).Sub(todayStart).Hours() / 24))
			adj = nowFt * math.Pow(surgeDailyCarry, float64(daysOut))
		}
		h := math.Round((*pr.Height+adj)*1000) / 1000
		out[i].Height = &h
		changed = true
	}
	if !changed {
		return preds, nowCtx
	}
	return out, nowCtx
}
