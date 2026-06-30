package models

import "time"

// Camera is a single live beach webcam in the roster. The YouTube live URL is
// stable; HLSURL is the rotating stream URL re-resolved periodically by the
// home yt-dlp cron (residential IP, to avoid datacenter filtering) and pushed
// back via the admin API.
type Camera struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Location   string    `json:"location"`
	YouTubeURL string    `json:"youtube_url"`
	HLSURL     string    `json:"hls_url"`
	SortOrder  int       `json:"sort_order"`
	UpdatedAt  time.Time `json:"updated_at"`
}
