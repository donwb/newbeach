// Package predict learns per-ramp tide-closure behavior from
// ramp_status_history and produces casual open/close outlooks. The county's
// decisions are inconsistent by nature, so everything here deals in risk and
// coarse windows, never precise promises.
package predict

import "time"

// SettingsKey is the settings-table key holding the learned parameters blob.
const SettingsKey = "prediction_params"

// paramsVersion identifies the blob schema for forward compatibility.
const paramsVersion = 1

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
}

// DefaultParams are the county-wide fallbacks used before any training run
// and for ramps with too few closures to learn from. Values come from the
// initial analysis of Mar–Aug 2026 history.
var DefaultParams = RampParams{
	ThresholdFt: 2.6,
	LeadMin:     105,
	LagMin:      80,
}
