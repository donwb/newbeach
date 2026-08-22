package predict

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/singleflight"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/weather"
)

// outlookTTL is how long a computed outlook is served before recomputing.
// Inputs move slowly (ramp statuses every minute, tides deterministically),
// so ten minutes keeps the endpoint effectively free.
const outlookTTL = 10 * time.Minute

// Service computes and caches the outlook on demand.
type Service struct {
	pool    *pgxpool.Pool
	noaa    *noaa.Client
	station string // NDBC buoy for serve-time sea state; empty = tide-only

	// Surf report inputs (nil/empty = no surf line). surfStation is
	// deliberately separate from station: PREDICT_WAVES_ENABLED gates the
	// tide model's wave conditioning, SURF_REPORT_ENABLED gates the copy,
	// and killing one must not kill the other.
	weather     *weather.Client
	surfStation string

	// noPersistence is the PREDICT_PERSISTENCE_ENABLED=false kill switch:
	// the prior is neither loaded nor applied, and the learned params are
	// left alone.
	noPersistence bool

	mu       sync.Mutex
	cached   *Outlook
	cachedAt time.Time
	group    singleflight.Group
}

// NewService creates an outlook Service. ndbcStation names the buoy whose
// latest wave_observations row conditions the risk calls; pass "" to serve
// tide-only (the PREDICT_WAVES_ENABLED kill switch).
func NewService(pool *pgxpool.Pool, noaaClient *noaa.Client, ndbcStation string) *Service {
	return &Service{pool: pool, noaa: noaaClient, station: ndbcStation}
}

// DisablePersistence serves memoryless risk calls (no "did it close
// yesterday?" prior) without touching training.
func (s *Service) DisablePersistence() {
	s.noPersistence = true
}

// loadPriorDay reads yesterday's status events for every ramp and derives
// each ramp's PriorDay. Best-effort: the outlook must never fail because
// the history read did, so any error logs and returns nil (memoryless).
func loadPriorDay(ctx context.Context, pool *pgxpool.Pool, now time.Time, preds []models.TidePrediction, params Params, label string) map[string]PriorDay {
	et := now.In(eastern)
	since := time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern).AddDate(0, 0, -1)
	events, err := database.GetAllRampStatusEventsSince(ctx, pool, since)
	if err != nil {
		slog.Warn(label+": reading yesterday's history, serving memoryless", "err", err)
		return nil
	}
	return priorDayFacts(now, events, preds, params.hardOpen())
}

// SetWeatherClient hands the service the NWS client used for surf-report
// wind and the Surf Zone Forecast. Additive so either feature wanting it
// can land first.
func (s *Service) SetWeatherClient(w *weather.Client) {
	s.weather = w
}

// EnableSurfReport turns on the surf line, reading sea state from the given
// buoy's wave_observations rows.
func (s *Service) EnableSurfReport(ndbcStation string) {
	s.surfStation = ndbcStation
}

// Get returns the current outlook, recomputing at most every outlookTTL.
func (s *Service) Get(ctx context.Context) (*Outlook, error) {
	s.mu.Lock()
	if s.cached != nil && time.Since(s.cachedAt) < outlookTTL {
		out := s.cached
		s.mu.Unlock()
		return out, nil
	}
	s.mu.Unlock()

	v, err, _ := s.group.Do("outlook", func() (interface{}, error) {
		out, err := s.build(ctx)
		if err != nil {
			return nil, err
		}
		s.mu.Lock()
		s.cached = out
		s.cachedAt = time.Now()
		s.mu.Unlock()
		return out, nil
	})
	if err != nil {
		// Serve a stale outlook over an error if one exists.
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.cached != nil {
			slog.Warn("serving stale outlook", "err", err)
			return s.cached, nil
		}
		return nil, err
	}
	return v.(*Outlook), nil
}

// build assembles the outlook's inputs and computes it.
func (s *Service) build(ctx context.Context) (*Outlook, error) {
	now := time.Now()

	ramps, err := database.GetRampsWithStatusSince(ctx, s.pool, "", "")
	if err != nil {
		return nil, fmt.Errorf("loading ramps: %w", err)
	}

	params := Params{Default: DefaultParams}
	if raw, err := database.GetSetting(ctx, s.pool, SettingsKey); err != nil {
		slog.Warn("outlook: reading params, using defaults", "err", err)
	} else if raw != "" {
		if err := json.Unmarshal([]byte(raw), &params); err != nil {
			slog.Warn("outlook: unparseable params, using defaults", "err", err)
			params = Params{Default: DefaultParams}
		}
	}

	// Yesterday through +2 days: enough behind for a closure-time height,
	// enough ahead for tomorrow's peaks.
	preds, err := s.noaa.FetchTidePredictionsRange(ctx, now.AddDate(0, 0, -1), now.AddDate(0, 0, 2))
	if err != nil {
		return nil, fmt.Errorf("fetching tide predictions: %w", err)
	}

	// Latest sea state, best-effort: the outlook must never fail because the
	// buoy or its table is unavailable — BuildOutlook treats nil (and stale
	// observations) as tide-only. The surf report reads the same row, so the
	// fetch happens when either consumer wants it — but the tide model only
	// ever sees it through its own station gate.
	var wave *models.WaveSample
	if s.station != "" || s.surfStation != "" {
		station := s.station
		if station == "" {
			station = s.surfStation
		}
		wave, err = database.GetLatestWaveObservation(ctx, s.pool, station)
		if err != nil {
			slog.Warn("outlook: reading latest wave observation", "err", err)
			wave = nil
		}
	}

	modelWave := wave
	if s.station == "" {
		modelWave = nil // PREDICT_WAVES_ENABLED=false: tide-only risk calls
	}

	var prior map[string]PriorDay
	if !s.noPersistence {
		prior = loadPriorDay(ctx, s.pool, now, preds, params, "outlook")
	}

	out := BuildOutlook(now, ramps, params, preds, modelWave, prior)

	// The surf line rides on top — best-effort, never fails the outlook.
	if s.surfStation != "" {
		var cond *weather.Conditions
		var srf *weather.SurfZone
		if s.weather != nil {
			if cond, err = s.weather.GetCurrentConditions(ctx); err != nil {
				slog.Warn("outlook: surf report conditions unavailable", "err", err)
				cond = nil
			}
			if srf, err = s.weather.GetSurfZone(ctx); err != nil {
				slog.Warn("outlook: surf zone forecast unavailable", "err", err)
				srf = nil
			}
		}
		out.SurfReport = BuildSurfReport(now, &out, wave, cond, srf)
	}

	return &out, nil
}
