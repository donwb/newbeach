package models

import "time"

// WidgetPushToken is one device's WidgetKit push token (iOS 26), registered
// by the widget extension so the server can tell WidgetKit to reload the
// widget the moment a ramp's status changes.
type WidgetPushToken struct {
	Token        string     `json:"token"`       // hex
	Environment  string     `json:"environment"` // "production" | "sandbox"
	BundleID     string     `json:"bundle_id"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	LastPushedAt *time.Time `json:"last_pushed_at,omitempty"`
}
