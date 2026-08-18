package conditions

import (
	"bufio"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

const (
	ndbcRealtimeURL   = "https://www.ndbc.noaa.gov/data/realtime2"
	ndbcStdmetURL     = "https://www.ndbc.noaa.gov/data/stdmet"
	ndbcHistoricalURL = "https://www.ndbc.noaa.gov/data/historical/stdmet"
)

// maxNDBCDataLines bounds how far down the realtime2 file we look for a row
// with wave data — observations are every 30 minutes, so 10 lines ≈ 5 hours.
const maxNDBCDataLines = 10

// errNDBCNotFound marks a 404 from NDBC — the file for that period doesn't
// exist (yet, or anymore), which is an expected condition for archive URLs.
var errNDBCNotFound = errors.New("NDBC file not found")

// WaveObservation is the latest wave reading from an NDBC buoy.
type WaveObservation struct {
	WaveHeightFt    float64
	DominantPeriodS *float64
	ObservedAt      time.Time
}

// NDBCClient fetches observations from an NDBC buoy's free text feeds: the
// realtime2 file (last ~45 days, newest-first) and the stdmet monthly/yearly
// archives. Default station 41113 is the Ponce de Leon Inlet wave buoy.
type NDBCClient struct {
	httpClient *http.Client
	stationID  string

	// Base URLs, overridable in tests.
	realtimeURL   string
	stdmetURL     string
	historicalURL string
}

// NewNDBCClient creates a client for the given NDBC station ID.
func NewNDBCClient(stationID string) *NDBCClient {
	return &NDBCClient{
		httpClient:    &http.Client{Timeout: 30 * time.Second},
		stationID:     stationID,
		realtimeURL:   ndbcRealtimeURL,
		stdmetURL:     ndbcStdmetURL,
		historicalURL: ndbcHistoricalURL,
	}
}

// FetchLatestWaves retrieves the most recent observation row that includes
// wave height. Buoys report "MM" for missing fields, so rows are scanned
// newest-first until one carries a wave height.
func (c *NDBCClient) FetchLatestWaves(ctx context.Context) (*WaveObservation, error) {
	url := fmt.Sprintf("%s/%s.txt", c.realtimeURL, c.stationID)
	samples, err := c.fetchTable(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("fetching NDBC data for station %s: %w", c.stationID, err)
	}
	obs, err := firstWaveSample(samples)
	if err != nil {
		return nil, fmt.Errorf("parsing NDBC data for station %s: %w", c.stationID, err)
	}
	return obs, nil
}

// FetchRealtimeWindow returns every wave-bearing observation in the station's
// realtime2 file — the buoy's last ~45 days — in file order (newest first).
func (c *NDBCClient) FetchRealtimeWindow(ctx context.Context) ([]models.WaveSample, error) {
	url := fmt.Sprintf("%s/%s.txt", c.realtimeURL, c.stationID)
	samples, err := c.fetchTable(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("fetching NDBC realtime window for station %s: %w", c.stationID, err)
	}
	return samples, nil
}

// FetchArchiveMonth returns the station's wave observations for one calendar
// month from NDBC's stdmet archives, trying each place the file can live:
// the month directory as gzip (completed months of the current year), the
// month directory as plain text (the most recent completed month), then the
// whole-year historical archive (where everything lands after January).
// found is false when every candidate 404s — an expected state for months
// NDBC hasn't archived, not an error.
func (c *NDBCClient) FetchArchiveMonth(ctx context.Context, year int, month time.Month) (samples []models.WaveSample, found bool, err error) {
	monthDir := month.String()[:3]
	candidates := []string{
		fmt.Sprintf("%s/%s/%s%d%d.txt.gz", c.stdmetURL, monthDir, c.stationID, int(month), year),
		fmt.Sprintf("%s/%s/%s.txt", c.stdmetURL, monthDir, c.stationID),
		fmt.Sprintf("%s/%sh%d.txt.gz", c.historicalURL, c.stationID, year),
	}

	start := time.Date(year, month, 1, 0, 0, 0, 0, time.UTC)
	end := start.AddDate(0, 1, 0)

	for _, url := range candidates {
		all, err := c.fetchTable(ctx, url)
		if errors.Is(err, errNDBCNotFound) {
			continue
		}
		if err != nil {
			return nil, false, fmt.Errorf("fetching NDBC archive for station %s: %w", c.stationID, err)
		}
		// The plain month file and the year archive can carry other months;
		// filter down so the caller always gets exactly the month asked for.
		var monthly []models.WaveSample
		for _, s := range all {
			if !s.Time.Before(start) && s.Time.Before(end) {
				monthly = append(monthly, s)
			}
		}
		if len(monthly) == 0 {
			// The file exists but has nothing for this month (e.g. the plain
			// month file is a different month than asked). Try the next home.
			continue
		}
		return monthly, true, nil
	}
	return nil, false, nil
}

// fetchTable GETs an NDBC stdmet-format text file (gzip-compressed when the
// URL says so) and parses every wave-bearing row.
func (c *NDBCClient) fetchTable(ctx context.Context, url string) ([]models.WaveSample, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating NDBC request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("%s: %w", url, errNDBCNotFound)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s returned status %d", url, resp.StatusCode)
	}

	var body io.Reader = resp.Body
	if strings.HasSuffix(url, ".gz") {
		gz, err := gzip.NewReader(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("decompressing %s: %w", url, err)
		}
		defer gz.Close()
		body = gz
	}

	samples, err := parseNDBCTable(bufio.NewScanner(body))
	if err != nil {
		return nil, fmt.Errorf("parsing %s: %w", url, err)
	}
	return samples, nil
}

