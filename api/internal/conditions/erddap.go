package conditions

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// erddapBaseURL is NOAA CoastWatch's ERDDAP mirror of the NDBC standard
// meteorological data. It exists here because www.ndbc.noaa.gov hard-blocks
// datacenter IPs (403 for any user agent from DigitalOcean egress — verified
// 2026-08-18), so in production every direct NDBC fetch fails and this
// mirror is the path that actually works. It lags the buoy by roughly one
// 30-minute observation cycle and carries the full multi-year history.
//
// NDBC_ERDDAP_URL overrides it: coastwatch ALSO tarpits the app's own egress
// IP (headers never arrive), so prod points at the cam-relay droplet's Caddy,
// which proxies /erddap/* through an IP coastwatch still likes.
const erddapBaseURL = "https://coastwatch.pfeg.noaa.gov/erddap/tabledap/cwwcNDBCMet.json"

// fetchERDDAPWaves returns the station's wave observations in [start, end]
// from the ERDDAP mirror, ascending, rows without wave height skipped.
func (c *NDBCClient) fetchERDDAPWaves(ctx context.Context, start, end time.Time) ([]models.WaveSample, error) {
	query := fmt.Sprintf(`station,time,wvht,dpd&station=%%22%s%%22&time%%3E=%s&time%%3C=%s`,
		c.stationID,
		url.QueryEscape(start.UTC().Format(time.RFC3339)),
		url.QueryEscape(end.UTC().Format(time.RFC3339)))
	reqURL := c.erddapURL + "?" + query

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating ERDDAP request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching ERDDAP waves: %w", err)
	}
	defer resp.Body.Close()

	// ERDDAP answers 404 with an error document when the constraint matches
	// nothing — treat that as an empty result, not a failure.
	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ERDDAP returned status %d", resp.StatusCode)
	}

	var payload struct {
		Table struct {
			ColumnNames []string            `json:"columnNames"`
			Rows        [][]json.RawMessage `json:"rows"`
		} `json:"table"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("decoding ERDDAP response: %w", err)
	}

	col := map[string]int{}
	for i, name := range payload.Table.ColumnNames {
		col[name] = i
	}
	timeIdx, timeOK := col["time"]
	wvhtIdx, wvhtOK := col["wvht"]
	dpdIdx, dpdOK := col["dpd"]
	if !timeOK || !wvhtOK {
		return nil, fmt.Errorf("ERDDAP response missing time/wvht columns")
	}

	var samples []models.WaveSample
	for _, row := range payload.Table.Rows {
		var ts string
		if err := json.Unmarshal(row[timeIdx], &ts); err != nil {
			continue
		}
		t, err := time.Parse(time.RFC3339, ts)
		if err != nil {
			continue
		}
		var wvhtM *float64
		if err := json.Unmarshal(row[wvhtIdx], &wvhtM); err != nil || wvhtM == nil {
			continue
		}
		s := models.WaveSample{Time: t, HeightFt: *wvhtM * 3.28084}
		if dpdOK {
			var dpd *float64
			if err := json.Unmarshal(row[dpdIdx], &dpd); err == nil && dpd != nil {
				s.DominantPeriodS = dpd
			}
		}
		samples = append(samples, s)
	}
	return samples, nil
}
