package handlers

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/predict"
)

// HandleV2Outlook returns the full casual open/close outlook for every ramp.
// GET /api/v2/outlook
func HandleV2Outlook(svc *predict.Service) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		outlook, err := svc.Get(ctx)
		if err != nil {
			slog.Error("building outlook", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to build outlook",
			})
		}

		return c.JSON(http.StatusOK, outlook)
	}
}

// HandleV2RampOutlook returns one ramp's outlook plus the shared context.
// GET /api/v2/ramps/:id/outlook
func HandleV2RampOutlook(svc *predict.Service) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "invalid ramp id",
			})
		}

		outlook, err := svc.Get(ctx)
		if err != nil {
			slog.Error("building outlook", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to build outlook",
			})
		}

		for _, ro := range outlook.Ramps {
			if ro.RampID == id {
				resp := map[string]interface{}{
					"generated_at": outlook.GeneratedAt,
					"season":       outlook.Season,
					"schedule":     outlook.Schedule,
					"tide":         outlook.Tide,
					"ramp":         ro,
				}
				// Shared context the bulk endpoint carries; omitted when nil,
				// matching its omitempty behavior.
				if outlook.Surf != nil {
					resp["surf"] = outlook.Surf
				}
				if outlook.SurfReport != nil {
					resp["surf_report"] = outlook.SurfReport
				}
				return c.JSON(http.StatusOK, resp)
			}
		}

		return c.JSON(http.StatusNotFound, map[string]string{
			"error": "ramp not found",
		})
	}
}

// HandleAdminPredictionParams returns the raw learned-parameters blob written
// by the nightly trainer, for operator inspection.
// GET /api/v2/admin/prediction/params
func HandleAdminPredictionParams(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		raw, err := database.GetSetting(ctx, pool, predict.SettingsKey)
		if err != nil {
			slog.Error("fetching prediction params", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch prediction params",
			})
		}
		if raw == "" {
			return c.JSON(http.StatusNotFound, map[string]string{
				"error": "prediction params not yet computed",
			})
		}

		return c.JSONBlob(http.StatusOK, []byte(raw))
	}
}

// HandleAdminPredictionScorecard grades a past day's outlook against recorded
// reality: each daytime tide peak is replayed through the model's risk rules
// and compared with the closure history. Defaults to yesterday (Eastern);
// ?date=YYYY-MM-DD grades any past day inside the recorded history.
// GET /api/v2/admin/prediction/scorecard
func HandleAdminPredictionScorecard(pool *pgxpool.Pool, noaaClient *noaa.Client, ndbcStation string) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		todayET := time.Now().In(eastern)
		today := time.Date(todayET.Year(), todayET.Month(), todayET.Day(), 0, 0, 0, 0, eastern)
		date := today.AddDate(0, 0, -1)
		if raw := c.QueryParam("date"); raw != "" {
			parsed, err := time.ParseInLocation("2006-01-02", raw, eastern)
			if err != nil {
				return c.JSON(http.StatusBadRequest, map[string]string{
					"error": "invalid date, expected YYYY-MM-DD",
				})
			}
			date = parsed
		}
		if !date.Before(today) {
			return c.JSON(http.StatusBadRequest, map[string]string{
				"error": "date must be a past day — the scorecard grades recorded history",
			})
		}

		history, err := database.GetAllRampHistoryEvents(ctx, pool)
		if err != nil {
			slog.Error("scorecard: loading history", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to load ramp history",
			})
		}

		params := predict.Params{Default: predict.DefaultParams}
		if raw, err := database.GetSetting(ctx, pool, predict.SettingsKey); err != nil {
			slog.Warn("scorecard: reading params, using defaults", "err", err)
		} else if raw != "" {
			if err := json.Unmarshal([]byte(raw), &params); err != nil {
				slog.Warn("scorecard: unparseable params, using defaults", "err", err)
				params = predict.Params{Default: predict.DefaultParams}
			}
		}

		ramps, err := database.GetRampsWithStatusSince(ctx, pool, "", "")
		if err != nil {
			slog.Error("scorecard: loading ramps", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to load ramps",
			})
		}
		closureHeights := make(map[string]*float64, len(ramps))
		for _, r := range ramps {
			closureHeights[r.AccessID] = r.ClosureHeightFt
		}

		// A day either side so labeling sees the peaks adjacent to midnight.
		preds, err := noaaClient.FetchTidePredictionsRange(ctx, date.AddDate(0, 0, -1), date.AddDate(0, 0, 1))
		if err != nil {
			slog.Error("scorecard: fetching tide predictions", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to fetch tide predictions",
			})
		}

		// Sea-state context for the grades — best-effort, the scorecard reads
		// fine without it.
		waves, err := database.GetWaveObservationsRange(ctx, pool, ndbcStation, date.AddDate(0, 0, -1), date.AddDate(0, 0, 1))
		if err != nil {
			slog.Warn("scorecard: loading wave observations", "err", err)
		}

		// Manually quarantined days — best-effort, the heuristics run either way.
		var excludedDays map[string]bool
		if raw, err := database.GetSetting(ctx, pool, predict.ExcludedDaysKey); err != nil {
			slog.Warn("scorecard: reading excluded days, ignoring", "err", err)
		} else {
			excludedDays = predict.ParseExcludedDays(raw)
		}

		return c.JSON(http.StatusOK, predict.BuildScorecard(date, history, closureHeights, params, preds, waves, excludedDays))
	}
}