// parseNDBCRealtime reads the realtime2 text format and returns the first
// (newest) row with a parseable WVHT, looking at most maxNDBCDataLines rows
// down. Kept as the logger's entry point; the table parser does the work.
func parseNDBCRealtime(scanner *bufio.Scanner) (*WaveObservation, error) {
	samples, err := parseNDBCTableLimit(scanner, maxNDBCDataLines)
	if err != nil {
		return nil, err
	}
	return firstWaveSample(samples)
}

func firstWaveSample(samples []models.WaveSample) (*WaveObservation, error) {
	if len(samples) == 0 {
		return nil, fmt.Errorf("no rows with wave data")
	}
	s := samples[0]
	return &WaveObservation{
		WaveHeightFt:    s.HeightFt,
		DominantPeriodS: s.DominantPeriodS,
		ObservedAt:      s.Time,
	}, nil
}

// parseNDBCTable parses any NDBC stdmet-format table — realtime2 or archive:
// two '#'-prefixed header lines (column names, then units), whitespace-
// delimited data rows, "MM" for missing values. Returns every row carrying a
// WVHT and a parseable timestamp, in file order (realtime2 is newest-first,
// archives oldest-first). Rows without wave data are skipped, not errors.
func parseNDBCTable(scanner *bufio.Scanner) ([]models.WaveSample, error) {
	return parseNDBCTableLimit(scanner, 0)
}

// parseNDBCTableLimit is parseNDBCTable bounded to the first maxRows data
// rows (0 = unlimited).
func parseNDBCTableLimit(scanner *bufio.Scanner, maxRows int) ([]models.WaveSample, error) {
	var columns []string
	var samples []models.WaveSample
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
		if maxRows > 0 && dataLines > maxRows {
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

		t, ok := ndbcTimestamp(row)
		if !ok {
			continue
		}

		s := models.WaveSample{Time: t, HeightFt: wvhtM * 3.28084}
		if dpd, ok := ndbcFloat(row["DPD"]); ok {
			s.DominantPeriodS = &dpd
		}
		samples = append(samples, s)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading NDBC feed: %w", err)
	}
	return samples, nil
}

// ndbcTimestamp assembles a row's UTC observation time. Modern files carry a
// minutes column ("mm"); older archives are hourly with only "YY MM DD hh",
// and some name the year column "YYYY" — handle all of them.
func ndbcTimestamp(row map[string]string) (time.Time, bool) {
	year := row["YY"]
	if year == "" {
		year = row["YYYY"]
	}
	minute := row["mm"]
	if minute == "" {
		minute = "00"
	}
	t, err := time.Parse("2006 01 02 15 04",
		fmt.Sprintf("%s %s %s %s %s", year, row["MM"], row["DD"], row["hh"], minute))
	if err != nil {
		return time.Time{}, false
	}
	return t, true
}

// ndbcFloat parses an NDBC field value, treating the "MM" missing marker as
// absent. Archives use "99.00"/"999.0"-style sentinels for missing values;
// wave heights that large are physically impossible, so they read as absent
// too.
func ndbcFloat(s string) (float64, bool) {
	if s == "" || s == "MM" {
		return 0, false
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, false
	}
	if v >= 99 {
		return 0, false
	}
	return v, true
}
