package models

import "time"

// TidePrediction represents a single high or low tide prediction from NOAA.
type TidePrediction struct {
	Time time.Time `json:"time"`
	Type string    `json:"type"` // "H" for high, "L" for low
}

// WaterTemp represents a water temperature reading from a single NOAA station.
type WaterTemp struct {
	StationID   string  `json:"station_id"`
	StationName string  `json:"station_name"`
	TempF       float64 `json:"temp_f"`
}

// TideInfo is the combined tide and water temperature data for the current moment.
type TideInfo struct {
	Direction    string           `json:"tide_direction"`
	Percentage   int              `json:"tide_percentage"`
	WaterTempAvg float64          `json:"water_temp_avg"`
	WaterTemps   []WaterTemp      `json:"water_temps"`
	Predictions  []TidePrediction `json:"predictions"`
	RetrievedAt  time.Time        `json:"retrieved_at"`
}
