package ingester

import (
	"context"
	"log/slog"
	"net/http"
	"sync"
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

	mu     sync.Mutex
	health Health
}

// Health is a snapshot of the ingester's recent poll outcomes. A poll is
// "clean" when every GIS status query succeeded and every returned feature
// was persisted.
type Health struct {
	LastPollAt      time.Time     `json:"last_poll_at"`
	LastCleanPollAt time.Time     `json:"last_clean_poll_at"`
	QueriesFailed   int           `json:"queries_failed"`
	FeaturesFailed  int           `json:"features_failed"`
	PollInterval    time.Duration `json:"-"`
}

// Status classifies the snapshot at time now: "starting" before the first
// poll completes, "degraded" when the last cycle had failures or no clean
// poll has happened within 5 poll intervals, otherwise "ok". The staleness
// check also catches a stalled poll loop, since LastCleanPollAt stops
// advancing either way.
func (h Health) Status(now time.Time) string {
	switch {
	case h.LastPollAt.IsZero():
		return "starting"
	case h.QueriesFailed > 0 || h.FeaturesFailed > 0:
		return "degraded"
	case now.Sub(h.LastCleanPollAt) > 5*h.PollInterval:
		return "degraded"
	default:
		return "ok"
	}
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

// Health returns a snapshot of the ingester's recent poll outcomes.
func (ing *Ingester) Health() Health {
	ing.mu.Lock()
	defer ing.mu.Unlock()
	h := ing.health
	h.PollInterval = ing.pollInterval
	return h
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
	queriesFailed := 0
	featuresFailed := 0

	for _, status := range gisStatuses {
		features, err := ing.queryGIS(ctx, status)
		if err != nil {
			queriesFailed++
			ing.logger.Error("GIS query failed",
				"status", status,
				"err", err,
			)
			continue
		}

		totalFeatures += len(features)

		if len(features) > 0 {
			failed := ing.processFeatures(ctx, features)
			featuresFailed += failed
			if failed > 0 {
				ing.logger.Error("processing features failed",
					"status", status,
					"failed", failed,
					"total", len(features),
				)
			}
		}
	}

	duration := time.Since(start)
	now := time.Now()

	ing.mu.Lock()
	ing.health.LastPollAt = now
	ing.health.QueriesFailed = queriesFailed
	ing.health.FeaturesFailed = featuresFailed
	if queriesFailed == 0 && featuresFailed == 0 {
		ing.health.LastCleanPollAt = now
	}
	ing.mu.Unlock()

	ing.logger.Info("poll cycle complete",
		"duration", duration,
		"statuses_queried", len(gisStatuses),
		"queries_failed", queriesFailed,
		"features_failed", featuresFailed,
		"total_features", totalFeatures,
	)
}
