// Package predict learns per-ramp tide-closure behavior from
// ramp_status_history and produces casual open/close outlooks. The county's
// decisions are inconsistent by nature, so everything here deals in risk and
// coarse windows, never precise promises.
package predict

import "time"

// SettingsKey is the settings-table key holding the learned parameters blob.
const SettingsKey = "prediction_params"

// paramsVersion identifies the blob schema. A stored blob with a different
// version is treated as stale, so bumping this forces a retrain on deploy.
// v4 added the county-wide wave regime params (Waves).
const paramsVersion = 4

// RampParams captures one ramp's learned tide-closure behavior.
type RampParams struct {
	// ThresholdFt is the predicted high-tide peak height (ft MLLW) above
	// which this ramp tends to close.
	ThresholdFt float64 `json:"threshold_ft"`
	// Accuracy is the balanced accuracy of the threshold on history.
	Accuracy float64 `json:"accuracy"`
	// NClosures is how many tide closures informed these values.
	NClosures int `json:"n_closures"`
	// CloseRate is the fraction of observed daytime tide peaks around which
	// this ramp was closed — its base tendency, independent of height.
	CloseRate float64 `json:"close_rate"`
	// LeadMin is the median minutes the ramp closes before the tide peak.
	LeadMin int `json:"lead_min"`
	// LagMin is the median minutes after the peak the ramp reopens.
	LagMin int `json:"lag_min"`
}

// Params is the full learned-parameters blob persisted to the settings table.
type Params struct {
	Version      int                   `json:"version"`
	ComputedAt   time.Time             `json:"computed_at"`
	HistoryStart string                `json:"history_start"`
	Default      RampParams            `json:"default"`
	Ramps        map[string]RampParams `json:"ramps"`

	// HardOpenFt / HardCloseFt are county-wide cutoffs learned as low/high
	// percentiles of the observed daytime peak distribution: below the
	// first, nothing closes; at or above the second, everything does. They
	// are derived from data (not constants) so they stay correct whatever
	// NOAA station — and height scale — the deployment is configured with.
	HardOpenFt  float64 `json:"hard_open_ft,omitempty"`
	HardCloseFt float64 `json:"hard_close_ft,omitempty"`

	// DayCloseOffsetMin is the learned median minutes the county's actual
	// end-of-day close lands relative to the posted close (negative = they
	// clear early, which is the observed norm — the posted turtle-season
	// 7pm has been running closer to 6:30). Learned rather than hard-coded
	// so it tracks whatever the county is actually doing this season.
	DayCloseOffsetMin int `json:"day_close_offset_min,omitempty"`

	// Waves is the county-wide wave-energy modifier: the same tide peak
	// closes ramps under a wind swell and passes quietly over a flat ocean,
	// so the current significant wave height shifts every ramp's effective
	// threshold. Nil until training has enough wave-matched peaks — and nil
	// always means "behave exactly as the tide-only model".
	Waves *WaveParams `json:"waves,omitempty"`
}

// WaveParams is the learned calm/rough wave regime split. Regime boundaries
// are quantiles of the observed wave heights at labeled daytime peaks (so
// they rescale with whatever buoy is configured); the two shifts are learned
// by the same closed-form accuracy scan the tide thresholds use.
type WaveParams struct {
	// CalmMaxFt / RoughMinFt bound the regimes: WVHT <= CalmMaxFt is calm,
	// >= RoughMinFt is rough, between is neutral (shift 0).
	CalmMaxFt  float64 `json:"calm_max_ft"`
	RoughMinFt float64 `json:"rough_min_ft"`

	// CalmRaiseFt raises the effective tide threshold on calm days (a flat
	// ocean needs more tide to close a ramp); RoughDropFt lowers it under a
	// real swell. Both are >= 0 and clamped to maxWaveShiftFt.
	CalmRaiseFt float64 `json:"calm_raise_ft"`
	RoughDropFt float64 `json:"rough_drop_ft"`

	// NSamples is how many wave-matched labeled peaks trained the split;
	// Accuracy is pooled label accuracy with the shifts applied.
	NSamples int     `json:"n_samples"`
	Accuracy float64 `json:"accuracy"`
}

// maxDayCloseOffsetMin clamps the learned offset, so a thin or weird sample
// can never drag the day's close somewhere absurd.
const maxDayCloseOffsetMin = 90

// dayCloseOffset returns the learned end-of-day offset, clamped.
func (p Params) dayCloseOffset() time.Duration {
	m := p.DayCloseOffsetMin
	if m < -maxDayCloseOffsetMin {
		m = -maxDayCloseOffsetMin
	}
	if m > maxDayCloseOffsetMin {
		m = maxDayCloseOffsetMin
	}
	return time.Duration(m) * time.Minute
}

// hardOpen/hardClose return the learned cutoffs, falling back to the
// station-8721147-scale constants from the original analysis when the blob
// predates them (or no training has run).
func (p Params) hardOpen() float64 {
	if p.HardOpenFt > 0 {
		return p.HardOpenFt
	}
	return hardOpenFt
}

func (p Params) hardClose() float64 {
	if p.HardCloseFt > 0 {
		return p.HardCloseFt
	}
	return hardCloseFt
}

// DefaultParams are the county-wide fallbacks used before any training run
// and for ramps with too few closures to learn from. Values come from the
// initial analysis of Mar–Aug 2026 history.
var DefaultParams = RampParams{
	ThresholdFt: 2.6,
	LeadMin:     105,
	LagMin:      80,
}
