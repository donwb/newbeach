package handlers

import (
	"log/slog"
	"net/http"
	"regexp"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/widgetpush"
)

var hexTokenRe = regexp.MustCompile(`^[0-9a-fA-F]{32,256}$`)

// HandleV2RegisterWidgetPushToken stores a widget push token from the iOS
// widget extension. POST /api/v2/widgets/push-token
// {token: hex, environment: production|sandbox}. Unauthenticated on
// purpose — the extension has no key, and a stray registration only earns
// a harmless push.
func HandleV2RegisterWidgetPushToken(pool *pgxpool.Pool, bundleID string) echo.HandlerFunc {
	return func(c echo.Context) error {
		var req struct {
			Token       string `json:"token"`
			Environment string `json:"environment"`
		}
		if err := c.Bind(&req); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		}
		if !hexTokenRe.MatchString(req.Token) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "token must be hex"})
		}
		switch req.Environment {
		case "":
			req.Environment = "production"
		case "production", "sandbox":
		default:
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "environment must be production or sandbox"})
		}
		if err := database.UpsertWidgetPushToken(c.Request().Context(), pool, req.Token, req.Environment, bundleID); err != nil {
			slog.Error("registering widget push token", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to register token"})
		}
		return c.JSON(http.StatusOK, map[string]string{"status": "registered", "environment": req.Environment})
	}
}

// HandleAdminWidgetPush sends a content-changed push to every registered
// widget right now — the way to prove the pipeline without waiting for the
// county to flip a ramp. POST /api/v2/admin/widgets/push
func HandleAdminWidgetPush(notifier *widgetpush.Notifier, pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		if notifier == nil {
			return c.JSON(http.StatusServiceUnavailable, map[string]string{"error": "widget push not configured"})
		}
		sent, dropped, failed := notifier.PushNow(c.Request().Context())
		tokens, _ := database.ListWidgetPushTokens(c.Request().Context(), pool)
		return c.JSON(http.StatusOK, map[string]any{
			"sent": sent, "dropped": dropped, "failed": failed, "registered": len(tokens),
		})
	}
}
