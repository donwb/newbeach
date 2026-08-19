package weather

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func loadSRFFixture(t *testing.T) string {
	t.Helper()
	raw, err := os.ReadFile("testdata/srf_kmlb.txt")
	require.NoError(t, err)
	return string(raw)
}

func TestParseSurfZone(t *testing.T) {
	fixture := loadSRFFixture(t)

	t.Run("volusia section", func(t *testing.T) {
		sz, err := parseSurfZone(fixture, "FLZ141")
		require.NoError(t, err)
		// The captured product's first-day values: rip Low, surf ~2 ft.
		assert.Contains(t, []string{"Low", "Moderate", "High"}, sz.RipCurrentRisk)
		assert.NotEmpty(t, sz.SurfHeight)
		assert.NotEmpty(t, sz.WaterTemp)
	})

	t.Run("other zone parses independently", func(t *testing.T) {
		sz, err := parseSurfZone(fixture, "FLZ154")
		require.NoError(t, err)
		assert.Contains(t, []string{"Low", "Moderate", "High"}, sz.RipCurrentRisk)
	})

	t.Run("missing zone errors", func(t *testing.T) {
		_, err := parseSurfZone(fixture, "TXZ999")
		assert.Error(t, err)
	})

	t.Run("garbage errors", func(t *testing.T) {
		_, err := parseSurfZone("not a product at all", "FLZ141")
		assert.Error(t, err)
	})

	t.Run("zone without labels errors", func(t *testing.T) {
		_, err := parseSurfZone("FLZ141-\nsome header\n.TODAY...\njust prose, no dotted labels\n", "FLZ141")
		assert.Error(t, err)
	})

	t.Run("labels parse with asterisks and dots trimmed", func(t *testing.T) {
		text := "FLZ141-\nheader\n.REST OF TODAY...\n" +
			"Rip Current Risk*...........Moderate. \n" +
			"Surf Height.................Around 3 feet. \n" +
			"UV Index**..................Very High. \n"
		sz, err := parseSurfZone(text, "FLZ141")
		require.NoError(t, err)
		assert.Equal(t, "Moderate", sz.RipCurrentRisk)
		assert.Equal(t, "Around 3 feet", sz.SurfHeight)
		assert.Equal(t, "Very High", sz.UVIndex)
	})

	t.Run("only first day section is read", func(t *testing.T) {
		text := "FLZ141-\nheader\n.REST OF TODAY...\n" +
			"Rip Current Risk*...........Low. \n" +
			".WEDNESDAY...\n" +
			"Rip Current Risk*...........High. \n"
		sz, err := parseSurfZone(text, "FLZ141")
		require.NoError(t, err)
		assert.Equal(t, "Low", sz.RipCurrentRisk, "tomorrow's risk must not leak into today's")
	})
}

// srfServer serves the products list + product endpoints from the fixture.
func srfServer(t *testing.T, issuance time.Time, hook func(w http.ResponseWriter, r *http.Request) bool) *httptest.Server {
	t.Helper()
	fixture := loadSRFFixture(t)
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hook != nil && hook(w, r) {
			return
		}
		switch r.URL.Path {
		case "/products":
			fmt.Fprintf(w, `{"@graph":[{"id":"test-product-id","issuanceTime":%q}]}`, issuance.Format(time.RFC3339))
		case "/products/test-product-id":
			resp, _ := json.Marshal(map[string]string{
				"issuanceTime": issuance.Format(time.RFC3339),
				"productText":  fixture,
			})
			w.Write(resp)
		default:
			http.NotFound(w, r)
		}
	}))
}

func TestGetSurfZoneFetchesAndCaches(t *testing.T) {
	now := time.Now()
	var hits atomic.Int64
	srv := srfServer(t, now.Add(-time.Hour), func(w http.ResponseWriter, r *http.Request) bool {
		hits.Add(1)
		return false
	})
	defer srv.Close()

	c := NewClient(srv.URL, "", "")
	sz, err := c.GetSurfZone(context.Background())
	require.NoError(t, err)
	assert.NotEmpty(t, sz.RipCurrentRisk)
	assert.False(t, sz.IssuedAt.IsZero())

	before := hits.Load()
	_, err = c.GetSurfZone(context.Background())
	require.NoError(t, err)
	assert.Equal(t, before, hits.Load(), "second call inside TTL hit the server")
}

func TestGetSurfZoneServesStaleThroughOutage(t *testing.T) {
	now := time.Now()
	var failing atomic.Bool
	srv := srfServer(t, now.Add(-time.Hour), func(w http.ResponseWriter, r *http.Request) bool {
		if failing.Load() {
			w.WriteHeader(http.StatusInternalServerError)
			return true
		}
		return false
	})
	defer srv.Close()

	c := NewClient(srv.URL, "", "")
	clock := now
	c.now = func() time.Time { return clock }

	first, err := c.GetSurfZone(context.Background())
	require.NoError(t, err)

	// Past the TTL with the upstream down: the cached product still serves
	// while its issuance is inside srfMaxStale.
	failing.Store(true)
	clock = clock.Add(srfTTL + time.Minute)
	stale, err := c.GetSurfZone(context.Background())
	require.NoError(t, err)
	assert.Equal(t, first, stale)

	// Once the cached product itself is older than a day, it stops serving.
	clock = clock.Add(srfMaxStale)
	_, err = c.GetSurfZone(context.Background())
	assert.Error(t, err)
}

func TestGetSurfZoneRejectsStaleProduct(t *testing.T) {
	// The upstream itself serving a >24h-old product (office stopped
	// issuing) must not produce a rip call.
	now := time.Now()
	srv := srfServer(t, now.Add(-30*time.Hour), nil)
	defer srv.Close()

	c := NewClient(srv.URL, "", "")
	_, err := c.GetSurfZone(context.Background())
	assert.Error(t, err)
}
