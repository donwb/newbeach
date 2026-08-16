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
)

// outlookTTL is how long a computed outlook is served before recomputing.
// Inputs move slowly (ramp statuses every minute, tides deterministically),
// so ten minutes keeps the endpoint effectively free.
const outlookTTL = 10 * time.Minute

// Service computes and caches the outlook on demand.
type Service struct {
	pool *pgxpool.Pool
	noaa *noaa.Client

	mu       sync.Mutex
	cached   *Outlook
	cachedAt time.Time
	group    singleflight.Group
}

// NewService creates an outlook Service.
func NewService(pool *pgxpool.Pool, noaaClient *noaa.Client) *Service {
	return &Service{pool: pool, noaa: noaaClient}
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

	out := BuildOutlook(now, ramps, params, preds)
	return &out, nil
}
