package handlers

import (
	"log/slog"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/predict"
)

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
