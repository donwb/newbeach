package models

// V1RampStatus matches the exact /rampstatus JSON contract consumed by the
// Tidbyt device. Field names MUST remain camelCase — do not change them.
type V1RampStatus struct {
	ID           int64  `json:"id"`
	RampName     string `json:"rampName"`
	AccessStatus string `json:"accessStatus"`
	ObjectID     int64  `json:"objectID"`
	City         string `json:"city"`
	AccessID     string `json:"accessID"`
	Location     string `json:"location"`
}

// ToV1 converts a RampStatus domain model to the v1 API response shape.
func (r *RampStatus) ToV1() V1RampStatus {
	return V1RampStatus{
		ID:           r.ID,
		RampName:     r.RampName,
		AccessStatus: r.AccessStatus,
		ObjectID:     r.ObjectID,
		City:         r.City,
		AccessID:     r.AccessID,
		Location:     r.Location,
	}
}

// V1TideResponse matches the exact /tides JSON contract consumed by the
// Tidbyt device. Field names MUST remain camelCase — do not change them.
type V1TideResponse struct {
	CurrentTideHighOrLow string        `json:"currentTideHighOrLow"`
	TideLevelPercentage  int           `json:"tideLevelPercentage"`
	WaterTemp            int           `json:"waterTemp"`
	TideInfo             []V1TideInfo  `json:"tideInfo"`
	WaterTemps           []V1WaterTemp `json:"waterTemps"`
}

// V1TideInfo represents a single tide prediction in the v1 format.
type V1TideInfo struct {
	TideDateTime string `json:"tideDateTime"`
	HighOrLow    string `json:"highOrLow"`
}

// V1WaterTemp represents a single station's water temperature in the v1 format.
type V1WaterTemp struct {
	StationID   string `json:"stationID"`
	StationName string `json:"stationName"`
	WaterTemp   int    `json:"waterTemp"`
}
