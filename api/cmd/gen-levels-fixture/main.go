// Command gen-levels-fixture is a throwaway generator for
// internal/predict/testdata/levels.json: hourly observed-minus-predicted
// water levels at the two CO-OPS gauges bracketing Volusia, covering the
// backtest history span, fetched live from NOAA.
//
// Like gen-waves-fixture it extends rather than rebuilds: samples already in
// the checked-in fixture are kept verbatim (NOAA revises residuals after the
// fact — 133 old samples moved by 11/12 — and a rebuild would silently
// perturb every older backtest), and only samples past each gauge's last
// timestamp are appended.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
)

func main() {
	ctx := context.Background()
	client := noaa.NewClient("", nil)

	start := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(2026, 11, 12, 5, 0, 0, 0, time.UTC)

	var existing []models.WaterLevelSample
	if raw, err := os.ReadFile("internal/predict/testdata/levels.json"); err == nil {
		if err := json.Unmarshal(raw, &existing); err != nil {
			fmt.Fprintf(os.Stderr, "existing fixture: %v\n", err)
			os.Exit(1)
		}
	}
	last := map[string]time.Time{}
	for _, l := range existing {
		if l.Time.After(last[l.Station]) {
			last[l.Station] = l.Time
		}
	}

	var all []models.WaterLevelSample
	for _, station := range []string{"8721604", "8720218"} {
		from := start
		if t, ok := last[station]; ok {
			from = t.Add(time.Second)
		}
		levels, err := client.FetchWaterLevelResiduals(ctx, station, from, end)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", station, err)
			os.Exit(1)
		}
		kept := levels[:0]
		for _, l := range levels {
			if l.Time.After(last[station]) {
				kept = append(kept, l)
			}
		}
		fmt.Fprintf(os.Stderr, "%s: %d new hourly samples\n", station, len(kept))
		all = append(all, kept...)
	}
	// Existing samples first, verbatim; then each gauge's new tail.
	all = append(existing, all...)

	out, err := json.Marshal(all)
	if err != nil {
		fmt.Fprintf(os.Stderr, "marshal: %v\n", err)
		os.Exit(1)
	}
	if err := os.WriteFile("internal/predict/testdata/levels.json", out, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write: %v\n", err)
		os.Exit(1)
	}
}
