// Command gen-waves-fixture is a throwaway generator for
// internal/predict/testdata/waves.json: NDBC 41113 wave observations
// covering the backtest history span, fetched from the live archives.
//
// It extends rather than rebuilds: samples already in the checked-in fixture
// are kept verbatim (NDBC revises archives after the realtime window, so a
// rebuild would silently perturb every older backtest), and only samples
// past its last timestamp are appended. Run from api/ and redirect stdout
// over the fixture.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sort"
	"time"

	"github.com/donwb/beach/api/internal/conditions"
	"github.com/donwb/beach/api/internal/models"
)

func main() {
	ctx := context.Background()
	client := conditions.NewNDBCClient("41113")

	start := time.Date(2026, 3, 9, 0, 0, 0, 0, time.UTC)
	end := time.Date(2026, 9, 25, 4, 0, 0, 0, time.UTC)

	var existing []models.WaveSample
	if raw, err := os.ReadFile("internal/predict/testdata/waves.json"); err == nil {
		if err := json.Unmarshal(raw, &existing); err != nil {
			fmt.Fprintf(os.Stderr, "existing fixture: %v\n", err)
			os.Exit(1)
		}
	}
	if len(existing) > 0 {
		start = existing[len(existing)-1].Time.Add(time.Second)
	}

	var all []models.WaveSample
	for m := start.Month(); m <= time.August; m++ {
		samples, found, err := client.FetchArchiveMonth(ctx, 2026, m)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%v: %v\n", m, err)
			os.Exit(1)
		}
		if !found {
			fmt.Fprintf(os.Stderr, "%v: no archive\n", m)
			os.Exit(1)
		}
		all = append(all, samples...)
		fmt.Fprintf(os.Stderr, "%v: %d samples\n", m, len(samples))
	}
	recent, err := client.FetchRealtimeWindow(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "realtime: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "realtime: %d samples\n", len(recent))
	all = append(all, recent...)

	seen := map[time.Time]bool{}
	var out []models.WaveSample
	for _, s := range all {
		if s.Time.Before(start) || !s.Time.Before(end) || seen[s.Time] {
			continue
		}
		seen[s.Time] = true
		s.HeightFt = math.Round(s.HeightFt*100) / 100
		if s.DominantPeriodS != nil {
			d := math.Round(*s.DominantPeriodS*100) / 100
			s.DominantPeriodS = &d
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Time.Before(out[j].Time) })
	out = append(existing, out...)

	blob, err := json.Marshal(out)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(string(blob))
	fmt.Fprintf(os.Stderr, "total: %d samples %s -> %s\n", len(out),
		out[0].Time.Format(time.RFC3339), out[len(out)-1].Time.Format(time.RFC3339))
}
