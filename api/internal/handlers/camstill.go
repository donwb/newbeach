package handlers

import (
	"net/url"
	"regexp"
	"strings"
)

// defaultCamStillTemplate is YouTube's live thumbnail: a 1280×720 frame of the
// broadcast that YouTube refreshes every ~4–6 minutes while the stream is live
// (measured 2026-11-23). It is served to any IP — unlike the googlevideo media
// segments, which YouTube IP-locks and, since 2026-11-20, refuses to the home
// restreamer — so clients fall back to it whenever a cam's relay stream is dark.
// The relay's 1280×270 panorama sits letterboxed inside it at rows 225–494.
const defaultCamStillTemplate = "https://i.ytimg.com/vi/{id}/maxresdefault_live.jpg"

// camStillDisabled turns the still fallback off when CAM_STILL_URL_TEMPLATE is
// set to it.
const camStillDisabled = "off"

var youTubeVideoID = regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)

// camStillURL derives a camera's still-frame URL from its YouTube live URL by
// substituting the video ID into tmpl ("{id}" placeholder; empty = default,
// "off" = disabled). Returns "" when the URL carries no recognizable video ID
// — a still is a nice-to-have, never a reason to fail the roster.
func camStillURL(youTubeURL, tmpl string) string {
	if tmpl == camStillDisabled {
		return ""
	}
	if tmpl == "" {
		tmpl = defaultCamStillTemplate
	}
	id := youTubeID(youTubeURL)
	if id == "" {
		return ""
	}
	return strings.ReplaceAll(tmpl, "{id}", id)
}

// youTubeID extracts the 11-character video ID from the URL shapes the roster
// uses or might: watch?v=, youtu.be/<id>, /live/<id>, /embed/<id>.
func youTubeID(raw string) string {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.Host == "" {
		return ""
	}
	host := strings.TrimPrefix(strings.ToLower(u.Host), "www.")
	host = strings.TrimPrefix(host, "m.")

	var id string
	switch host {
	case "youtube.com":
		if v := u.Query().Get("v"); v != "" {
			id = v
			break
		}
		parts := strings.Split(strings.Trim(u.Path, "/"), "/")
		if len(parts) == 2 && (parts[0] == "live" || parts[0] == "embed") {
			id = parts[1]
		}
	case "youtu.be":
		id = strings.Trim(u.Path, "/")
	}
	if !youTubeVideoID.MatchString(id) {
		return ""
	}
	return id
}
