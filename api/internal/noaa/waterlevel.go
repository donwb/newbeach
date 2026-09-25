package noaa

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// maxWaterLevelSpan is NOAA's per-request limit for 6-minute water_level
// and predictions data.
const maxWaterLevelSpan = 31 * 24 * time.Hour

// minSamplesPerHour is how many of an hour's ten 6-minute pairs must be
// present for the hour to produce a residual.
const minSamplesPerHour = 5

// recentLevelsTTL caches the serve-time series. Gauges report every six
// minutes, but the anomaly is a 12-hour mean — ten minutes of staleness is
// invisible, and the outlook and weekend services share one fetch.
const recentLevelsTTL = 10 * time.Minute

// recentLevelsSpan covers yesterday's peaks (the persistence prior labels
// them on effective water) plus the engine's 12-hour trailing window.
const recentLevelsSpan = 48 * time.Hour

type noaaSeriesResponse struct {
	Data []struct {
		T string `json:"t"`
		V string `json:"v"`
	} `json:"data"`
	Predictions []struct {
		T string `json:"t"`
		V string `json:"v"`
	} `json:"predictions"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

// levelsCache holds the last serve-time fetch.
type levelsCache struct {
	mu      sync.Mutex
	key     string
	levels  []models.WaterLevelSample
	expires time.Time
}

// RecentWaterLevels returns the last recentLevelsSpan of hourly residuals
// for each station, cached for recentLevelsTTL. A station that fails is
// skipped (the engine averages whichever gauges report); only all stations
// failing is an error.
func (c *Client) RecentWaterLevels(ctx context.Context, stations []string) ([]models.WaterLevelSample, error) {
	key := strings.Join(stations, ",")
	c.levels.mu.Lock()
	if c.levels.key == key && time.Now().Before(c.levels.expires) {
		levels := c.levels.levels
		c.levels.mu.Unlock()
		return levels, nil
	}
	c.levels.mu.Unlock()

	end := time.Now()
	var all []models.WaterLevelSample
	var errs []string
	for _, st := range stations {
		levels, err := c.FetchWaterLevelResiduals(ctx, st, end.Add(-recentLevelsSpan), end)
		if err != nil {
			errs = append(errs, err.Error())
			continue
		}
		all = append(all, levels...)
	}
	if len(all) == 0 && len(errs) > 0 {
		return nil, fmt.Errorf("fetching water levels: %s", strings.Join(errs, "; "))
	}

	c.levels.mu.Lock()
	c.levels.key, c.levels.levels, c.levels.expires = key, all, time.Now().Add(recentLevelsTTL)
	c.levels.mu.Unlock()
	return all, nil
}

// FetchWaterLevelResiduals returns hourly observed-minus-predicted water
// levels for one CO-OPS gauge over [begin, end], chunked to NOAA's 31-day
// request limit. Hours with too few 6-minute pairs are dropped.
func (c *Client) FetchWaterLevelResiduals(ctx context.Context, station string, begin, end time.Time) ([]models.WaterLevelSample, error) {
	var out []models.WaterLevelSample
	// Hour-aligned chunks keep every clock hour inside one request.
	for from := begin.UTC().Truncate(time.Hour); from.Before(end); from = from.Add(maxWaterLevelSpan) {
		to := from.Add(maxWaterLevelSpan)
		if to.After(end) {
			to = end
		}
		obs, err := c.fetchSeries(ctx, station, "water_level", from, to)
		if err != nil {
			return nil, fmt.Errorf("station %s water_level: %w", station, err)
		}
		pred, err := c.fetchSeries(ctx, station, "predictions", from, to)
		if err != nil {
			return nil, fmt.Errorf("station %s predictions: %w", station, err)
		}
		out = append(out, hourlyResiduals(station, obs, pred)...)
	}
	// Adjacent chunks share their boundary stamp, which can surface the
	// same hour twice.
	return dedupeHours(out), nil
}

// fetchSeries pulls one 6-minute product in GMT, MLLW (the datum cancels in
// the residual; it only has to match between the two products).
func (c *Client) fetchSeries(ctx context.Context, station, product string, begin, end time.Time) (map[time.Time]float64, error) {
	params := url.Values{
		"product":    {product},
		"datum":      {"MLLW"},
		"time_zone":  {"gmt"},
		"units":      {"english"},
		"format":     {"json"},
		"station":    {station},
		"begin_date": {begin.UTC().Format("20060102 15:04")},
		"end_date":   {end.UTC().Format("20060102 15:04")},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s?%s", baseURL, params.Encode()), nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("requesting: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	var raw noaaSeriesResponse
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, fmt.Errorf("decoding: %w", err)
	}
	return seriesFromResponse(raw)
}

// seriesFromResponse maps either product's payload to time → feet. NOAA
// reports "no data in range" as an error body; that is an empty series, not
// a failure (a gauge outage shouldn't sink a months-long training fetch).
func seriesFromResponse(raw noaaSeriesResponse) (map[time.Time]float64, error) {
	rows := raw.Data
	if len(rows) == 0 {
		rows = raw.Predictions
	}
	if len(rows) == 0 && raw.Error != nil && !strings.Contains(raw.Error.Message, "No data was found") {
		return nil, fmt.Errorf("NOAA: %s", strings.TrimSpace(raw.Error.Message))
	}
	out := make(map[time.Time]float64, len(rows))
	for _, r := range rows {
		t, err := time.Parse("2006-01-02 15:04", r.T)
		if err != nil {
			continue
		}
		v, err := strconv.ParseFloat(strings.TrimSpace(r.V), 64)
		if err != nil {
			continue
		}
		out[t.UTC()] = v
	}
	return out, nil
}

// hourlyResiduals pairs observations with predictions at the same 6-minute
// stamps and averages each clock hour's differences. The sample is stamped
// at the hour's end, so a trailing window read at t only ever includes
// water that had already been observed by t.
func hourlyResiduals(station string, obs, pred map[time.Time]float64) []models.WaterLevelSample {
	sums := map[time.Time]float64{}
	counts := map[time.Time]int{}
	for t, o := range obs {
		p, ok := pred[t]
		if !ok {
			continue
		}
		h := t.Truncate(time.Hour)
		sums[h] += o - p
		counts[h]++
	}
	out := make([]models.WaterLevelSample, 0, len(sums))
	for h, n := range counts {
		if n < minSamplesPerHour {
			continue
		}
		out = append(out, models.WaterLevelSample{
			Station:    station,
			Time:       h.Add(time.Hour),
			ResidualFt: math.Round(sums[h]/float64(n)*1000) / 1000,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Time.Before(out[j].Time) })
	return out
}

// dedupeHours keeps one sample per hour, the later chunk's.
func dedupeHours(levels []models.WaterLevelSample) []models.WaterLevelSample {
	idx := map[time.Time]int{}
	var out []models.WaterLevelSample
	for _, l := range levels {
		if i, ok := idx[l.Time]; ok {
			out[i] = l
			continue
		}
		idx[l.Time] = len(out)
		out = append(out, l)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Time.Before(out[j].Time) })
	return out
}
