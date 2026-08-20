package models

import (
	"strings"
	"time"
	"unicode"
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

// RampStatusWithSince pairs a ramp's current status with the time that status
// took effect, taken from the most recent history entry. StatusSince is nil
// when the ramp has no recorded status changes.
//
// The metadata fields come from an optional LEFT JOIN against ramp_metadata
// and are all pointers with omitempty: ramps without metadata serialize
// exactly as they did before the ramp_metadata table existed, so existing
// consumers (web, TRMNL, tvOS, iOS) see identical JSON until a field is set.
type RampStatusWithSince struct {
	RampStatus
	StatusSince     *time.Time `json:"status_since,omitempty"`
	ShortName       *string    `json:"short_name,omitempty"`
	Address         *string    `json:"address,omitempty"`
	DrivingHours    *string    `json:"driving_hours,omitempty"`
	ClosureHeightFt *float64   `json:"closure_height_ft,omitempty"`
	SortOrder       *int       `json:"sort_order,omitempty"`
}

// RampMetadata is the operator-curated enrichment for a single ramp, keyed by
// the county GIS access_id. Every field except AccessID is nullable; a nil
// pointer serializes to an absent key and stores SQL NULL. The admin upsert
// treats the body as a full replacement, so an absent or null field clears
// the stored value.
type RampMetadata struct {
	AccessID        string   `json:"access_id" db:"access_id"`
	ShortName       *string  `json:"short_name,omitempty" db:"short_name"`
	Address         *string  `json:"address,omitempty" db:"address"`
	DrivingHours    *string  `json:"driving_hours,omitempty" db:"driving_hours"`
	ClosureHeightFt *float64 `json:"closure_height_ft,omitempty" db:"closure_height_ft"`
	SortOrder       *int     `json:"sort_order,omitempty" db:"sort_order"`
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

// StatusEvent is a bare status change: what the status became and when.
// Used as the input to interval derivation.
type StatusEvent struct {
	AccessStatus string    `json:"access_status"`
	RecordedAt   time.Time `json:"recorded_at"`
}

// RampStatusInterval is a span of time during which a ramp held one status.
// Intervals are derived from ramp_status_history change events.
type RampStatusInterval struct {
	Status   string    `json:"status"`
	Category string    `json:"category"`
	Start    time.Time `json:"start"`
	End      time.Time `json:"end"`
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

// PrettyCityName converts a GIS city like "NEW SMYRNA BEACH" or
// "WILBUR-BY-THE-SEA" to display casing ("New Smyrna Beach",
// "Wilbur-by-the-Sea"). Connector words stay lowercase except when leading.
func PrettyCityName(name string) string {
	small := map[string]bool{"by": true, "the": true, "of": true, "at": true}
	capitalize := func(s string, lead bool) string {
		if s == "" {
			return s
		}
		if !lead && small[s] {
			return s
		}
		return strings.ToUpper(s[:1]) + s[1:]
	}
	words := strings.Fields(strings.ToLower(strings.TrimSpace(name)))
	for i, w := range words {
		parts := strings.Split(w, "-")
		for j, p := range parts {
			parts[j] = capitalize(p, i == 0 && j == 0)
		}
		words[i] = strings.Join(parts, "-")
	}
	return strings.Join(words, " ")
}

// PrettyRampName converts a GIS ramp name like "3RD AV" or "CRAWFORD RD" to a
// display name like "3rd Ave" or "Crawford Rd".
func PrettyRampName(name string) string {
	words := strings.Fields(name)
	for i, w := range words {
		switch w {
		case "AV", "AVE":
			words[i] = "Ave"
		case "RD":
			words[i] = "Rd"
		case "ST":
			words[i] = "St"
		case "BLVD":
			words[i] = "Blvd"
		case "DR":
			words[i] = "Dr"
		case "LN":
			words[i] = "Ln"
		case "CT":
			words[i] = "Ct"
		default:
			if len(w) > 0 && unicode.IsDigit(rune(w[0])) {
				// Ordinals: "3RD" → "3rd", "27TH" → "27th".
				words[i] = strings.ToLower(w)
			} else {
				words[i] = strings.ToUpper(w[:1]) + strings.ToLower(w[1:])
			}
		}
	}
	return strings.Join(words, " ")
}
