package noaa

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"net/url"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

const baseURL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

// Client fetches tide predictions and water temperature from the NOAA
// Tides & Currents API.
type Client struct {
	httpClient     *http.Client
	tideStationID  string
	tempStationIDs []string
}

// NewClient creates a NOAA API client.
//   - tideStation is the NOAA station ID used for tide predictions (e.g. "8721164").
//   - tempStations is a slice of NOAA station IDs used for water temperature readings.
func NewClient(tideStation string, tempStations []string) *Client {
	return &Client{
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		tideStationID:  tideStation,
		tempStationIDs: tempStations,
	}
}

// noaaPredictionResponse is the raw JSON shape returned by the NOAA predictions endpoint.
type noaaPredictionResponse struct {
	Predictions []struct {
		T    string `json:"t"`    // "2026-03-09 11:24"
		V    string `json:"v"`    // tide height value (unused here)
		Type string `json:"type"` // "H" or "L"
	} `json:"predictions"`
}

// noaaTempResponse is the raw JSON shape returned by the NOAA water_temperature endpoint.
type noaaTempResponse struct {
	Metadata struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	} `json:"metadata"`
	Data []struct {
		V string `json:"v"` // temperature value as string
	} `json:"data"`
}

// FetchTidePredictions retrieves today's high/low tide predictions from the
// configured NOAA tide station.
func (c *Client) FetchTidePredictions(ctx context.Context) ([]models.TidePrediction, error) {
	now := time.Now()
	today := now.Format("20060102")

	params := url.Values{
		"product":    {"predictions"},
		"datum":      {"MLLW"},
		"time_zone":  {"lst_ldt"},
		"units":      {"english"},
		"format":     {"json"},
		"interval":   {"hilo"},
		"station":    {c.tideStationID},
		"begin_date": {today},
		"end_date":   {today},
	}

	reqURL := fmt.Sprintf("%s?%s", baseURL, params.Encode())

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating tide prediction request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching tide predictions from NOAA: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("NOAA tide predictions returned status %d", resp.StatusCode)
	}

	var noaaResp noaaPredictionResponse
	if err := json.NewDecoder(resp.Body).Decode(&noaaResp); err != nil {
		return nil, fmt.Errorf("decoding tide predictions: %w", err)
	}

	predictions := make([]models.TidePrediction, 0, len(noaaResp.Predictions))
	for _, p := range noaaResp.Predictions {
		t, err := time.ParseInLocation("2006-01-02 15:04", p.T, now.Location())
		if err != nil {
			slog.Warn("skipping unparseable tide prediction time", "raw", p.T, "err", err)
			continue
		}
		predictions = append(predictions, models.TidePrediction{
			Time: t,
			Type: p.Type,
		})
	}

	return predictions, nil
}

// FetchHourlyPredictions retrieves today's hourly tide height predictions from
// the configured NOAA tide station. These provide the granular data points
// needed to render a smooth tide chart curve.
func (c *Client) FetchHourlyPredictions(ctx context.Context) ([]models.TidePredictionPoint, error) {
	now := time.Now()
	today := now.Format("20060102")

	params := url.Values{
		"product":    {"predictions"},
		"datum":      {"MLLW"},
		"time_zone":  {"lst_ldt"},
		"units":      {"english"},
		"format":     {"json"},
		"interval":   {"h"},
		"station":    {c.tideStationID},
		"begin_date": {today},
		"end_date":   {today},
	}

	reqURL := fmt.Sprintf("%s?%s", baseURL, params.Encode())

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating hourly prediction request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching hourly predictions from NOAA: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("NOAA hourly predictions returned status %d", resp.StatusCode)
	}

	var noaaResp noaaPredictionResponse
	if err := json.NewDecoder(resp.Body).Decode(&noaaResp); err != nil {
		return nil, fmt.Errorf("decoding hourly predictions: %w", err)
	}

	points := make([]models.TidePredictionPoint, 0, len(noaaResp.Predictions))
	for _, p := range noaaResp.Predictions {
		t, err := time.ParseInLocation("2006-01-02 15:04", p.T, now.Location())
		if err != nil {
			slog.Warn("skipping unparseable hourly prediction time", "raw", p.T, "err", err)
			continue
		}

		var height float64
		if _, err := fmt.Sscanf(p.V, "%f", &height); err != nil {
			slog.Warn("skipping unparseable hourly prediction height", "raw", p.V, "err", err)
			continue
		}

		points = append(points, models.TidePredictionPoint{
			Time:   t,
			Height: height,
		})
	}

	return points, nil
}

