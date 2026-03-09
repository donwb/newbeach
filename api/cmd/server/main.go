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

	beachapi "github.com/donwb/beach/api"
	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/handlers"
	"github.com/donwb/beach/api/internal/ingester"
	"github.com/donwb/beach/api/internal/noaa"
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
		tideStation = "8721164"
	}

	tempStationsStr := os.Getenv("NOAA_TEMP_STATIONS")
	if tempStationsStr == "" {
		tempStationsStr = "8721604,8720218"
	}
	tempStations := strings.Split(tempStationsStr, ",")

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

	// Set up Echo HTTP server.
	e := echo.New()
	e.HideBanner = true
	e.HidePort = true

	// Serve static website files from the filesystem.
	// In Docker, web files are at /web; locally, they're at ../web or ./web.
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
		e.Static("/", webDir)
	} else {
		slog.Warn("web directory not found, static file serving disabled")
	}

	// Register API routes.
	handlers.RegisterRoutes(e, pool, noaaClient)

	// Start the data ingester in a background goroutine.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ing := ingester.New(pool, gisHost, pollInterval)
	go ing.Start(ctx)

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
