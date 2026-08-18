package conditions

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/weather"
)

// Logger periodically snapshots environmental conditions (tide, wind, waves)
// and county-wide ramp state into the beach_conditions table. Each source is
// best-effort: a failed fetch stores NULL for its columns and the row is
// written regardless, so gaps in one upstream never lose the others.
type Logger struct {
	pool     *pgxpool.Pool
	noaa     *noaa.Client
	weather  *weather.Client
	ndbc     *NDBCClient
	interval time.Duration
	logger   *slog.Logger
}

// New creates a conditions snapshot logger.
func New(pool *pgxpool.Pool, noaaClient *noaa.Client, weatherClient *weather.Client, ndbcStation string, interval time.Duration) *Logger {
	return &Logger{
		pool:     pool,
		noaa:     noaaClient,
		weather:  weatherClient,
		ndbc:     NewNDBCClient(ndbcStation),
		interval: interval,
		logger:   slog.Default().With("component", "conditions"),
	}
}

// Start begins the snapshot loop: one snapshot immediately, then on the
// configured interval until ctx is cancelled.
func (l *Logger) Start(ctx context.Context) {
	l.logger.Info("starting conditions logger", "interval", l.interval)

	l.snapshot(ctx)

	ticker := time.NewTicker(l.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			l.logger.Info("conditions logger shutting down")
			return
		case <-ticker.C:
			l.snapshot(ctx)
		}
	}
}

// snapshot gathers one row of conditions and persists it.
func (l *Logger) snapshot(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	now := time.Now()
	var c models.BeachConditions

	// Tide: current predicted height (interpolated from hourly points) and the
	// next predicted high-tide peak from today's extremes.
	if hourly, err := l.noaa.FetchHourlyPredictions(ctx); err != nil {
		l.logger.Warn("snapshot: hourly tide predictions unavailable", "err", err)
	} else if h, ok := interpolateHeight(hourly, now); ok {
		c.TidePredictedFt = &h
	}

	if preds, err := l.noaa.FetchTidePredictions(ctx); err != nil {
		l.logger.Warn("snapshot: tide predictions unavailable", "err", err)
	} else {
		for _, p := range preds {
			if p.Type == "H" && p.Time.After(now) && p.Height != nil {
				c.NextPeakFt = p.Height
				t := p.Time
				c.NextPeakAt = &t
				break
			}
		}
	}

	// Wind from the latest NWS observation.
	if cond, err := l.weather.GetCurrentConditions(ctx); err != nil {
		l.logger.Warn("snapshot: NWS conditions unavailable", "err", err)
	} else {
		c.WindSpeedMph = ParseMph(cond.WindSpeed)
		c.WindGustMph = ParseMph(cond.WindGust)
		if cond.WindDirection != "" {
			dir := cond.WindDirection
			c.WindDir = &dir
		}
	}

	// Waves from the NDBC buoy. The observation also lands in the canonical
	// wave_observations series (keyed by the buoy's own timestamp) that the
	// prediction model trains and serves from.
	if waves, err := l.ndbc.FetchLatestWaves(ctx); err != nil {
		l.logger.Warn("snapshot: NDBC waves unavailable", "err", err)
	} else {
		c.WaveHeightFt = &waves.WaveHeightFt
		c.DominantPeriodS = waves.DominantPeriodS
		if !waves.ObservedAt.IsZero() {
			sample := models.WaveSample{
				Time:            waves.ObservedAt,
				HeightFt:        waves.WaveHeightFt,
				DominantPeriodS: waves.DominantPeriodS,
			}
			if _, err := database.UpsertWaveObservations(ctx, l.pool, l.ndbc.stationID, []models.WaveSample{sample}); err != nil {
				l.logger.Warn("snapshot: wave observation upsert failed", "err", err)
			}
		}
	}

	// County-wide ramp counts. "Open" counts anything drivable (open or
	// limited category); tide closures are split out from other closures.
	if statuses, err := database.ListRampStatuses(ctx, l.pool); err != nil {
		l.logger.Warn("snapshot: ramp statuses unavailable", "err", err)
	} else if len(statuses) > 0 {
		var open, tide, other int
		for _, s := range statuses {
			switch {
			case s == "CLOSED FOR HIGH TIDE":
				tide++
			case models.StatusToCategory(s) == "closed":
				other++
			default:
				open++
			}
		}
		c.RampsOpen = &open
		c.RampsClosedTide = &tide
		c.RampsClosedOther = &other
	}

	if err := database.InsertBeachConditions(ctx, l.pool, c); err != nil {
		l.logger.Error("snapshot: insert failed", "err", err)
		return
	}
	l.logger.Debug("conditions snapshot recorded")
}

// interpolateHeight linearly interpolates the tide height at t from a series
// of prediction points. Returns false when t falls outside the series.
func interpolateHeight(points []models.TidePredictionPoint, t time.Time) (float64, bool) {
	for i := 1; i < len(points); i++ {
		p0, p1 := points[i-1], points[i]
		if t.Before(p0.Time) || t.After(p1.Time) {
			continue
		}
		span := p1.Time.Sub(p0.Time).Seconds()
		if span <= 0 {
			return p0.Height, true
		}
		f := t.Sub(p0.Time).Seconds() / span
		return p0.Height + f*(p1.Height-p0.Height), true
	}
	return 0, false
}
