// Package nwsfc fetches NWS gridpoint forecasts (api.weather.gov) and exposes
// them as expanded, unit-converted samples. It exists separately from the
// presentation-oriented weather package: this package speaks raw gridpoint
// series (the quantitative land forecast and the marine wave forecast), and no
// NWS wire shapes leak out of it — consumers see Fahrenheit, mph, and feet.
package nwsfc

import "time"

// HourlySample is one hour of land forecast, already unit-converted for
// display (F, mph). Pointer fields: the NWS series are sparse and cover
// different horizons — nil means no value covered that hour.
type HourlySample struct {
	Time         time.Time
	TempF        *float64
	HeatIndexF   *float64
	PoPPct       *float64
	ThunderPct   *float64
	WindMph      *float64
	GustMph      *float64
	SkyCoverPct  *float64
	HeatRisk     *int
	HeatAdvisory bool // an NWS heat hazard (phenomenon "HT"/"EH") covers this hour
}

// LandForecast is the expanded hourly land-gridpoint forecast.
type LandForecast struct {
	FetchedAt time.Time
	Hours     []HourlySample
}

// WaveBlock is one valid-time block from the marine gridpoint. Marine series
// come in coarse multi-hour (sometimes multi-day) blocks, so they are kept as
// blocks rather than expanded per hour. A block carries height or period,
// whichever series it came from — query them independently.
type WaveBlock struct {
	Start    time.Time
	End      time.Time
	HeightFt *float64
	PeriodS  *float64
}

// MarineForecast is the marine-gridpoint wave forecast.
type MarineForecast struct {
	FetchedAt time.Time
	Blocks    []WaveBlock
}

// MaxHeightFtBetween returns the maximum forecast wave height overlapping
// [start, end), or nil if no height block overlaps.
func (m *MarineForecast) MaxHeightFtBetween(start, end time.Time) *float64 {
	var max *float64
	for _, b := range m.Blocks {
		if b.HeightFt == nil || !b.Start.Before(end) || !b.End.After(start) {
			continue
		}
		if max == nil || *b.HeightFt > *max {
			v := *b.HeightFt
			max = &v
		}
	}
	return max
}

// --- Unit conversion helpers ---
//
// Deliberately duplicated from the weather package (three one-liners) rather
// than exporting them across packages.

func celsiusToFahrenheit(c float64) float64 { return c*9.0/5.0 + 32.0 }

func kmhToMph(kmh float64) float64 { return kmh * 0.621371 }

func metersToFeet(m float64) float64 { return m * 3.28084 }
