package handlers

import (
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
)

// HandleV1RampStatus returns all ramp statuses in the exact v1 JSON contract
// consumed by the Tidbyt device. GET /rampstatus
func HandleV1RampStatus(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		rows, err := pool.Query(ctx,
			`SELECT id, ramp_name, access_status, object_id, city, access_id, location
			 FROM ramp_status
			 ORDER BY ramp_name`)
		if err != nil {
			slog.Error("querying ramp status", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query ramp status",
			})
		}
		defer rows.Close()

		result := make([]models.V1RampStatus, 0)
		for rows.Next() {
			var r models.V1RampStatus
			if err := rows.Scan(&r.ID, &r.RampName, &r.AccessStatus, &r.ObjectID, &r.City, &r.AccessID, &r.Location); err != nil {
				slog.Error("scanning ramp row", "err", err)
				continue
			}
			result = append(result, r)
		}

		if err := rows.Err(); err != nil {
			slog.Error("iterating ramp rows", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to read ramp status rows",
			})
		}

		return c.JSON(http.StatusOK, result)
	}
}

// HandleV1Tides returns tide and water temperature data in the exact v1 JSON
// contract consumed by the Tidbyt device. GET /tides
func HandleV1Tides(noaaClient *noaa.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		info, err := noaaClient.GetTideInfo(ctx)
		if err != nil {
			slog.Error("fetching tide info", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch tide information",
			})
		}

		// Build v1 tide info array.
		tideInfos := make([]models.V1TideInfo, 0, len(info.Predictions))
		for _, p := range info.Predictions {
			tideInfos = append(tideInfos, models.V1TideInfo{
				TideDateTime: p.Time.Format("2006-01-02T15:04:00Z"),
				HighOrLow:    p.Type,
			})
		}

		// Build v1 water temps array.
		waterTemps := make([]models.V1WaterTemp, 0, len(info.WaterTemps))
		for _, wt := range info.WaterTemps {
			waterTemps = append(waterTemps, models.V1WaterTemp{
				StationID:   wt.StationID,
				StationName: wt.StationName,
				WaterTemp:   int(math.Round(wt.TempF)),
			})
		}

		// The top-level waterTemp comes from the first station (Canaveral).
		topLevelTemp := 0
		if len(info.WaterTemps) > 0 {
			topLevelTemp = int(math.Round(info.WaterTemps[0].TempF))
		}

		resp := models.V1TideResponse{
			CurrentTideHighOrLow: info.Direction,
			TideLevelPercentage:  info.Percentage,
			WaterTemp:            topLevelTemp,
			TideInfo:             tideInfos,
			WaterTemps:           waterTemps,
		}

		return c.JSON(http.StatusOK, resp)
	}
}

// HandleV1Ramps returns all ramp statuses in the legacy plain text format.
// GET /ramps
// Format: "RAMPNAME is : STATUS\n"
func HandleV1Ramps(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		rows, err := pool.Query(ctx,
			`SELECT ramp_name, access_status
			 FROM ramp_status
			 ORDER BY ramp_name`)
		if err != nil {
			slog.Error("querying ramp status for /ramps", "err", err)
			return c.String(http.StatusInternalServerError, "failed to query ramp status")
		}
		defer rows.Close()

		var sb strings.Builder
		for rows.Next() {
			var name, status string
			if err := rows.Scan(&name, &status); err != nil {
				slog.Error("scanning ramp row for /ramps", "err", err)
				continue
			}
			sb.WriteString(fmt.Sprintf("%s is : %s\n", name, status))
		}

		if err := rows.Err(); err != nil {
			slog.Error("iterating ramp rows for /ramps", "err", err)
			return c.String(http.StatusInternalServerError, "failed to read ramp status rows")
		}

		return c.String(http.StatusOK, sb.String())
	}
}
