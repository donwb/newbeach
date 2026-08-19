package nwsfc

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"golang.org/x/sync/singleflight"
)

const (
	// landTTL / marineTTL: how long a fetched forecast is served before
	// refetching. NWS updates the land grid roughly hourly; marine blocks are
	// coarser and move slower.
	landTTL   = time.Hour
	marineTTL = 2 * time.Hour

	// maxStale bounds serve-stale: when the upstream fails, the last good
	// forecast keeps serving up to this long past its fetch, then callers get
	// the error (and consumers degrade to tide-only).
	maxStale = 6 * time.Hour
)

// fcCache is a single-value TTL cache with singleflight refill and
// serve-stale-on-error, the same shape as predict.Service's outlook cache.
type fcCache[T any] struct {
	ttl time.Duration

	mu        sync.Mutex
	val       *T
	fetchedAt time.Time
	group     singleflight.Group
}

// get returns the cached value while fresh, otherwise refetches (collapsing
// concurrent misses). On fetch failure a stale value within maxStale is
// served with a warning.
func (c *fcCache[T]) get(ctx context.Context, now func() time.Time, name string, fetch func(context.Context) (*T, error)) (*T, error) {
	c.mu.Lock()
	if c.val != nil && now().Sub(c.fetchedAt) < c.ttl {
		v := c.val
		c.mu.Unlock()
		return v, nil
	}
	c.mu.Unlock()

	v, err, _ := c.group.Do(name, func() (interface{}, error) {
		val, err := fetch(ctx)
		if err != nil {
			return nil, err
		}
		c.mu.Lock()
		c.val = val
		c.fetchedAt = now()
		c.mu.Unlock()
		return val, nil
	})
	if err != nil {
		c.mu.Lock()
		defer c.mu.Unlock()
		if c.val != nil && now().Sub(c.fetchedAt) < maxStale {
			slog.Warn("serving stale NWS forecast", "forecast", name, "age", now().Sub(c.fetchedAt).Round(time.Minute), "err", err)
			return c.val, nil
		}
		return nil, err
	}
	return v.(*T), nil
}
