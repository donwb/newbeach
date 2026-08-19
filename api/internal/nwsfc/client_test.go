package nwsfc

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func fixtureServer(t *testing.T, hook func(w http.ResponseWriter, r *http.Request) bool) *httptest.Server {
	t.Helper()
	land, err := os.ReadFile("testdata/land_gridpoint.json")
	require.NoError(t, err)
	marine, err := os.ReadFile("testdata/marine_gridpoint.json")
	require.NoError(t, err)

	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hook != nil && hook(w, r) {
			return
		}
		switch r.URL.Path {
		case "/gridpoints/MLB/42,92":
			w.Write(land)
		case "/gridpoints/MLB/46,93":
			w.Write(marine)
		default:
			http.NotFound(w, r)
		}
	}))
}

func newTestClient(baseURL string) *Client {
	c := NewClient(baseURL, "MLB/42,92", "MLB/46,93")
	c.httpClient.Timeout = 2 * time.Second
	return c
}

func TestClientFetchesAndCaches(t *testing.T) {
	var hits atomic.Int64
	srv := fixtureServer(t, func(w http.ResponseWriter, r *http.Request) bool {
		hits.Add(1)
		return false
	})
	defer srv.Close()

	c := newTestClient(srv.URL)
	ctx := context.Background()

	lf, err := c.LandForecast(ctx)
	require.NoError(t, err)
	assert.NotEmpty(t, lf.Hours)

	mf, err := c.MarineForecast(ctx)
	require.NoError(t, err)
	assert.NotEmpty(t, mf.Blocks)

	// Second calls inside the TTL never hit the server.
	before := hits.Load()
	_, err = c.LandForecast(ctx)
	require.NoError(t, err)
	_, err = c.MarineForecast(ctx)
	require.NoError(t, err)
	assert.Equal(t, before, hits.Load(), "cached calls hit the server")
}

func TestClientRetriesTransientErrors(t *testing.T) {
	var failures atomic.Int64
	failures.Store(2) // first two responses 500, then success
	srv := fixtureServer(t, func(w http.ResponseWriter, r *http.Request) bool {
		if failures.Load() > 0 {
			failures.Add(-1)
			w.WriteHeader(http.StatusInternalServerError)
			return true
		}
		return false
	})
	defer srv.Close()

	c := newTestClient(srv.URL)
	lf, err := c.LandForecast(context.Background())
	require.NoError(t, err, "two 500s then success should succeed via retries")
	assert.NotEmpty(t, lf.Hours)
}

func TestClient4xxIsPermanent(t *testing.T) {
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	c := newTestClient(srv.URL)
	_, err := c.LandForecast(context.Background())
	require.Error(t, err)
	assert.Equal(t, int64(1), hits.Load(), "4xx must not be retried")
}

func TestClientServesStaleOnFailure(t *testing.T) {
	var failing atomic.Bool
	srv := fixtureServer(t, func(w http.ResponseWriter, r *http.Request) bool {
		if failing.Load() {
			w.WriteHeader(http.StatusInternalServerError)
			return true
		}
		return false
	})
	defer srv.Close()

	c := newTestClient(srv.URL)
	now := time.Now()
	c.now = func() time.Time { return now }

	ctx := context.Background()
	first, err := c.LandForecast(ctx)
	require.NoError(t, err)

	// Past the TTL but inside maxStale, with the upstream down: stale serves.
	failing.Store(true)
	now = now.Add(landTTL + time.Minute)
	stale, err := c.LandForecast(ctx)
	require.NoError(t, err, "stale value should serve through an outage")
	assert.Equal(t, first, stale)

	// Past maxStale the error surfaces.
	now = now.Add(maxStale)
	_, err = c.LandForecast(ctx)
	assert.Error(t, err, "stale beyond maxStale must not serve")
}
