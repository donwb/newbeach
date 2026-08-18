package conditions

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/database"
)

// minMonthSamples is the wave_observations row count below which a month is
// considered missing and worth fetching from the NDBC archive. A partial
// month (buoy adrift for a stretch) clears the floor and is left alone, so
// the backfill never refetches forever; a near-empty month keeps retrying.
const minMonthSamples = 100

// BackfillWaves ensures wave_observations covers [start, now) for the
// station: the realtime2 window first (one request, heals up to ~45 days of
// logger downtime), then each calendar month from start whose data is
// missing, oldest first. Every write is an idempotent upsert, so this is
// safe to run on every boot — steady-state cost is the single realtime2
// request.
func BackfillWaves(ctx context.Context, pool *pgxpool.Pool, station string, start time.Time) error {
	logger := slog.Default().With("component", "wave-backfill", "station", station)
	client := NewNDBCClient(station)
	return backfillWaves(ctx, pool, client, station, start, time.Now().UTC(), logger)
}

// backfillWaves is the testable core of BackfillWaves.
func backfillWaves(ctx context.Context, pool *pgxpool.Pool, client *NDBCClient, station string, start, now time.Time, logger *slog.Logger) error {
	if recent, err := client.FetchRealtimeWindow(ctx); err != nil {
		logger.Warn("realtime window fetch failed", "err", err)
	} else if n, err := database.UpsertWaveObservations(ctx, pool, station, recent); err != nil {
		return fmt.Errorf("upserting realtime wave window: %w", err)
	} else if n > 0 {
		logger.Info("realtime wave window healed", "inserted", n)
	}

	// Walk whole months oldest-first. The current month is covered by the
	// realtime2 window above; archive months end at the first of this month.
	month := time.Date(start.Year(), start.Month(), 1, 0, 0, 0, 0, time.UTC)
	thisMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	for ; month.Before(thisMonth); month = month.AddDate(0, 1, 0) {
		count, err := database.CountWaveObservations(ctx, pool, station, month, month.AddDate(0, 1, 0))
		if err != nil {
			return fmt.Errorf("checking wave coverage for %s: %w", month.Format("2006-01"), err)
		}
		if count >= minMonthSamples {
			continue
		}

		samples, found, err := client.FetchArchiveMonth(ctx, month.Year(), month.Month())
		if err != nil {
			// One flaky month shouldn't abort the rest of the walk.
			logger.Warn("archive month fetch failed", "month", month.Format("2006-01"), "err", err)
			continue
		}
		if !found {
			logger.Info("no NDBC archive for month", "month", month.Format("2006-01"))
			continue
		}

		n, err := database.UpsertWaveObservations(ctx, pool, station, samples)
		if err != nil {
			return fmt.Errorf("upserting wave archive for %s: %w", month.Format("2006-01"), err)
		}
		logger.Info("backfilled wave month", "month", month.Format("2006-01"), "fetched", len(samples), "inserted", n)
	}
	return nil
}
