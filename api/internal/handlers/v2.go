package handlers

import (
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"os"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
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

// _ is used to suppress the unused import warning for math. This ensures the
// import is available for the v1 handler rounding calls that live in the same
// package.
var _ = math.Round
