package handlers

import (
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/camhealth"
	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/ingester"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/videostream"
	"github.com/donwb/beach/api/internal/weather"
)

// HandleV2Ramps returns ramp statuses with optional city and status query filters.
// Each ramp carries status_since, the time its current status took effect.
// GET /api/v2/ramps?city=New+Smyrna+Beach&status=open
func HandleV2Ramps(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		city := c.QueryParam("city")
		status := c.QueryParam("status")

		ramps, err := database.GetRampsWithStatusSince(ctx, pool, city, status)
		if err != nil {
			slog.Error("querying v2 ramps", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query ramps",
			})
		}
		if ramps == nil {
			ramps = make([]models.RampStatusWithSince, 0)
		}

		return c.JSON(http.StatusOK, ramps)
	}
}

// HandleV2RampByID returns a single ramp by its database ID, including any
// operator-curated metadata (nullable fields, omitted from the JSON when
// unset — the response is unchanged for ramps without metadata).
// GET /api/v2/ramps/:id
func HandleV2RampByID(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		idStr := c.Param("id")
		id, err := strconv.ParseInt(idStr, 10, 64)
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "invalid ramp id",
			})
		}

		var r models.RampStatusWithSince
		err = pool.QueryRow(ctx,
			`SELECT r.id, r.ramp_name, r.access_status, r.status_category, r.object_id, r.city, r.access_id, r.location, r.updated_at,
			        m.short_name, m.address, m.driving_hours, m.closure_height_ft, m.sort_order
			 FROM ramp_status r
			 LEFT JOIN ramp_metadata m ON m.access_id = r.access_id
			 WHERE r.id = $1`, id).
			Scan(&r.ID, &r.RampName, &r.AccessStatus, &r.StatusCategory,
				&r.ObjectID, &r.City, &r.AccessID, &r.Location, &r.UpdatedAt,
				&r.ShortName, &r.Address, &r.DrivingHours, &r.ClosureHeightFt, &r.SortOrder)

		if err != nil {
			slog.Error("querying ramp by id", "id", id, "err", err)
			return c.JSON(http.StatusNotFound, map[string]string{
				"error": "ramp not found",
			})
		}

		return c.JSON(http.StatusOK, r)
	}
}

// HandleV2Tides returns enhanced tide data in the v2 snake_case format.
// GET /api/v2/tides
func HandleV2Tides(noaaClient *noaa.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		info, err := noaaClient.GetTideInfo(ctx)
		if err != nil {
			slog.Error("fetching v2 tide info", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch tide information",
			})
		}

		return c.JSON(http.StatusOK, info)
	}
}

// HandleV2TideChart returns granular tide data suitable for rendering a smooth
// tide chart. It includes the hourly prediction curve, high/low markers, and the
// current server time for plotting a "now" indicator.
// GET /api/v2/tides/chart
func HandleV2TideChart(noaaClient *noaa.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		hourly, err := noaaClient.FetchHourlyPredictions(ctx)
		if err != nil {
			slog.Error("fetching hourly predictions for tide chart", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch hourly tide predictions",
			})
		}

		highLow, err := noaaClient.FetchTidePredictions(ctx)
		if err != nil {
			slog.Error("fetching high/low predictions for tide chart", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch high/low tide predictions",
			})
		}

		return c.JSON(http.StatusOK, map[string]interface{}{
			"hourly":       hourly,
			"high_low":     highLow,
			"current_time": time.Now(),
		})
	}
}

