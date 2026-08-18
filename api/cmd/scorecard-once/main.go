// Command scorecard-once runs the prediction scorecard locally using data
// fetched from the deployed API (prod DB is unreachable off-network) and
// prints it as JSON. One-off local harness — read-only.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/conditions"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/predict"
)

const apiBase = "https://beach.donwb.com"

func main() {
	ctx := context.Background()

	eastern, err := time.LoadLocation("America/New_York")
	if err != nil {
		fail("loading tz: %v", err)
	}

	now := time.Now().In(eastern)
	date := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, eastern).AddDate(0, 0, -1)
	if len(os.Args) > 1 {
		date, err = time.ParseInLocation("2006-01-02", os.Args[1], eastern)
		if err != nil {
			fail("parsing date: %v", err)
		}
	}

	var ramps []models.RampStatusWithSince
	getJSON(ctx, apiBase+"/api/v2/ramps", "", &ramps)

	closureHeights := make(map[string]*float64, len(ramps))
	history := make(map[string][]models.StatusEvent, len(ramps))
	for _, r := range ramps {
		closureHeights[r.AccessID] = r.ClosureHeightFt

		var wrapped struct {
			History []models.RampHistoryEntry `json:"history"`
		}
		getJSON(ctx, fmt.Sprintf("%s/api/v2/ramps/%d/history?limit=5000", apiBase, r.ID), "", &wrapped)
		events := make([]models.StatusEvent, 0, len(wrapped.History))
		for _, e := range wrapped.History {
			events = append(events, models.StatusEvent{AccessStatus: e.AccessStatus, RecordedAt: e.RecordedAt})
		}
		sort.Slice(events, func(i, j int) bool { return events[i].RecordedAt.Before(events[j].RecordedAt) })
		history[r.AccessID] = events
	}

	// Retrain locally exactly like the nightly trainer: full-history hilo
	// span through Train(). Deterministic, so this reproduces the prod blob
	// without needing the admin endpoint.
	histStart := time.Now()
	for _, events := range history {
		if len(events) > 0 && events[0].RecordedAt.Before(histStart) {
			histStart = events[0].RecordedAt
		}
	}

	station := os.Getenv("NOAA_TIDE_STATION")
	if station == "" {
		station = "8721147"
	}
	noaaClient := noaa.NewClient(station, strings.Split("8721604,8720218", ","))
	preds, err := noaaClient.FetchTidePredictionsRange(ctx, histStart, time.Now().AddDate(0, 0, 1))
	if err != nil {
		fail("fetching tides: %v", err)
	}

	// Waves straight from NDBC — the prod DB (and its wave_observations
	// table) is unreachable off-network. Training needs the same full-span
	// series the prod trainer reads, so walk the archive months back to the
	// start of history plus the realtime2 window for the recent weeks.
	ndbcStation := os.Getenv("NDBC_STATION")
	if ndbcStation == "" {
		ndbcStation = "41113"
	}
	ndbc := conditions.NewNDBCClient(ndbcStation)
	waves, err := ndbc.FetchRealtimeWindow(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: fetching waves: %v (grading without sea state)\n", err)
	}
	month := time.Date(histStart.Year(), histStart.Month(), 1, 0, 0, 0, 0, time.UTC)
	thisMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	for ; month.Before(thisMonth); month = month.AddDate(0, 1, 0) {
		samples, found, err := ndbc.FetchArchiveMonth(ctx, month.Year(), month.Month())
		if err != nil || !found {
			fmt.Fprintf(os.Stderr, "warning: no wave archive for %s (err=%v)\n", month.Format("2006-01"), err)
			continue
		}
		waves = append(waves, samples...)
	}
	seen := make(map[time.Time]bool, len(waves))
	deduped := waves[:0]
	for _, s := range waves {
		if !seen[s.Time] {
			seen[s.Time] = true
			deduped = append(deduped, s)
		}
	}
	waves = deduped

	params := predict.Train(history, preds, waves, time.Now())
	sc := predict.BuildScorecard(date, history, closureHeights, params, preds, waves)
	out, err := json.MarshalIndent(sc, "", "  ")
	if err != nil {
		fail("marshaling: %v", err)
	}
	fmt.Println(string(out))
}

func getJSON(ctx context.Context, url, apiKey string, dst any) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		fail("building request %s: %v", url, err)
	}
	if apiKey != "" {
		req.Header.Set("X-Api-Key", apiKey)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fail("fetching %s: %v", url, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fail("fetching %s: status %d", url, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(dst); err != nil {
		fail("decoding %s: %v", url, err)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
