package models

import "time"

// BeachConditions is one periodic snapshot of environmental conditions and
// county-wide ramp state, persisted to the beach_conditions table. All
// condition fields are pointers: a nil means the upstream source was
// unavailable at snapshot time, and the row is written anyway.
// WaveSample is one buoy wave observation — the unit shared by the NDBC
// fetchers, the wave_observations table, the trainer, and the predict engine.
// It lives in models so predict never has to import conditions.
type WaveSample struct {
	Time            time.Time `json:"t"`
	HeightFt        float64   `json:"wvht_ft"`
	DominantPeriodS *float64  `json:"dpd_s,omitempty"`
}

type BeachConditions struct {
	ID               int64      `json:"id"`
	RecordedAt       time.Time  `json:"recorded_at"`
	TidePredictedFt  *float64   `json:"tide_predicted_ft,omitempty"`
	NextPeakFt       *float64   `json:"next_peak_ft,omitempty"`
	NextPeakAt       *time.Time `json:"next_peak_at,omitempty"`
	WindSpeedMph     *float64   `json:"wind_speed_mph,omitempty"`
	WindGustMph      *float64   `json:"wind_gust_mph,omitempty"`
	WindDir          *string    `json:"wind_dir,omitempty"`
	WaveHeightFt     *float64   `json:"wave_height_ft,omitempty"`
	DominantPeriodS  *float64   `json:"dominant_period_s,omitempty"`
	RampsOpen        *int       `json:"ramps_open,omitempty"`
	RampsClosedTide  *int       `json:"ramps_closed_tide,omitempty"`
	RampsClosedOther *int       `json:"ramps_closed_other,omitempty"`
}