// FetchWaterTemps retrieves the latest water temperature from each configured
// NOAA temperature station.
func (c *Client) FetchWaterTemps(ctx context.Context) ([]models.WaterTemp, error) {
	temps := make([]models.WaterTemp, 0, len(c.tempStationIDs))

	for _, stationID := range c.tempStationIDs {
		wt, err := c.fetchSingleTemp(ctx, stationID)
		if err != nil {
			slog.Error("failed to fetch water temp", "station", stationID, "err", err)
			continue
		}
		temps = append(temps, *wt)
	}

	if len(temps) == 0 {
		return nil, fmt.Errorf("failed to fetch water temperature from any station")
	}

	return temps, nil
}

func (c *Client) fetchSingleTemp(ctx context.Context, stationID string) (*models.WaterTemp, error) {
	params := url.Values{
		"product":   {"water_temperature"},
		"date":      {"latest"},
		"units":     {"english"},
		"time_zone": {"lst_ldt"},
		"format":    {"json"},
		"station":   {stationID},
	}

	reqURL := fmt.Sprintf("%s?%s", baseURL, params.Encode())

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating temp request for station %s: %w", stationID, err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching temp from station %s: %w", stationID, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("NOAA temp station %s returned status %d", stationID, resp.StatusCode)
	}

	var noaaResp noaaTempResponse
	if err := json.NewDecoder(resp.Body).Decode(&noaaResp); err != nil {
		return nil, fmt.Errorf("decoding temp for station %s: %w", stationID, err)
	}

	if len(noaaResp.Data) == 0 {
		return nil, fmt.Errorf("no temperature data returned for station %s", stationID)
	}

	var tempF float64
	if _, err := fmt.Sscanf(noaaResp.Data[0].V, "%f", &tempF); err != nil {
		return nil, fmt.Errorf("parsing temp value %q for station %s: %w", noaaResp.Data[0].V, stationID, err)
	}

	return &models.WaterTemp{
		StationID:   stationID,
		StationName: noaaResp.Metadata.Name,
		TempF:       tempF,
	}, nil
}

// GetTideInfo combines tide predictions and water temperature data into a
// single TideInfo response. It calculates tide direction (Rising/Dropping) and
// the percentage between the previous and next tide events.
func (c *Client) GetTideInfo(ctx context.Context) (*models.TideInfo, error) {
	predictions, err := c.FetchTidePredictions(ctx)
	if err != nil {
		return nil, fmt.Errorf("fetching tide predictions: %w", err)
	}

	temps, err := c.FetchWaterTemps(ctx)
	if err != nil {
		return nil, fmt.Errorf("fetching water temps: %w", err)
	}

	// Hourly predictions are non-critical — log and continue if they fail.
	hourly, err := c.FetchHourlyPredictions(ctx)
	if err != nil {
		slog.Warn("failed to fetch hourly predictions, continuing without them", "err", err)
	}

	now := time.Now()
	direction, pct := calculateTidePosition(predictions, now)

	var tempSum float64
	for _, wt := range temps {
		tempSum += wt.TempF
	}
	avg := tempSum / float64(len(temps))

	return &models.TideInfo{
		Direction:         direction,
		Percentage:        pct,
		WaterTempAvg:      avg,
		WaterTemps:        temps,
		Predictions:       predictions,
		HourlyPredictions: hourly,
		RetrievedAt:       now,
	}, nil
}

// calculateTidePosition determines the tide direction and percentage between
// the previous and next tide events relative to the given time.
//
// Direction: If the next event is High → "Rising"; if Low → "Dropping".
// Percentage: 0 at the last event, 100 at the next event, linearly interpolated.
func calculateTidePosition(predictions []models.TidePrediction, now time.Time) (direction string, percentage int) {
	if len(predictions) == 0 {
		return "Unknown", 0
	}

	// Find the previous and next tide events bracketing "now".
	var prev, next *models.TidePrediction
	for i := range predictions {
		if predictions[i].Time.After(now) {
			next = &predictions[i]
			if i > 0 {
				prev = &predictions[i-1]
			}
			break
		}
		prev = &predictions[i]
	}

	// Determine direction from the next tide event.
	if next == nil {
		// All predictions are in the past — use last known direction.
		if prev != nil && prev.Type == "H" {
			return "Dropping", 100
		}
		return "Rising", 100
	}

	if next.Type == "H" {
		direction = "Rising"
	} else {
		direction = "Dropping"
	}

	// Calculate percentage between prev and next.
	if prev == nil {
		// No previous event today — treat as 0%.
		return direction, 0
	}

	totalDuration := next.Time.Sub(prev.Time).Seconds()
	elapsed := now.Sub(prev.Time).Seconds()

	if totalDuration <= 0 {
		return direction, 0
	}

	pct := int(math.Round((elapsed / totalDuration) * 100))
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}

	return direction, pct
}
