package predict

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/noaa"
)

// trainHour/trainMinute schedule the nightly run at 03:30 ET — after the
// day's closures are all recorded and long before the beach opens.
const (
	trainHour   = 3
	trainMinute = 30

	// staleAfter forces a boot-time training run when the stored params are
	// missing or older than this.
	staleAfter = 48 * time.Hour
)

// Trainer recomputes the learned prediction parameters nightly and persists
// them to the settings table. Training reads full ramp history plus one
// long-range NOAA hilo request; it is cheap enough to rerun unconditionally,
// and the settings upsert is idempotent so overlapping instances are
// harmless.
type Trainer struct {
	pool   *pgxpool.Pool
	noaa   *noaa.Client
	logger *slog.Logger
}

// NewTrainer creates a Trainer.
func NewTrainer(pool *pgxpool.Pool, noaaClient *noaa.Client) *Trainer {
	return &Trainer{
		pool:   pool,
		noaa:   noaaClient,
		logger: slog.Default().With("component", "trainer"),
	}
}

// Start runs the nightly training loop until ctx is cancelled. On boot it
// trains immediately when the stored params are missing or stale.
func (t *Trainer) Start(ctx context.Context) {
	if t.paramsStale(ctx) {
		t.train(ctx)
	}

	for {
		next := nextRunTime(time.Now())
		t.logger.Info("next training run scheduled", "at", next)

		select {
		case <-ctx.Done():
			t.logger.Info("trainer shutting down")
			return
		case <-time.After(time.Until(next)):
			t.train(ctx)
		}
	}
}

// nextRunTime returns the next 03:30 ET strictly after now.
func nextRunTime(now time.Time) time.Time {
	et := now.In(eastern)
	run := time.Date(et.Year(), et.Month(), et.Day(), trainHour, trainMinute, 0, 0, eastern)
	if !run.After(et) {
		run = run.AddDate(0, 0, 1)
	}
	return run
}

// paramsStale reports whether stored params are absent, unreadable, or older
// than staleAfter.
func (t *Trainer) paramsStale(ctx context.Context) bool {
	raw, err := database.GetSetting(ctx, t.pool, SettingsKey)
	if err != nil {
		t.logger.Warn("reading stored params", "err", err)
		return true
	}
	if raw == "" {
		return true
	}
	var p Params
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		t.logger.Warn("stored params unreadable, retraining", "err", err)
		return true
	}
	// A version bump means the blob schema (or its semantics) changed —
	// retrain on boot rather than serving a stale shape for up to 48h.
	if p.Version != paramsVersion {
		return true
	}
	return time.Since(p.ComputedAt) > staleAfter
}

// train runs one full training pass and persists the result.
func (t *Trainer) train(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()

	start := time.Now()

	history, err := database.GetAllRampHistoryEvents(ctx, t.pool)
	if err != nil {
		t.logger.Error("training: loading history", "err", err)
		return
	}
	if len(history) == 0 {
		t.logger.Warn("training: no history yet, skipping")
		return
	}

	// One hilo request covers the entire history span (NOAA allows ~1 year).
	histStart := time.Now()
	for _, events := range history {
		if len(events) > 0 && events[0].RecordedAt.Before(histStart) {
			histStart = events[0].RecordedAt
		}
	}
	preds, err := t.noaa.FetchTidePredictionsRange(ctx, histStart, time.Now().AddDate(0, 0, 1))
	if err != nil {
		t.logger.Error("training: fetching tide predictions", "err", err)
		return
	}

	params := Train(history, preds, time.Now())

	blob, err := json.Marshal(params)
	if err != nil {
		t.logger.Error("training: marshaling params", "err", err)
		return
	}
	if err := database.UpsertSetting(ctx, t.pool, SettingsKey, string(blob)); err != nil {
		t.logger.Error("training: persisting params", "err", err)
		return
	}

	t.logger.Info("training complete",
		"duration", time.Since(start),
		"ramps_learned", len(params.Ramps),
		"default_threshold_ft", params.Default.ThresholdFt,
	)
}