// HandleV2Health returns the service health status including database
// connectivity and ingestion health.
// GET /api/v2/health
//
// Ingestion problems mark the overall status "degraded" but keep HTTP 200:
// this endpoint is the DigitalOcean container health check, and restarting
// the container cannot fix a GIS-side ingestion failure — a 503 here would
// only cause restart loops and block deploys while the API itself is fine.
// Only a database outage returns 503.
func HandleV2Health(pool *pgxpool.Pool, ing *ingester.Ingester) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		dbStatus := "connected"
		if err := pool.Ping(ctx); err != nil {
			slog.Error("health check database ping failed", "err", err)
			dbStatus = "disconnected"
		}

		ingHealth := ing.Health()
		ingStatus := ingHealth.Status(time.Now())

		status := "ok"
		httpStatus := http.StatusOK
		if ingStatus == "degraded" {
			status = "degraded"
		}
		if dbStatus != "connected" {
			status = "degraded"
			httpStatus = http.StatusServiceUnavailable
		}

		return c.JSON(httpStatus, map[string]interface{}{
			"status":   status,
			"database": dbStatus,
			"ingester": map[string]interface{}{
				"status":             ingStatus,
				"last_poll_at":       ingHealth.LastPollAt,
				"last_clean_poll_at": ingHealth.LastCleanPollAt,
				"queries_failed":     ingHealth.QueriesFailed,
				"features_failed":    ingHealth.FeaturesFailed,
			},
		})
	}
}

// HandleV2Config returns client configuration from environment variables
// merged with database settings.
// GET /api/v2/config
func HandleV2Config(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		// Source the legacy video_stream_url from the default camera (lowest
		// sort_order). Fall back to the settings key if the roster is empty,
		// so the field is never blank during a transition.
		videoStreamURL, _ := database.GetDefaultCameraHLS(ctx, pool)
		if videoStreamURL == "" {
			videoStreamURL, _ = database.GetSetting(ctx, pool, "video_stream_url")
		}

		return c.JSON(http.StatusOK, map[string]interface{}{
			"webcam_url":       os.Getenv("WEBCAM_URL"),
			"tide_station":     os.Getenv("NOAA_TIDE_STATION"),
			"temp_stations":    os.Getenv("NOAA_TEMP_STATIONS"),
			"water_temp_avg":   true,
			"default_city":     "New Smyrna Beach",
			"video_stream_url": videoStreamURL,
		})
	}
}

// cameraDTO is the public camera roster wire shape. Online and
// StatusChangedAt are pointers so cameras with no observed health omit the
// fields entirely — existing clients decode the pre-health JSON unchanged.
type cameraDTO struct {
	ID              string     `json:"id"`
	Name            string     `json:"name"`
	Location        string     `json:"location"`
	StreamURL       string     `json:"stream_url"`
	Online          *bool      `json:"online,omitempty"`
	StatusChangedAt *time.Time `json:"status_changed_at,omitempty"`
}

// HandleV2Cameras returns the public camera roster for clients (tvOS cam
// switcher). Exposes only what a player needs — the rotating HLS stream URL
// per camera, ordered south-to-north — plus the default camera id. Cameras
// with observed relay health additionally carry online/status_changed_at
// (strictly additive; cameras never observed omit both fields).
// GET /api/v2/cameras
func HandleV2Cameras(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		cameras, err := database.ListCameras(ctx, pool)
		if err != nil {
			slog.Error("failed to list cameras", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list cameras"})
		}

		// Health is best-effort decoration: a failed read serves the roster
		// without it rather than taking the cam switcher down with it.
		health, err := camhealth.GetAll(ctx, pool)
		if err != nil {
			slog.Warn("failed to read camera health for roster", "err", err)
			health = nil
		}

		out := make([]cameraDTO, 0, len(cameras))
		for _, cam := range cameras {
			dto := cameraDTO{
				ID:        cam.ID,
				Name:      cam.Name,
				Location:  cam.Location,
				StreamURL: cam.HLSURL,
			}
			if h, ok := health[cam.ID]; ok {
				online := h.Online
				changedAt := h.ChangedAt
				dto.Online = &online
				dto.StatusChangedAt = &changedAt
			}
			out = append(out, dto)
		}

		defaultID := ""
		if len(cameras) > 0 {
			defaultID = cameras[0].ID
		}

		return c.JSON(http.StatusOK, map[string]interface{}{
			"cameras":    out,
			"default_id": defaultID,
		})
	}
}

