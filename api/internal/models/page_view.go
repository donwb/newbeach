package models

import "time"

// PageView is one logged HTML page navigation (never an API call or asset
// fetch). First-party visibility into who is reading the site — e.g. whether
// county staff open /county/ after outreach.
type PageView struct {
	ViewedAt  time.Time `json:"viewed_at"`
	Path      string    `json:"path"`
	IP        string    `json:"ip"`
	UserAgent string    `json:"user_agent"`
	Referer   string    `json:"referer"`
}

// PageViewIPSummary aggregates page views by visitor IP over a query window.
type PageViewIPSummary struct {
	IP        string    `json:"ip"`
	Views     int       `json:"views"`
	FirstSeen time.Time `json:"first_seen"`
	LastSeen  time.Time `json:"last_seen"`
	Paths     []string  `json:"paths"`
	UserAgent string    `json:"user_agent"`
}
