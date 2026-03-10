package weather

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"
)

const (
	// NWS API base URL.
	nwsBaseURL = "https://api.weather.gov"
	// New Smyrna Beach approximate coordinates.
	defaultLat = 29.0258
	defaultLon = -80.9270
	// User-Agent is required by the NWS API.
	userAgent = "(beach-ramp-status, github.com/donwb/beach)"
)

// Conditions represents the current observed weather conditions from the
// nearest NWS observation station.
type Conditions struct {
	Temperature   float64   `json:"temperature_f"`
	WindSpeed     string    `json:"wind_speed"`
	WindDirection string    `json:"wind_direction"`
	Description   string    `json:"description"`
	Humidity      int       `json:"humidity"`
	Icon          string    `json:"icon"`
	UVIndex       *int      `json:"uv_index,omitempty"`
	RetrievedAt   time.Time `json:"retrieved_at"`
}

// Forecast represents a single forecast period from the NWS (e.g. "Tonight",
// "Wednesday").
type Forecast struct {
	Name         string `json:"name"`
	Temperature  int    `json:"temperature"`
	TempUnit     string `json:"temp_unit"`
	WindSpeed    string `json:"wind_speed"`
	WindDir      string `json:"wind_direction"`
	ShortDesc    string `json:"short_description"`
	DetailedDesc string `json:"detailed_description"`
	IsDaytime    bool   `json:"is_daytime"`
	Icon         string `json:"icon"`
}

// WeatherInfo combines current conditions and the multi-period forecast.
type WeatherInfo struct {
	Current  *Conditions `json:"current"`
	Forecast []Forecast  `json:"forecast"`
}

// Client fetches weather data from the National Weather Service API
// (api.weather.gov). The NWS API is free and requires no API key — only a
// descriptive User-Agent header.
type Client struct {
	httpClient *http.Client
	lat        float64
	lon        float64

	// Cached grid/station lookups (set once, never change).
	mu                 sync.Mutex
	forecastURL        string
	observationStation string
}

// NewClient creates a weather API client configured for the default beach
// coordinates.
func NewClient() *Client {
	return &Client{
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		lat: defaultLat,
		lon: defaultLon,
	}
}

// GetWeather returns the current conditions and forecast for the configured
// location. On the first call it resolves the NWS grid point and nearest
// observation station, caching the results for subsequent calls.
func (c *Client) GetWeather(ctx context.Context) (*WeatherInfo, error) {
	if err := c.ensureGridResolved(ctx); err != nil {
		return nil, fmt.Errorf("resolving NWS grid point: %w", err)
	}

	// Fetch current conditions and forecast concurrently.
	type condResult struct {
		cond *Conditions
		err  error
	}
	type fcstResult struct {
		forecast []Forecast
		err      error
	}

	condCh := make(chan condResult, 1)
	fcstCh := make(chan fcstResult, 1)

	go func() {
		cond, err := c.fetchCurrentConditions(ctx)
		condCh <- condResult{cond, err}
	}()

	go func() {
		fc, err := c.fetchForecast(ctx)
		fcstCh <- fcstResult{fc, err}
	}()

	cr := <-condCh
	fr := <-fcstCh

	// Current conditions are optional — a failure is logged but doesn't fail
	// the whole request.
	if cr.err != nil {
		slog.Warn("failed to fetch current conditions", "err", cr.err)
	}

	if fr.err != nil {
		return nil, fmt.Errorf("fetching forecast: %w", fr.err)
	}

	return &WeatherInfo{
		Current:  cr.cond,
		Forecast: fr.forecast,
	}, nil
}

// --- NWS API response shapes ---

// nwsPointsResponse is the JSON shape from GET /points/{lat},{lon}.
type nwsPointsResponse struct {
	Properties struct {
		Forecast            string `json:"forecast"`
		ObservationStations string `json:"observationStations"`
	} `json:"properties"`
}

// nwsStationsResponse is the JSON shape from the observationStations URL.
type nwsStationsResponse struct {
	Features []struct {
		Properties struct {
			StationIdentifier string `json:"stationIdentifier"`
		} `json:"properties"`
	} `json:"features"`
}

// nwsObservationResponse is the JSON shape from GET /stations/{id}/observations/latest.
type nwsObservationResponse struct {
	Properties struct {
		TextDescription string `json:"textDescription"`
		Temperature     struct {
			Value *float64 `json:"value"`
		} `json:"temperature"`
		WindSpeed struct {
			Value *float64 `json:"value"`
		} `json:"windSpeed"`
		WindDirection struct {
			Value *float64 `json:"value"`
		} `json:"windDirection"`
		RelativeHumidity struct {
			Value *float64 `json:"value"`
		} `json:"relativeHumidity"`
		Icon string `json:"icon"`
	} `json:"properties"`
}

// nwsForecastResponse is the JSON shape from the forecast URL.
type nwsForecastResponse struct {
	Properties struct {
		Periods []struct {
			Name             string `json:"name"`
			Temperature      int    `json:"temperature"`
			TemperatureUnit  string `json:"temperatureUnit"`
			WindSpeed        string `json:"windSpeed"`
			WindDirection    string `json:"windDirection"`
			ShortForecast    string `json:"shortForecast"`
			DetailedForecast string `json:"detailedForecast"`
			IsDaytime        bool   `json:"isDaytime"`
			Icon             string `json:"icon"`
		} `json:"periods"`
	} `json:"properties"`
}

// --- Internal helpers ---

