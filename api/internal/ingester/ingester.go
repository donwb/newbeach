package ingester

import (
	"context"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Ingester polls the Volusia County GIS endpoint at a configurable interval
// and upserts ramp status data into the database.
type Ingester struct {
	pool         *pgxpool.Pool
	gisHost      string
	pollInterval time.Duration
	httpClient   *http.Client
	logger       *slog.Logger
	healthy      atomic.Bool
}

// New creates a new Ingester instance.
func New(pool *pgxpool.Pool, gisHost string, pollInterval time.Duration) *Ingester {
	ing := &Ingester{
		pool:         pool,
		gisHost:      gisHost,
		pollInterval: pollInterval,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		logger: slog.Default().With("component", "ingester"),
	}
	return ing
}

// IsHealthy returns true if the last poll cycle completed successfully.
func (ing *Ingester) IsHealthy() bool {
	return ing.healthy.Load()
}

// Start begins the polling loop. It runs the first poll immediately, then
// continues on the configured interval. It blocks until ctx is cancelled.
func (ing *Ingester) Start(ctx context.Context) {
	ing.logger.Info("starting GIS ingester",
		"gis_host", ing.gisHost,
		"poll_interval", ing.pollInterval,
	)

	// Run immediately on start.
	ing.poll(ctx)

	ticker := time.NewTicker(ing.pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			ing.logger.Info("ingester shutting down")
			return
		case <-ticker.C:
			ing.poll(ctx)
		}
	}
}

// poll queries the GIS endpoint for each known status value and processes
// the returned features.
func (ing *Ingester) poll(ctx context.Context) {
	start := time.Now()
	totalFeatures := 0
	successCount := 0

	for _, status := range gisStatuses {
		features, err := ing.queryGIS(ctx, status)
		if err != nil {
			ing.logger.Error("GIS query failed",
				"status", status,
				"err", err,
			)
			continue
		}

		successCount++
		totalFeatures += len(features)

		if len(features) > 0 {
			if err := ing.processFeatures(ctx, features); err != nil {
				ing.logger.Error("processing features failed",
					"status", status,
					"err", err,
				)
				continue
			}
		}
	}

	duration := time.Since(start)

	// Healthy if at least one status query succeeded.
	ing.healthy.Store(successCount > 0)

	ing.logger.Info("poll cycle complete",
		"duration", duration,
		"statuses_queried", len(gisStatuses),
		"statuses_succeeded", successCount,
		"total_features", totalFeatures,
	)
}
