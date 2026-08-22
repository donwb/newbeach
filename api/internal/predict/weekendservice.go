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
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/nwsfc"
)

// weekendTTL is how long a computed weekend outlook is served before
// recomputing. The answer moves on the scale of NWS forecast updates
// (roughly hourly), not minutes.
const weekendTTL = time.Hour

// ForecastSource is what the weekend outlook needs from the NWS forecast
// client — an interface so tests can stub it and the kill switch can pass
// nil (nil source = tide-only weekend verdicts).
type ForecastSource interface {
	LandForecast(ctx context.Context) (*nwsfc.LandForecast, error)
	MarineForecast(ctx context.Context) (*nwsfc.MarineForecast, error)
}

// WeekendService computes and caches the weekend outlook on demand, the same
// shape as the live outlook's Service.
type WeekendService struct {
	pool *pgxpool.Pool
	noaa *noaa.Client
	fc   ForecastSource

	noPersistence bool // PREDICT_PERSISTENCE_ENABLED=false

	mu       sync.Mutex
	cached   *WeekendOutlook
	cachedAt time.Time
	group    singleflight.Group
}

// NewWeekendService creates a weekend outlook service. fc may be nil, which
// serves honest tide-only verdicts.
func NewWeekendService(pool *pgxpool.Pool, noaaClient *noaa.Client, fc ForecastSource) *WeekendService {
	return &WeekendService{pool: pool, noaa: noaaClient, fc: fc}
}

// Get returns the current weekend outlook, recomputing at most every
// weekendTTL and serving a stale copy over an error.
func (s *WeekendService) Get(ctx context.Context) (*WeekendOutlook, error) {
	s.mu.Lock()
	if s.cached != nil && time.Since(s.cachedAt) < weekendTTL {
		out := s.cached
		s.mu.Unlock()
		return out, nil
	}
	s.mu.Unlock()

	v, err, _ := s.group.Do("weekend", func() (interface{}, error) {
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
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.cached != nil {
			slog.Warn("serving stale weekend outlook", "err", err)
			return s.cached, nil
		}
		return nil, err
	}
	return v.(*WeekendOutlook), nil
}

// DisablePersistence serves memoryless verdicts (no prior-day carry-over).
func (s *WeekendService) DisablePersistence() {
	s.noPersistence = true
}

// build assembles the weekend outlook's inputs and computes it. Tides are
// required; the NWS forecasts are best-effort — a day without coverage gets
// a tide-only verdict and says so in its basis.
func (s *WeekendService) build(ctx context.Context) (*WeekendOutlook, error) {
	now := time.Now()

	ramps, err := database.GetRampsWithStatusSince(ctx, s.pool, "", "")
	if err != nil {
		return nil, fmt.Errorf("loading ramps: %w", err)
	}

	params := Params{Default: DefaultParams}
	if raw, err := database.GetSetting(ctx, s.pool, SettingsKey); err != nil {
		slog.Warn("weekend outlook: reading params, using defaults", "err", err)
	} else if raw != "" {
		if err := json.Unmarshal([]byte(raw), &params); err != nil {
			slog.Warn("weekend outlook: unparseable params, using defaults", "err", err)
			params = Params{Default: DefaultParams}
		}
	}

	// Verdict thresholds: experiential and live-tunable via the settings
	// table; defaults from the calibration interview.
	vp := DefaultVerdictParams()
	if raw, err := database.GetSetting(ctx, s.pool, WeekendParamsKey); err != nil {
		slog.Warn("weekend outlook: reading verdict params, using defaults", "err", err)
	} else if raw != "" {
		if err := json.Unmarshal([]byte(raw), &vp); err != nil {
			slog.Warn("weekend outlook: unparseable verdict params, using defaults", "err", err)
			vp = DefaultVerdictParams()
		}
	}

	// Yesterday behind (closure-height context) through the whole horizon
	// ahead. A wider range than the live outlook's fetch, so it lands in its
	// own entry of the noaa prediction cache.
	preds, err := s.noaa.FetchTidePredictionsRange(ctx, now.AddDate(0, 0, -1), now.AddDate(0, 0, weekendHorizonDays+1))
	if err != nil {
		return nil, fmt.Errorf("fetching tide predictions: %w", err)
	}

	var land *nwsfc.LandForecast
	var marine *nwsfc.MarineForecast
	if s.fc != nil {
		if land, err = s.fc.LandForecast(ctx); err != nil {
			slog.Warn("weekend outlook: land forecast unavailable, tide-only", "err", err)
			land = nil
		}
		if marine, err = s.fc.MarineForecast(ctx); err != nil {
			slog.Warn("weekend outlook: marine forecast unavailable", "err", err)
			marine = nil
		}
	}

	var prior map[string]PriorDay
	if !s.noPersistence {
		prior = loadPriorDay(ctx, s.pool, now, preds, params, "weekend outlook")
	}

	out := BuildWeekendOutlook(now, ramps, params, vp, preds, land, marine, prior)
	return &out, nil
}