// ensureGridResolved fetches /points/{lat},{lon} to populate the cached
// forecast URL and observation station. It's a no-op if already resolved.
func (c *Client) ensureGridResolved(ctx context.Context) error {
	c.mu.Lock()
	if c.forecastURL != "" && c.observationStation != "" {
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	// Resolve the grid point.
	pointsURL := fmt.Sprintf("%s/points/%.4f,%.4f", nwsBaseURL, c.lat, c.lon)
	var points nwsPointsResponse
	if err := c.doJSON(ctx, pointsURL, &points); err != nil {
		return fmt.Errorf("fetching NWS points: %w", err)
	}

	if points.Properties.Forecast == "" {
		return fmt.Errorf("NWS points response missing forecast URL")
	}
	if points.Properties.ObservationStations == "" {
		return fmt.Errorf("NWS points response missing observation stations URL")
	}

	// Resolve the nearest observation station.
	var stations nwsStationsResponse
	if err := c.doJSON(ctx, points.Properties.ObservationStations, &stations); err != nil {
		return fmt.Errorf("fetching NWS observation stations: %w", err)
	}

	if len(stations.Features) == 0 {
		return fmt.Errorf("NWS returned no observation stations")
	}

	stationID := stations.Features[0].Properties.StationIdentifier

	c.mu.Lock()
	c.forecastURL = points.Properties.Forecast
	c.observationStation = stationID
	c.mu.Unlock()

	slog.Info("resolved NWS grid point",
		"forecast_url", points.Properties.Forecast,
		"observation_station", stationID,
	)

	return nil
}

// fetchCurrentConditions retrieves the latest observation from the cached
// observation station.
func (c *Client) fetchCurrentConditions(ctx context.Context) (*Conditions, error) {
	c.mu.Lock()
	station := c.observationStation
	c.mu.Unlock()

	if station == "" {
		return nil, fmt.Errorf("observation station not resolved")
	}

	obsURL := fmt.Sprintf("%s/stations/%s/observations/latest", nwsBaseURL, station)
	var obs nwsObservationResponse
	if err := c.doJSON(ctx, obsURL, &obs); err != nil {
		return nil, fmt.Errorf("fetching latest observation from station %s: %w", station, err)
	}

	cond := &Conditions{
		Description: obs.Properties.TextDescription,
		Icon:        obs.Properties.Icon,
		RetrievedAt: time.Now(),
	}

	// Temperature from NWS is in Celsius — convert to Fahrenheit.
	if obs.Properties.Temperature.Value != nil {
		cond.Temperature = celsiusToFahrenheit(*obs.Properties.Temperature.Value)
	}

	// Wind speed from NWS is in km/h — convert to mph and format.
	if obs.Properties.WindSpeed.Value != nil {
		mph := kmhToMph(*obs.Properties.WindSpeed.Value)
		cond.WindSpeed = fmt.Sprintf("%.0f mph", mph)
	}

	// Wind direction in degrees — convert to cardinal direction.
	if obs.Properties.WindDirection.Value != nil {
		cond.WindDirection = degreesToCardinal(*obs.Properties.WindDirection.Value)
	}

	// Relative humidity.
	if obs.Properties.RelativeHumidity.Value != nil {
		cond.Humidity = int(*obs.Properties.RelativeHumidity.Value)
	}

	return cond, nil
}

// fetchForecast retrieves the multi-period forecast from the cached forecast
// URL.
func (c *Client) fetchForecast(ctx context.Context) ([]Forecast, error) {
	c.mu.Lock()
	url := c.forecastURL
	c.mu.Unlock()

	if url == "" {
		return nil, fmt.Errorf("forecast URL not resolved")
	}

	var nwsResp nwsForecastResponse
	if err := c.doJSON(ctx, url, &nwsResp); err != nil {
		return nil, fmt.Errorf("fetching NWS forecast: %w", err)
	}

	periods := nwsResp.Properties.Periods
	forecasts := make([]Forecast, 0, len(periods))
	for _, p := range periods {
		forecasts = append(forecasts, Forecast{
			Name:         p.Name,
			Temperature:  p.Temperature,
			TempUnit:     p.TemperatureUnit,
			WindSpeed:    p.WindSpeed,
			WindDir:      p.WindDirection,
			ShortDesc:    p.ShortForecast,
			DetailedDesc: p.DetailedForecast,
			IsDaytime:    p.IsDaytime,
			Icon:         p.Icon,
		})
	}

	return forecasts, nil
}

// doJSON performs an HTTP GET to the given URL, decoding the response JSON into
// dest. It sets the required User-Agent header on every request.
func (c *Client) doJSON(ctx context.Context, url string, dest interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("creating request for %s: %w", url, err)
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "application/geo+json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("requesting %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("NWS API %s returned status %d", url, resp.StatusCode)
	}

	if err := json.NewDecoder(resp.Body).Decode(dest); err != nil {
		return fmt.Errorf("decoding response from %s: %w", url, err)
	}

	return nil
}

// --- Unit conversion helpers ---

// celsiusToFahrenheit converts a temperature from Celsius to Fahrenheit.
func celsiusToFahrenheit(c float64) float64 {
	return c*9.0/5.0 + 32.0
}

// kmhToMph converts a speed from km/h to mph.
func kmhToMph(kmh float64) float64 {
	return kmh * 0.621371
}

// degreesToCardinal converts a wind direction in degrees to a cardinal compass
// direction string (N, NNE, NE, etc.).
func degreesToCardinal(degrees float64) string {
	directions := []string{
		"N", "NNE", "NE", "ENE",
		"E", "ESE", "SE", "SSE",
		"S", "SSW", "SW", "WSW",
		"W", "WNW", "NW", "NNW",
	}
	idx := int((degrees + 11.25) / 22.5) % 16
	if idx < 0 {
		idx += 16
	}
	return directions[idx]
}
