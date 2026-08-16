package handlers

import (
	"log/slog"
	"net/http"
	"os"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/camhealth"
	"github.com/donwb/beach/api/internal/database"
)

// HandleCameraHealthHook receives stream up/down events from MediaMTX on the
// relay droplet (runOnReady / runOnNotReady, see docs/CAM-RELAY.md). Paths
// that aren't roster cameras (ad-hoc test publishes) are acknowledged and
// ignored so the relay never error-spams over them.
// POST /api/v2/hooks/camera-health   Body: {"id": "nsb", "online": true}
func HandleCameraHealthHook(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		var body struct {
			ID     string `json:"id"`
			Online *bool  `json:"online"`
		}
		if err := c.Bind(&body); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		}
		if body.ID == "" || body.Online == nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "id and online are required"})
		}

		known, err := database.CameraExists(ctx, pool, body.ID)
		if err != nil {
			slog.Error("camera health hook: existence check failed", "id", body.ID, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to record status"})
		}
		if !known {
			return c.JSON(http.StatusOK, map[string]string{"status": "ignored", "id": body.ID})
		}

		flipped, err := camhealth.SetStatus(ctx, pool, body.ID, *body.Online, camhealth.SourceHook)
		if err != nil {
			slog.Error("camera health hook: recording failed", "id", body.ID, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to record status"})
		}
		if flipped {
			slog.Info("camera status changed", "camera", body.ID, "online", *body.Online, "source", camhealth.SourceHook)
		}

		return c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "id": body.ID, "flipped": flipped})
	}
}

// HandleV2CamerasHealth returns current health for every observed camera plus
// recent flap history — the debugging/dashboard view of the cam relay.
// GET /api/v2/cameras/health?limit=100
func HandleV2CamerasHealth(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		health, err := camhealth.GetAll(ctx, pool)
		if err != nil {
			slog.Error("failed to read camera health", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to read camera health"})
		}

		limit := 100
		if l := c.QueryParam("limit"); l != "" {
			if n, err := strconv.Atoi(l); err == nil {
				limit = n
			}
		}
		transitions, err := camhealth.RecentTransitions(ctx, pool, limit)
		if err != nil {
			slog.Error("failed to read camera health history", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to read camera health history"})
		}

		return c.JSON(http.StatusOK, map[string]interface{}{
			"cameras":            health,
			"recent_transitions": transitions,
		})
	}
}

// hookKeyAuth validates the X-Hook-Key header against the CAM_HOOK_KEY
// environment variable. Separate from the admin key so the relay droplet
// holds a credential that can only report camera health, nothing else.
func hookKeyAuth() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			expected := os.Getenv("CAM_HOOK_KEY")
			if expected == "" {
				return c.JSON(http.StatusServiceUnavailable, map[string]string{"error": "camera health hooks not configured"})
			}
			if c.Request().Header.Get("X-Hook-Key") != expected {
				return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid hook key"})
			}
			return next(c)
		}
	}
}
