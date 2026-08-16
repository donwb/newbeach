package conditions

import (
	"bufio"
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const ndbcBaseURL = "https://www.ndbc.noaa.gov/data/realtime2"

// maxNDBCDataLines bounds how far down the realtime2 file we look for a row
// with wave data — observations are every 30 minutes, so 10 lines ≈ 5 hours.
const maxNDBCDataLines = 10

// WaveObservation is the latest wave reading from an NDBC buoy.
type WaveObservation struct {
	WaveHeightFt    float64
	DominantPeriodS *float64
	ObservedAt      time.Time
}

// NDBCClient fetches the latest observations from an NDBC buoy's realtime2
// text feed (free, no API key). Default station 41113 is the Ponce de Leon
// Inlet wave buoy.
type NDBCClient struct {
	httpClient *http.Client
	stationID  string
}

// NewNDBCClient creates a client for the given NDBC station ID.
func NewNDBCClient(stationID string) *NDBCClient {
	return &NDBCClient{
		httpClient: &http.Client{Timeout: 15 * time.Second},
		stationID:  stationID,
	}
}

// FetchLatestWaves retrieves the most recent observation row that includes
// wave height. Buoys report "MM" for missing fields, so rows are scanned
// newest-first until one carries a wave height.
func (c *NDBCClient) FetchLatestWaves(ctx context.Context) (*WaveObservation, error) {
	url := fmt.Sprintf("%s/%s.txt", ndbcBaseURL, c.stationID)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating NDBC request for station %s: %w", c.stationID, err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching NDBC data for station %s: %w", c.stationID, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("NDBC station %s returned status %d", c.stationID, resp.StatusCode)
	}

	obs, err := parseNDBCRealtime(bufio.NewScanner(resp.Body))
	if err != nil {
		return nil, fmt.Errorf("parsing NDBC data for station %s: %w", c.stationID, err)
	}
	return obs, nil
}

// parseNDBCRealtime reads the realtime2 fixed-column text format: two header
// lines (column names prefixed with '#', then units), followed by data rows
// newest-first. Returns the first row with a parseable WVHT.
func parseNDBCRealtime(scanner *bufio.Scanner) (*WaveObservation, error) {
	var columns []string
	dataLines := 0

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "#") {
			// First comment line holds the column names ("#YY MM DD ...").
			if columns == nil {
				columns = strings.Fields(strings.TrimPrefix(line, "#"))
			}
			continue
		}
		if columns == nil {
			return nil, fmt.Errorf("data row before header")
		}

		dataLines++
		if dataLines > maxNDBCDataLines {
			break
		}

		fields := strings.Fields(line)
		if len(fields) < len(columns) {
			continue
		}
		row := make(map[string]string, len(columns))
		for i, name := range columns {
			row[name] = fields[i]
		}

		wvhtM, ok := ndbcFloat(row["WVHT"])
		if !ok {
			continue
		}

		obs := &WaveObservation{WaveHeightFt: wvhtM * 3.28084}
		if dpd, ok := ndbcFloat(row["DPD"]); ok {
			obs.DominantPeriodS = &dpd
		}
		if t, err := time.Parse("2006 01 02 15 04",
			fmt.Sprintf("%s %s %s %s %s", row["YY"], row["MM"], row["DD"], row["hh"], row["mm"])); err == nil {
			obs.ObservedAt = t
		}
		return obs, nil
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading NDBC feed: %w", err)
	}
	return nil, fmt.Errorf("no rows with wave data in first %d observations", maxNDBCDataLines)
}

// ndbcFloat parses an NDBC field value, treating the "MM" missing marker as
// absent.
func ndbcFloat(s string) (float64, bool) {
	if s == "" || s == "MM" {
		return 0, false
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}
