package nwsfc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

const (
	// defaultBaseURL is the public NWS API. Prod may override it via
	// NWS_BASE_URL to route through the cam-relay droplet's Caddy proxy if
	// the App Platform egress IP ever gets blocked (the NDBC_ERDDAP_URL
	// precedent — see docs/WAVE-DATA.md).
	defaultBaseURL = "https://api.weather.gov"

	// userAgent is required by the NWS API.
	userAgent = "(beach-ramp-status, github.com/donwb/beach)"

	// fetchAttempts / initial backoff for transient NWS failures (routine
	// 5xxs), same shape as the GIS ingester's retry loop.
	fetchAttempts = 3
)

// Client fetches land and marine gridpoint forecasts. Gridpoints are
// configured directly ("MLB/42,92") — no /points resolution round-trip.
type Client struct {
	httpClient *http.Client
	baseURL    string
	landGrid   string
	marineGrid string

	landCache   fcCache[LandForecast]
	marineCache fcCache[MarineForecast]

	now func() time.Time // stubbed in tests
}

// NewClient creates a forecast client. Empty baseURL means the public NWS
// API; grids are "OFFICE/x,y" gridpoint identifiers.
func NewClient(baseURL, landGrid, marineGrid string) *Client {
	if baseURL == "" {
		baseURL = defaultBaseURL
	}
	return &Client{
		httpClient:  &http.Client{Timeout: 15 * time.Second},
		baseURL:     baseURL,
		landGrid:    landGrid,
		marineGrid:  marineGrid,
		landCache:   fcCache[LandForecast]{ttl: landTTL},
		marineCache: fcCache[MarineForecast]{ttl: marineTTL},
		now:         time.Now,
	}
}

// LandForecast returns the expanded hourly land forecast, cached per landTTL.
func (c *Client) LandForecast(ctx context.Context) (*LandForecast, error) {
	return c.landCache.get(ctx, c.now, "land", func(ctx context.Context) (*LandForecast, error) {
		resp, err := c.fetchGridpoint(ctx, c.landGrid)
		if err != nil {
			return nil, fmt.Errorf("fetching land gridpoint %s: %w", c.landGrid, err)
		}
		return expandLand(resp, c.now()), nil
	})
}

// MarineForecast returns the marine wave forecast, cached per marineTTL.
func (c *Client) MarineForecast(ctx context.Context) (*MarineForecast, error) {
	return c.marineCache.get(ctx, c.now, "marine", func(ctx context.Context) (*MarineForecast, error) {
		resp, err := c.fetchGridpoint(ctx, c.marineGrid)
		if err != nil {
			return nil, fmt.Errorf("fetching marine gridpoint %s: %w", c.marineGrid, err)
		}
		return expandMarine(resp, c.now()), nil
	})
}

// fetchGridpoint GETs a raw gridpoint document, retrying transient failures.
// 4xx statuses are permanent (a bad grid ID never fixes itself); 5xx and
// transport errors retry with exponential backoff.
func (c *Client) fetchGridpoint(ctx context.Context, grid string) (*gridpointResponse, error) {
	url := fmt.Sprintf("%s/gridpoints/%s", c.baseURL, grid)

	var lastErr error
	for attempt := 0; attempt < fetchAttempts; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(1<<uint(attempt-1)) * time.Second
			slog.Info("retrying NWS gridpoint fetch", "grid", grid, "attempt", attempt+1, "backoff", backoff)
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff):
			}
		}

		resp, err := c.doGridpoint(ctx, url)
		if err == nil {
			return resp, nil
		}
		lastErr = err
		var pe *permanentError
		if errors.As(err, &pe) {
			return nil, pe.err
		}
	}
	return nil, fmt.Errorf("fetching %s after %d attempts: %w", url, fetchAttempts, lastErr)
}

func (c *Client) doGridpoint(ctx context.Context, url string) (*gridpointResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, &permanentError{fmt.Errorf("creating request for %s: %w", url, err)}
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "application/geo+json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("requesting %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf("NWS API %s returned status %d", url, resp.StatusCode)
		if resp.StatusCode >= 400 && resp.StatusCode < 500 {
			return nil, &permanentError{err}
		}
		return nil, err
	}

	var out gridpointResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("decoding response from %s: %w", url, err)
	}
	return &out, nil
}

// permanentError marks failures that retrying cannot fix.
type permanentError struct{ err error }

func (e *permanentError) Error() string { return e.err.Error() }
