package ingester

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// GIS status values to query (lowercase for the URL).
var gisStatuses = []string{
	"open",
	"closed",
	"closed for high tide",
	"4x4 only",
	"closing in progress",
	"closed - cleared for turtles",
	"closed - at capacity",
	"open - entrance only",
}

// gisResponse is the top-level JSON response from the ArcGIS MapServer.
type gisResponse struct {
	Features []gisFeature `json:"features"`
}

// gisFeature represents a single ramp feature from the GIS endpoint.
type gisFeature struct {
	Attributes gisAttributes `json:"attributes"`
}

// gisAttributes holds the fields extracted from each GIS feature.
type gisAttributes struct {
	AccessName   string `json:"AccessName"`
	AccessStatus string `json:"AccessStatus"`
	ObjectID     int64  `json:"OBJECTID"`
	City         string `json:"City"`
	AccessID     string `json:"AccessID"`
	GeneralLoc   string `json:"GeneralLoc"`
}

// queryGIS fetches all ramp features with the given status from the GIS endpoint.
// Retries up to 3 times with exponential backoff on failure.
func (ing *Ingester) queryGIS(ctx context.Context, status string) ([]gisFeature, error) {
	// Build the URL with spaces encoded as %20 but single quotes kept raw.
	encodedStatus := strings.ReplaceAll(status, " ", "%20")
	fullURL := fmt.Sprintf("https://%s/arcgis/rest/services/Beaches/MapServer/7/query?where=AccessStatus='%s'&outFields=*&f=json",
		ing.gisHost, encodedStatus)

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(1<<uint(attempt-1)) * time.Second
			ing.logger.Info("retrying GIS query", "status", status, "attempt", attempt+1, "backoff", backoff)

			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff):
			}
		}

		features, err := ing.doGISRequest(ctx, fullURL)
		if err == nil {
			return features, nil
		}
		lastErr = err
		ing.logger.Warn("GIS query failed", "status", status, "attempt", attempt+1, "err", err)
	}

	return nil, fmt.Errorf("querying GIS for status %s after 3 attempts: %w", status, lastErr)
}

// doGISRequest performs a single HTTP request to the GIS endpoint.
func (ing *Ingester) doGISRequest(ctx context.Context, reqURL string) ([]gisFeature, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating GIS request: %w", err)
	}

	resp, err := ing.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("executing GIS request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GIS returned status %d", resp.StatusCode)
	}

	var gisResp gisResponse
	if err := json.NewDecoder(resp.Body).Decode(&gisResp); err != nil {
		return nil, fmt.Errorf("decoding GIS response: %w", err)
	}

	return gisResp.Features, nil
}
