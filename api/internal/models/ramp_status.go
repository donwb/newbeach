package models

import (
	"strings"
	"time"
)

// RampStatus represents the current status of a beach access ramp.
// This is the primary domain model shared across the API and ingester.
type RampStatus struct {
	ID             int64     `json:"id" db:"id"`
	RampName       string    `json:"ramp_name" db:"ramp_name"`
	AccessStatus   string    `json:"access_status" db:"access_status"`
	StatusCategory string    `json:"status_category" db:"status_category"`
	ObjectID       int64     `json:"object_id" db:"object_id"`
	City           string    `json:"city" db:"city"`
	AccessID       string    `json:"access_id" db:"access_id"`
	Location       string    `json:"location" db:"location"`
	UpdatedAt      time.Time `json:"last_updated" db:"updated_at"`
}

// RampStatusHistory represents a single historical record of a ramp status change.
type RampStatusHistory struct {
	ID           int64     `json:"id" db:"id"`
	AccessID     string    `json:"access_id" db:"access_id"`
	AccessStatus string    `json:"access_status" db:"access_status"`
	RecordedAt   time.Time `json:"recorded_at" db:"recorded_at"`
}

// RampHistoryEntry represents a historical ramp status change, optionally
// enriched with ramp name and city from the current ramp_status table.
type RampHistoryEntry struct {
	ID           int64     `json:"id"`
	AccessID     string    `json:"access_id"`
	AccessStatus string    `json:"access_status"`
	RecordedAt   time.Time `json:"recorded_at"`
	RampName     string    `json:"ramp_name,omitempty"`
	City         string    `json:"city,omitempty"`
}

// StatusToCategory maps a raw access status string to a category:
// "open", "limited", or "closed".
func StatusToCategory(status string) string {
	switch strings.ToUpper(strings.TrimSpace(status)) {
	case "OPEN":
		return "open"
	case "4X4 ONLY", "CLOSING IN PROGRESS", "OPEN - ENTRANCE ONLY":
		return "limited"
	default:
		return "closed"
	}
}

// StatusToShort returns an abbreviated status string (12 characters or fewer)
// suitable for space-constrained IoT displays.
func StatusToShort(status string) string {
	switch strings.ToUpper(strings.TrimSpace(status)) {
	case "OPEN":
		return "OPEN"
	case "CLOSED":
		return "CLOSED"
	case "4X4 ONLY":
		return "4X4 ONLY"
	case "CLOSED FOR HIGH TIDE":
		return "CLOSED-TIDE"
	case "CLOSED - AT CAPACITY":
		return "CLOSED-FULL"
	case "CLOSED - CLEARED FOR TURTLES":
		return "CLOSED-TRTL"
	case "CLOSING IN PROGRESS":
		return "CLOSING"
	case "OPEN - ENTRANCE ONLY":
		return "ENTER ONLY"
	default:
		// For any unknown status, truncate to 12 characters.
		s := strings.ToUpper(strings.TrimSpace(status))
		if len(s) > 12 {
			return s[:12]
		}
		return s
	}
}
