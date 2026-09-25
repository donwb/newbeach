// Command gen-county-fixture is a throwaway generator for the county-wide
// backtest fixtures in internal/predict/testdata: every ramp's status history
// (history_county.json) and hilo predictions at the production tide station
// (hilo_8721164.json), fetched from the deployed API and NOAA. Run from api/.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
)

const (
	apiBase = "https://beach.donwb.com"
	station = "8721164"
)

type fixtureEvent struct {
	S string `json:"s"`
	T string `json:"t"`
}

func main() {
	ctx := context.Background()
	end := time.Date(2026, 9, 25, 4, 0, 0, 0, time.UTC) // midnight ET, 9/25

	var ramps []models.RampStatusWithSince
	getJSON(apiBase+"/api/v2/ramps", &ramps)

	out := map[string][]fixtureEvent{}
	for _, r := range ramps {
		var wrapped struct {
			History []models.RampHistoryEntry `json:"history"`
		}
		getJSON(fmt.Sprintf("%s/api/v2/ramps/%d/history?limit=5000", apiBase, r.ID), &wrapped)
		sort.Slice(wrapped.History, func(i, j int) bool { return wrapped.History[i].RecordedAt.Before(wrapped.History[j].RecordedAt) })
		for _, e := range wrapped.History {
			if e.RecordedAt.Before(end) {
				out[r.AccessID] = append(out[r.AccessID], fixtureEvent{S: e.AccessStatus, T: e.RecordedAt.UTC().Format(time.RFC3339Nano)})
			}
		}
		fmt.Fprintf(os.Stderr, "%s: %d events\n", r.AccessID, len(out[r.AccessID]))
	}
	write("internal/predict/testdata/history_county.json", out)

	preds, err := noaa.NewClient(station, nil).FetchTidePredictionsRange(ctx,
		time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC), time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC))
	if err != nil {
		fail("hilo: %v", err)
	}
	type hiloRow struct {
		T    string `json:"t"`
		V    string `json:"v"`
		Type string `json:"type"`
	}
	eastern, _ := time.LoadLocation("America/New_York")
	rows := make([]hiloRow, 0, len(preds))
	for _, p := range preds {
		if p.Height != nil {
			rows = append(rows, hiloRow{T: p.Time.In(eastern).Format("2006-01-02 15:04"), V: fmt.Sprintf("%.3f", *p.Height), Type: p.Type})
		}
	}
	fmt.Fprintf(os.Stderr, "hilo %s: %d extremes\n", station, len(rows))
	write("internal/predict/testdata/hilo_"+station+".json", rows)
}

func getJSON(url string, dst any) {
	resp, err := http.Get(url)
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

func write(path string, v any) {
	blob, err := json.Marshal(v)
	if err != nil {
		fail("marshal %s: %v", path, err)
	}
	if err := os.WriteFile(path, blob, 0o644); err != nil {
		fail("write %s: %v", path, err)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
