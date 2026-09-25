// Command gen-levels-fixture is a throwaway generator for
// internal/predict/testdata/levels.json: hourly observed-minus-predicted
// water levels at the two CO-OPS gauges bracketing Volusia, covering the
// backtest history span, fetched live from NOAA.
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
	end := time.Date(2026, 9, 25, 0, 0, 0, 0, time.UTC)

	var all []models.WaterLevelSample
	for _, station := range []string{"8721604", "8720218"} {
		levels, err := client.FetchWaterLevelResiduals(ctx, station, start, end)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", station, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "%s: %d hourly samples\n", station, len(levels))
		all = append(all, levels...)
	}

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