// HandleAdminGetSettings returns all settings from the database.
// GET /api/v2/admin/settings
func HandleAdminGetSettings(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()
		settings, err := database.GetAllSettings(ctx, pool)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to read settings"})
		}
		return c.JSON(http.StatusOK, settings)
	}
}

// HandleAdminUpdateSetting upserts a single setting.
// POST /api/v2/admin/settings
// Body: {"key": "video_stream_url", "value": "https://..."}
func HandleAdminUpdateSetting(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		var body struct {
			Key   string `json:"key"`
			Value string `json:"value"`
		}
		if err := c.Bind(&body); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		}
		if body.Key == "" {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "key is required"})
		}

		if err := database.UpsertSetting(ctx, pool, body.Key, body.Value); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update setting"})
		}

		// Transition bridge: the legacy video_stream_url push (old cron script)
		// also mirrors into the default camera's hls_url, which is what
		// /api/v2/config now reads. This keeps the default cam fresh until the
		// cron is switched to POST /admin/cameras/:id/stream. Best-effort.
		if body.Key == "video_stream_url" && body.Value != "" {
			if err := database.UpdateDefaultCameraHLS(ctx, pool, body.Value); err != nil {
				slog.Warn("failed to mirror video_stream_url to default camera", "err", err)
			}
		}

		return c.JSON(http.StatusOK, map[string]string{"status": "ok", "key": body.Key, "value": body.Value})
	}
}

// HandleAdminGetCameras returns the full camera roster (including youtube_url
// and the last-resolved hls_url) for the home yt-dlp cron to iterate.
// GET /api/v2/admin/cameras
func HandleAdminGetCameras(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()
		cameras, err := database.ListCameras(ctx, pool)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list cameras"})
		}
		return c.JSON(http.StatusOK, map[string]interface{}{"cameras": cameras})
	}
}

// HandleAdminUpdateCameraStream sets the resolved HLS URL for one camera.
// Called by the home cron after it resolves each YouTube live URL locally.
// POST /api/v2/admin/cameras/:id/stream
// Body: {"hls_url": "https://..."}
func HandleAdminUpdateCameraStream(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		id := c.Param("id")
		if id == "" {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "camera id is required"})
		}

		var body struct {
			HLSURL string `json:"hls_url"`
		}
		if err := c.Bind(&body); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		}
		if body.HLSURL == "" {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "hls_url is required"})
		}

		if err := database.UpdateCameraHLS(ctx, pool, id, body.HLSURL); err != nil {
			if err == pgx.ErrNoRows {
				return c.JSON(http.StatusNotFound, map[string]string{"error": "unknown camera id"})
			}
			slog.Error("failed to update camera stream", "id", id, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update camera stream"})
		}

		return c.JSON(http.StatusOK, map[string]string{"status": "ok", "id": id})
	}
}

// HandleAdminUpsertRampMetadata inserts or fully replaces the curated
// metadata for one ramp, keyed by access_id. All body fields are optional
// and nullable; the row is replaced wholesale, so an absent or null field
// clears the stored value. Returns the stored row.
// PUT /api/v2/admin/ramps/:id/metadata
// Body: {"short_name": "Beachway", "address": "...", "driving_hours": "...",
//
//	"closure_height_ft": 2.5, "sort_order": 1}
func HandleAdminUpsertRampMetadata(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		accessID := c.Param("id")
		if accessID == "" {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "ramp access_id is required"})
		}

		var body models.RampMetadata
		if err := c.Bind(&body); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		}
		// The path is authoritative for the key; ignore any access_id in the body.
		body.AccessID = accessID

		stored, err := database.UpsertRampMetadata(ctx, pool, body)
		if err != nil {
			slog.Error("failed to upsert ramp metadata", "access_id", accessID, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to upsert ramp metadata"})
		}

		return c.JSON(http.StatusOK, stored)
	}
}

