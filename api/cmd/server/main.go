package main

import (
	"context"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"

	beachapi "github.com/donwb/beach/api"
	"github.com/donwb/beach/api/internal/camhealth"
	"github.com/donwb/beach/api/internal/conditions"
	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/handlers"
	"github.com/donwb/beach/api/internal/ingester"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/nwsfc"
	"github.com/donwb/beach/api/internal/predict"
	"github.com/donwb/beach/api/internal/videostream"
	"github.com/donwb/beach/api/internal/weather"
)

func main() {
	// Configure structured logging.
	logLevel := slog.LevelInfo
	if lvl := os.Getenv("LOG_LEVEL"); lvl != "" {
		switch strings.ToLower(lvl) {
		case "debug":
			logLevel = slog.LevelDebug
		case "warn":
			logLevel = slog.LevelWarn
		case "error":
			logLevel = slog.LevelError
		}
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: logLevel})))

	slog.Info("starting beach ramp status service")

	// Read configuration from environment.
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		slog.Error("DATABASE_URL is required")
		os.Exit(1)
	}

	gisHost := os.Getenv("GIS_HOST")
	if gisHost == "" {
		gisHost = "maps5.vcgov.org"
	}

	pollInterval := 60 * time.Second
	if pi := os.Getenv("POLL_INTERVAL"); pi != "" {
		if secs, err := strconv.Atoi(pi); err == nil && secs > 0 {
			pollInterval = time.Duration(secs) * time.Second
		}
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	tideStation := os.Getenv("NOAA_TIDE_STATION")
	if tideStation == "" {
		tideStation = "8721147"
	}

	tempStationsStr := os.Getenv("NOAA_TEMP_STATIONS")
	if tempStationsStr == "" {
		tempStationsStr = "8721604,8720218"
	}
	tempStations := strings.Split(tempStationsStr, ",")

	ndbcStation := os.Getenv("NDBC_STATION")
	if ndbcStation == "" {
		ndbcStation = "41113" // Ponce de Leon Inlet wave buoy
	}

	conditionsInterval := 30 * time.Minute
	if ci := os.Getenv("CONDITIONS_INTERVAL"); ci != "" {
		if mins, err := strconv.Atoi(ci); err == nil && mins > 0 {
			conditionsInterval = time.Duration(mins) * time.Minute
		}
	}
	conditionsEnabled := os.Getenv("CONDITIONS_ENABLED") != "false"

	// Kill switch for wave-conditioned predictions: serving falls back to
	// tide-only without touching the learned params or the wave series.
	predictWavesEnabled := os.Getenv("PREDICT_WAVES_ENABLED") != "false"

	// Kill switch for the persistence prior ("did it close yesterday?"):
	// serving goes memoryless; training still learns the shifts.
	predictPersistenceEnabled := os.Getenv("PREDICT_PERSISTENCE_ENABLED") != "false"

	// Weekend outlook: NWS forecast gridpoints (land + marine) feed the
	// multi-day verdicts. The base URL is overridable in case the App
	// Platform egress IP ever gets blocked — point it at the cam-relay
	// droplet's Caddy proxy, the NDBC_ERDDAP_URL precedent.
	weekendEnabled := os.Getenv("WEEKEND_OUTLOOK_ENABLED") != "false"
	nwsBaseURL := os.Getenv("NWS_BASE_URL")
	nwsLandGrid := os.Getenv("NWS_LAND_GRIDPOINT")
	if nwsLandGrid == "" {
		nwsLandGrid = "MLB/42,92" // New Smyrna Beach
	}
	nwsMarineGrid := os.Getenv("NWS_MARINE_GRIDPOINT")
	if nwsMarineGrid == "" {
		nwsMarineGrid = "MLB/46,93" // coastal waters off the inlet (AMZ550)
	}

	camHealthInterval := 60 * time.Second
	if chi := os.Getenv("CAM_HEALTH_INTERVAL"); chi != "" {
		if secs, err := strconv.Atoi(chi); err == nil && secs > 0 {
			camHealthInterval = time.Duration(secs) * time.Second
		}
	}
	camHealthEnabled := os.Getenv("CAM_HEALTH_ENABLED") != "false"

	// Connect to the database.
	pool, err := database.Connect(databaseURL)
	if err != nil {
		slog.Error("failed to connect to database", "err", err)
		os.Exit(1)
	}
	defer database.Close(pool)

	// Run migrations using embedded SQL files from the api root package.
	migrationsSubFS, err := fs.Sub(beachapi.MigrationsFS, "migrations")
	if err != nil {
		slog.Error("failed to access embedded migrations", "err", err)
		os.Exit(1)
	}
	if err := database.RunMigrations(pool, migrationsSubFS); err != nil {
		slog.Error("failed to run migrations", "err", err)
		os.Exit(1)
	}

	// Create NOAA client.
	noaaClient := noaa.NewClient(tideStation, tempStations)

	// Create NWS weather client. Shares NWS_BASE_URL with the forecast
	// client so the droplet-proxy contingency covers every NWS fetch.
	weatherClient := weather.NewClient(nwsBaseURL, os.Getenv("NWS_SRF_OFFICE"), os.Getenv("NWS_SRF_ZONE"))

	// Set up Echo HTTP server.
	e := echo.New()
	e.HideBanner = true
	e.HidePort = true

	// Video stream refresher — resolves the rotating YouTube live HLS URL via
	// yt-dlp and persists to the `video_stream_url` setting. There is no
	// server-side polling: YouTube bot-blocks yt-dlp from datacenter IPs, so
	// the refresh is driven externally by scripts/update-stream-url.sh running
	// from a residential IP (e.g. a cron job on an always-on home machine). The
	// /api/v2/video/refresh endpoint remains only as an on-demand fallback for
	// client playback failures; it shares that datacenter-IP limitation and may
	// fail.
	videoRefresher := videostream.New(
		pool,
		os.Getenv("VIDEO_YOUTUBE_URL"),
		os.Getenv("YT_DLP_PATH"),
	)

	// Register API routes.
	ing := ingester.New(pool, gisHost, pollInterval)
	outlookStation := ndbcStation
	if !predictWavesEnabled {
		outlookStation = ""
	}
	outlookSvc := predict.NewService(pool, noaaClient, outlookStation)
	if !predictPersistenceEnabled {
		outlookSvc.DisablePersistence()
	}

	// Surf report: one casual surf line on the outlook. Its switch is
	// independent of PREDICT_WAVES_ENABLED — killing the copy must not kill
	// the tide model's wave conditioning, and vice versa.
	if os.Getenv("SURF_REPORT_ENABLED") != "false" {
		outlookSvc.SetWeatherClient(weatherClient)
		outlookSvc.EnableSurfReport(ndbcStation)
	}

	// Weekend outlook service — nil when disabled, which unregisters the
	// route entirely (clients hide the section on fetch failure).
	var weekendSvc *predict.WeekendService
	if weekendEnabled {
		nwsClient := nwsfc.NewClient(nwsBaseURL, nwsLandGrid, nwsMarineGrid)
		weekendSvc = predict.NewWeekendService(pool, noaaClient, nwsClient)
		if !predictPersistenceEnabled {
			weekendSvc.DisablePersistence()
		}
	}
	handlers.RegisterRoutes(e, pool, noaaClient, weatherClient, videoRefresher, ing, outlookSvc, weekendSvc, ndbcStation)

	// Serve static website files from the filesystem, after API routes so the
	// CORS and logging middleware registered there wrap static responses too.
	// In Docker, web files are at /web; locally, they're at ../web or ./web.
	// HTML5 mode serves index.html for any path with no matching file and no
	// registered route (/ramp/:id, /tide, /water, /wind — the SPA routes).
	// NOTE: the fallback triggers on *echo.HTTPError 404s. API handlers return
	// JSON errors via c.JSON (never echo.NewHTTPError), which keeps them out of
	// the fallback — keep it that way, and the /api/ Skipper guards the rest.
	webDir := os.Getenv("WEB_DIR")
	if webDir == "" {
		// Try common local dev paths.
		for _, candidate := range []string{"web", "../web", "../../web"} {
			if info, err := os.Stat(candidate); err == nil && info.IsDir() {
				webDir = candidate
				break
			}
		}
	}
	if webDir != "" {
		slog.Info("serving static files", "dir", webDir)
		e.Use(middleware.StaticWithConfig(middleware.StaticConfig{
			Root:  webDir,
			HTML5: true,
			Skipper: func(c echo.Context) bool {
				return strings.HasPrefix(c.Request().URL.Path, "/api/")
			},
		}))
	} else {
		slog.Warn("web directory not found, static file serving disabled")
	}

	// Start the data ingester in a background goroutine.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	videoRefresher.PrimeFromDB(ctx)

	go ing.Start(ctx)

	// Conditions snapshot logger — accumulates tide/wind/wave + ramp-count
	// snapshots in beach_conditions as training data for closure prediction.
	if conditionsEnabled {
		condLogger := conditions.New(pool, noaaClient, weatherClient, ndbcStation, conditionsInterval)
		go condLogger.Start(ctx)
	}

	// Camera health poller — reconciles camera_health against the relay by
	// probing each stream URL. MediaMTX hooks provide instant transitions;
	// this establishes state at boot and repairs anything a missed hook left
	// stale.
	if camHealthEnabled {
		camPoller := camhealth.NewPoller(pool, camHealthInterval)
		go camPoller.Start(ctx)
	}

	// Nightly prediction trainer — learns per-ramp tide-closure thresholds
	// from ramp_status_history and persists them to the settings table.
	trainer := predict.NewTrainer(pool, noaaClient, ndbcStation)
	go trainer.Start(ctx)

	// Start the HTTP server in a goroutine.
	go func() {
		addr := fmt.Sprintf(":%s", port)
		slog.Info("HTTP server starting", "addr", addr)
		if err := e.Start(addr); err != nil && err != http.ErrServerClosed {
			slog.Error("HTTP server error", "err", err)
			os.Exit(1)
		}
	}()

	// Wait for interrupt signal for graceful shutdown.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down...")

	// Cancel the ingester.
	cancel()

	// Graceful shutdown of HTTP server.
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := e.Shutdown(shutdownCtx); err != nil {
		slog.Error("HTTP server shutdown error", "err", err)
	}

	slog.Info("service stopped")
}
