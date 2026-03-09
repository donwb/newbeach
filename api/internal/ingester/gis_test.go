package ingester

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestQueryGIS_Success(t *testing.T) {
	body := `{
		"features": [
			{
				"attributes": {
					"AccessName": "BEACHWAY AV",
					"AccessStatus": "OPEN",
					"OBJECTID": 123,
					"City": "New Smyrna Beach",
					"AccessID": "NSB-001",
					"GeneralLoc": "1400 N ATLANTIC AV"
				}
			},
			{
				"attributes": {
					"AccessName": "CRAWFORD RD",
					"AccessStatus": "OPEN",
					"OBJECTID": 124,
					"City": "New Smyrna Beach",
					"AccessID": "NSB-002",
					"GeneralLoc": "2000 S ATLANTIC AV"
				}
			}
		]
	}`

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(body))
	}))
	defer server.Close()

	// Strip the http:// prefix to use as gisHost, and patch the queryGIS to use http.
	ing := &Ingester{
		gisHost:    server.Listener.Addr().String(),
		httpClient: server.Client(),
		logger:     slog.Default(),
	}

	// We need to test doGISRequest directly since queryGIS builds the URL with https.
	features, err := ing.doGISRequest(context.Background(), server.URL+"/arcgis/rest/services/Beaches/MapServer/7/query?where=AccessStatus%3D%27open%27&outFields=*&f=json")
	require.NoError(t, err)
	assert.Len(t, features, 2)
	assert.Equal(t, "BEACHWAY AV", features[0].Attributes.AccessName)
	assert.Equal(t, "OPEN", features[0].Attributes.AccessStatus)
	assert.Equal(t, int64(123), features[0].Attributes.ObjectID)
	assert.Equal(t, "New Smyrna Beach", features[0].Attributes.City)
	assert.Equal(t, "NSB-001", features[0].Attributes.AccessID)
	assert.Equal(t, "1400 N ATLANTIC AV", features[0].Attributes.GeneralLoc)
}

func TestQueryGIS_EmptyFeatures(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"features": []}`))
	}))
	defer server.Close()

	ing := &Ingester{
		httpClient: server.Client(),
		logger:     slog.Default(),
	}

	features, err := ing.doGISRequest(context.Background(), server.URL+"/query")
	require.NoError(t, err)
	assert.Empty(t, features)
}

func TestQueryGIS_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	ing := &Ingester{
		httpClient: server.Client(),
		logger:     slog.Default(),
	}

	_, err := ing.doGISRequest(context.Background(), server.URL+"/query")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "status 500")
}

func TestQueryGIS_MalformedJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{invalid json`))
	}))
	defer server.Close()

	ing := &Ingester{
		httpClient: server.Client(),
		logger:     slog.Default(),
	}

	_, err := ing.doGISRequest(context.Background(), server.URL+"/query")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "decoding GIS response")
}

func TestQueryGIS_RetryOnFailure(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		if callCount < 3 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"features": [{"attributes": {"AccessName": "TEST", "AccessStatus": "OPEN", "OBJECTID": 1, "City": "Test", "AccessID": "T-001", "GeneralLoc": "123 Main"}}]}`))
	}))
	defer server.Close()

	ing := &Ingester{
		gisHost:    server.Listener.Addr().String(),
		httpClient: server.Client(),
		logger:     slog.Default(),
	}

	// Call doGISRequest multiple times to simulate what retry logic does.
	// First two calls fail (503), third succeeds.
	_, err := ing.doGISRequest(context.Background(), server.URL+"/query")
	assert.Error(t, err) // 503
	_, err = ing.doGISRequest(context.Background(), server.URL+"/query")
	assert.Error(t, err) // 503
	features, err := ing.doGISRequest(context.Background(), server.URL+"/query")
	require.NoError(t, err) // success
	assert.Len(t, features, 1)
	assert.Equal(t, 3, callCount)
}

func TestGISStatuses(t *testing.T) {
	expected := []string{
		"open",
		"closed",
		"closed for high tide",
		"4x4 only",
		"closing in progress",
		"closed - cleared for turtles",
		"closed - at capacity",
		"open - entrance only",
	}

	assert.Equal(t, expected, gisStatuses)
	assert.Len(t, gisStatuses, 8)
}
