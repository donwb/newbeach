package handlers

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"

	"github.com/donwb/beach/api/internal/noaa"
)

// RegisterRoutes wires all HTTP routes onto the Echo instance.
// It configures CORS, request logging, and registers both v1 (backward-compatible)
// and v2 endpoints.
func RegisterRoutes(e *echo.Echo, pool *pgxpool.Pool, noaaClient *noaa.Client) {
	// --- Middleware ---

	// CORS: allow all origins (public API).
	e.Use(middleware.CORSWithConfig(middleware.CORSConfig{
		AllowOrigins: []string{"*"},
		AllowMethods: []string{"GET", "HEAD", "OPTIONS"},
	}))

	// Request logging.
	e.Use(middleware.RequestLoggerWithConfig(middleware.RequestLoggerConfig{
		LogStatus:   true,
		LogURI:      true,
		LogError:    true,
		LogLatency:  true,
		LogMethod:   true,
		HandleError: true,
		LogValuesFunc: func(c echo.Context, v middleware.RequestLoggerValues) error {
			if v.Error != nil {
				e.Logger.Errorf("method=%s uri=%s status=%d latency=%s error=%v",
					v.Method, v.URI, v.Status, v.Latency, v.Error)
			} else {
				e.Logger.Infof("method=%s uri=%s status=%d latency=%s",
					v.Method, v.URI, v.Status, v.Latency)
			}
			return nil
		},
	}))

	// Recover from panics.
	e.Use(middleware.Recover())

	// --- v1 endpoints (exact backward compatibility for Tidbyt) ---

	e.GET("/rampstatus", HandleV1RampStatus(pool))
	e.GET("/tides", HandleV1Tides(noaaClient))
	e.GET("/ramps", HandleV1Ramps(pool))

	// --- v2 endpoints ---

	v2 := e.Group("/api/v2")
	v2.GET("/ramps", HandleV2Ramps(pool))
	v2.GET("/ramps/:id", HandleV2RampByID(pool))
	v2.GET("/tides", HandleV2Tides(noaaClient))
	v2.GET("/health", HandleV2Health(pool))
	v2.GET("/config", HandleV2Config())
}
