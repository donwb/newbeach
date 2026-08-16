package camhealth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// TestClassifyProbe pins the status → online mapping: only 2xx counts as
// online. 404 is MediaMTX's "no publisher" answer; 5xx/3xx and everything
// else must read as offline, never online.
func TestClassifyProbe(t *testing.T) {
	tests := []struct {
		status int
		online bool
	}{
		{http.StatusOK, true},
		{http.StatusNoContent, true},
		{http.StatusNotFound, false},
		{http.StatusInternalServerError, false},
		{http.StatusBadGateway, false},
		{http.StatusMovedPermanently, false},
		{http.StatusUnauthorized, false},
	}
	for _, tt := range tests {
		assert.Equal(t, tt.online, classifyProbe(tt.status), "status %d", tt.status)
	}
}

// TestProbe distinguishes a conclusive answer from a failed probe: an HTTP
// response of any status is conclusive, while an unreachable server draws no
// conclusion (ok=false) so stale-but-real state is never overwritten by a
// network blip on the API's side.
func TestProbe(t *testing.T) {
	p := NewPoller(nil, time.Minute)

	t.Run("200 is online", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))
		defer srv.Close()

		online, ok := p.probe(context.Background(), srv.URL)
		assert.True(t, ok)
		assert.True(t, online)
	})

	t.Run("404 is offline", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusNotFound)
		}))
		defer srv.Close()

		online, ok := p.probe(context.Background(), srv.URL)
		assert.True(t, ok)
		assert.False(t, online)
	})

	t.Run("unreachable is inconclusive", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
		srv.Close() // closed before use: connection refused

		_, ok := p.probe(context.Background(), srv.URL)
		assert.False(t, ok)
	})
}
