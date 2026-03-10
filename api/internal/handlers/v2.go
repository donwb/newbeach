package handlers

import (
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/weather"
)

// HandleV2Ramps returns ramp statuses with optional city and status query filters.
// GET /api/v2/ramps?city=New+Smyrna+Beach&status=open
func HandleV2Ramps(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		city := c.QueryParam("city")
		status := c.QueryParam("status")

		query := `SELECT id, ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at
		          FROM ramp_status WHERE 1=1`
		args := make([]interface{}, 0)
		argIdx := 1

		if city != "" {
			query += fmt.Sprintf(" AND city = $%d", argIdx)
			args = append(args, city)
			argIdx++
		}
		if status != "" {
			query += fmt.Sprintf(" AND status_category = $%d", argIdx)
			args = append(args, status)
			argIdx++
		}

		query += " ORDER BY city, ramp_name"

		rows, err := pool.Query(ctx, query, args...)
		if err != nil {
			slog.Error("querying v2 ramps", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query ramps",
			})
		}
		defer rows.Close()

		ramps := make([]models.RampStatus, 0)
		for rows.Next() {
			var r models.RampStatus
			if err := rows.Scan(
				&r.ID, &r.RampName, &r.AccessStatus, &r.StatusCategory,
				&r.ObjectID, &r.City, &r.AccessID, &r.Location, &r.UpdatedAt,
			); err != nil {
				slog.Error("scanning v2 ramp row", "err", err)
				continue
			}
			ramps = append(ramps, r)
		}

		if err := rows.Err(); err != nil {
			slog.Error("iterating v2 ramp rows", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to read ramp rows",
			})
		}

		return c.JSON(http.StatusOK, ramps)
	}
}

// HandleV2RampByID returns a single ramp by its database ID.
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

		var r models.RampStatus
		err = pool.QueryRow(ctx,
			`SELECT id, ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at
			 FROM ramp_status WHERE id = $1`, id).
			Scan(&r.ID, &r.RampName, &r.AccessStatus, &r.StatusCategory,
				&r.ObjectID, &r.City, &r.AccessID, &r.Location, &r.UpdatedAt)

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

// HandleV2Health returns the service health status including database connectivity.
// GET /api/v2/health
func HandleV2Health(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		dbStatus := "connected"
		if err := pool.Ping(ctx); err != nil {
			slog.Error("health check database ping failed", "err", err)
			dbStatus = "disconnected"
		}

		status := "ok"
		httpStatus := http.StatusOK
		if dbStatus != "connected" {
			status = "degraded"
			httpStatus = http.StatusServiceUnavailable
		}

		return c.JSON(httpStatus, map[string]string{
			"status":   status,
			"database": dbStatus,
		})
	}
}

// HandleV2Config returns client configuration from environment variables.
// GET /api/v2/config
func HandleV2Config() echo.HandlerFunc {
	return func(c echo.Context) error {
		webcamURL := os.Getenv("WEBCAM_URL")

		return c.JSON(http.StatusOK, map[string]interface{}{
			"webcam_url":        webcamURL,
			"tide_station":      os.Getenv("NOAA_TIDE_STATION"),
			"temp_stations":     os.Getenv("NOAA_TEMP_STATIONS"),
			"water_temp_avg":    true,
			"default_city":      "New Smyrna Beach",
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

// HandleV2RecentActivity returns recent status changes across all ramps.
// GET /api/v2/activity?limit=50
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

		entries, err := database.GetRecentHistory(ctx, pool, limit)
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
