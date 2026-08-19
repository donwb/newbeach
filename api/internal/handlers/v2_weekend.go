package handlers

import (
	"log/slog"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/predict"
)

// HandleV2WeekendOutlook returns the multi-day "when should I go" outlook.
// GET /api/v2/outlook/weekend
func HandleV2WeekendOutlook(svc *predict.WeekendService) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		outlook, err := svc.Get(ctx)
		if err != nil {
			slog.Error("building weekend outlook", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to build weekend outlook",
			})
		}

		return c.JSON(http.StatusOK, outlook)
	}
}
