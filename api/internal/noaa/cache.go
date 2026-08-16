package noaa

import (
	"context"
	"fmt"
	"sync"
	"time"

	"golang.org/x/sync/singleflight"
)

// predictionCacheTTL is how long fetched tide predictions stay fresh.
// Predictions are deterministic astronomical data, so a long TTL is safe;
// keys include the date range, so a "today" request naturally rolls over at
// midnight.
const predictionCacheTTL = 6 * time.Hour

type predictionCacheEntry struct {
	resp    noaaPredictionResponse
	expires time.Time
}

// predictionCache is a small TTL cache for NOAA prediction responses, with
// singleflight so concurrent misses collapse into one upstream request.
type predictionCache struct {
	mu      sync.Mutex
	entries map[string]predictionCacheEntry
	group   singleflight.Group
}

// fetchPredictionsCached wraps fetchPredictions with the TTL cache.
func (c *Client) fetchPredictionsCached(ctx context.Context, interval string, begin, end time.Time) (noaaPredictionResponse, error) {
	key := fmt.Sprintf("%s|%s|%s",
		interval,
		begin.In(eastern).Format("20060102"),
		end.In(eastern).Format("20060102"),
	)

	c.predCache.mu.Lock()
	if entry, ok := c.predCache.entries[key]; ok && time.Now().Before(entry.expires) {
		c.predCache.mu.Unlock()
		return entry.resp, nil
	}
	c.predCache.mu.Unlock()

	v, err, _ := c.predCache.group.Do(key, func() (interface{}, error) {
		resp, err := c.fetchPredictions(ctx, interval, begin, end)
		if err != nil {
			return nil, err
		}
		c.predCache.mu.Lock()
		if c.predCache.entries == nil {
			c.predCache.entries = make(map[string]predictionCacheEntry)
		}
		c.predCache.entries[key] = predictionCacheEntry{resp: resp, expires: time.Now().Add(predictionCacheTTL)}
		// Drop expired entries so day-keyed entries don't accumulate forever.
		for k, e := range c.predCache.entries {
			if time.Now().After(e.expires) {
				delete(c.predCache.entries, k)
			}
		}
		c.predCache.mu.Unlock()
		return resp, nil
	})
	if err != nil {
		return noaaPredictionResponse{}, err
	}
	return v.(noaaPredictionResponse), nil
}
