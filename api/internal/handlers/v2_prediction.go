package handlers

import (
	"log/slog"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
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
				return c.JSON(http.StatusOK, map[string]interface{}{
					"generated_at": outlook.GeneratedAt,
					"season":       outlook.Season,
					"schedule":     outlook.Schedule,
					"tide":         outlook.Tide,
					"ramp":         ro,
				})
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