// HandleV2VideoRefresh resolves the current HLS URL from YouTube and persists
// it to settings. Called by clients (tvOS) when their player encounters a
// playback error, indicating the cached URL has rotated. Concurrent calls and
// rapid retries are coalesced/cooldown-throttled inside the Refresher.
// POST /api/v2/video/refresh
func HandleV2VideoRefresh(refresher *videostream.Refresher) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		result, err := refresher.Refresh(ctx)
		if err != nil {
			slog.Error("video stream refresh failed", "err", err)
			return c.JSON(http.StatusBadGateway, map[string]string{
				"error": "failed to refresh video stream URL",
			})
		}

		return c.JSON(http.StatusOK, map[string]interface{}{
			"video_stream_url": result.URL,
			"cached":           result.Cached,
		})
	}
}

// HandleV2RampHistory returns historical status changes for a specific ramp.
// GET /api/v2/ramps/:id/history?limit=100
func HandleV2RampHistory(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		idStr := c.Param("id")
		id, err := strconv.ParseInt(idStr, 10, 64)
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "invalid ramp id",
			})
		}

		// Look up the ramp to get its access_id.
		ramp, err := database.GetRampByID(ctx, pool, id)
		if err != nil {
			slog.Error("fetching ramp for history", "id", id, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch ramp",
			})
		}
		if ramp == nil {
			return c.JSON(http.StatusNotFound, map[string]string{
				"error": "ramp not found",
			})
		}

		// Parse optional limit parameter (default 100).
		limit := 100
		if limitStr := c.QueryParam("limit"); limitStr != "" {
			parsed, err := strconv.Atoi(limitStr)
			if err == nil && parsed > 0 {
				limit = parsed
			}
		}

		entries, err := database.GetRampHistory(ctx, pool, ramp.AccessID, limit)
		if err != nil {
			slog.Error("querying ramp history", "access_id", ramp.AccessID, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query ramp history",
			})
		}

		if entries == nil {
			entries = []models.RampHistoryEntry{}
		}

		return c.JSON(http.StatusOK, map[string]interface{}{
			"ramp":    ramp,
			"history": entries,
		})
	}
}

// HandleV2RampIntervals returns a ramp's status history as contiguous
// intervals over a trailing window, suitable for rendering a timeline band.
// GET /api/v2/ramps/:id/intervals?hours=48 (hours clamped to 1..168)
func HandleV2RampIntervals(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		idStr := c.Param("id")
		id, err := strconv.ParseInt(idStr, 10, 64)
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "invalid ramp id",
			})
		}

		ramp, err := database.GetRampByID(ctx, pool, id)
		if err != nil {
			slog.Error("fetching ramp for intervals", "id", id, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch ramp",
			})
		}
		if ramp == nil {
			return c.JSON(http.StatusNotFound, map[string]string{
				"error": "ramp not found",
			})
		}

		hours, err := parseIntervalHours(c.QueryParam("hours"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "invalid hours parameter",
			})
		}

		windowEnd := time.Now().UTC()
		windowStart := windowEnd.Add(-time.Duration(hours) * time.Hour)

		events, err := database.GetRampStatusEvents(ctx, pool, ramp.AccessID, windowStart)
		if err != nil {
			slog.Error("querying status events", "access_id", ramp.AccessID, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query ramp status events",
			})
		}

		intervals := buildIntervals(events, windowStart, windowEnd, ramp.AccessStatus)

		return c.JSON(http.StatusOK, map[string]interface{}{
			"ramp":         ramp,
			"window_start": windowStart,
			"window_end":   windowEnd,
			"intervals":    intervals,
		})
	}
}

// parseIntervalHours parses the intervals endpoint's hours parameter.
// Empty means the default 48; values clamp to 1..168.
func parseIntervalHours(raw string) (int, error) {
	if raw == "" {
		return 48, nil
	}
	hours, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("parsing hours %q: %w", raw, err)
	}
	if hours < 1 {
		hours = 1
	}
	if hours > 168 {
		hours = 168
	}
	return hours, nil
}

// buildIntervals pairs ordered status-change events into contiguous intervals
// covering [windowStart, windowEnd]. A baseline event recorded before
// windowStart has its start clamped to windowStart. With no events at all the
// whole window carries currentStatus. With events but no baseline (history
// younger than the window) the first interval starts at its event time,
// leaving an honest gap at the head of the window. Consecutive events with
// the same status merge into one interval.
func buildIntervals(events []models.StatusEvent, windowStart, windowEnd time.Time, currentStatus string) []models.RampStatusInterval {
	if len(events) == 0 {
		return []models.RampStatusInterval{{
			Status:   currentStatus,
			Category: models.StatusToCategory(currentStatus),
			Start:    windowStart,
			End:      windowEnd,
		}}
	}

	intervals := make([]models.RampStatusInterval, 0, len(events))
	for _, e := range events {
		start := e.RecordedAt
		if start.Before(windowStart) {
			start = windowStart
		}
		if !start.Before(windowEnd) {
			break
		}

		if n := len(intervals); n > 0 {
			if intervals[n-1].Status == e.AccessStatus {
				continue // merge: previous interval already carries this status
			}
			intervals[n-1].End = start
		}

		intervals = append(intervals, models.RampStatusInterval{
			Status:   e.AccessStatus,
			Category: models.StatusToCategory(e.AccessStatus),
			Start:    start,
			End:      windowEnd,
		})
	}

	return intervals
}

// HandleV2RecentActivity returns recent status changes across all ramps,
// with optional filters: city (exact match), ramp (access_id), and since
// (RFC3339 timestamp — only entries recorded at or after it). With no
// filters the response is identical to the original unfiltered endpoint.
// GET /api/v2/activity?limit=50&city=New+Smyrna+Beach&ramp=NSB-001&since=2026-08-15T00:00:00Z
func HandleV2RecentActivity(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		// Parse optional limit parameter (default 50, max 200).
		limit := 50
		if limitStr := c.QueryParam("limit"); limitStr != "" {
			parsed, err := strconv.Atoi(limitStr)
			if err == nil && parsed > 0 {
				if parsed > 200 {
					parsed = 200
				}
				limit = parsed
			}
		}

		city := c.QueryParam("city")
		ramp := c.QueryParam("ramp")
		since, err := parseActivitySince(c.QueryParam("since"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "invalid since parameter, expected RFC3339 timestamp",
			})
		}

		entries, err := database.GetRecentHistoryFiltered(ctx, pool, limit, city, ramp, since)
		if err != nil {
			slog.Error("querying recent activity", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query recent activity",
			})
		}

		if entries == nil {
			entries = []models.RampHistoryEntry{}
		}

		return c.JSON(http.StatusOK, entries)
	}
}

// parseActivitySince parses the activity endpoint's optional since parameter.
// Empty means no filter (nil); anything else must be RFC3339.
func parseActivitySince(raw string) (*time.Time, error) {
	if raw == "" {
		return nil, nil
	}
	t, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return nil, fmt.Errorf("parsing since %q: %w", raw, err)
	}
	return &t, nil
}

// HandleV2Weather returns current conditions and forecast from the National
// Weather Service API.
// GET /api/v2/weather
func HandleV2Weather(weatherClient *weather.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		info, err := weatherClient.GetWeather(ctx)
		if err != nil {
			slog.Error("fetching weather info", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch weather information",
			})
		}

		return c.JSON(http.StatusOK, info)
	}
}

// _ is used to suppress the unused import warning for math. This ensures the
// import is available for the v1 handler rounding calls that live in the same
// package.
var _ = math.Round
