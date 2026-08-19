// gen-nws-fixture fetches the land and marine NWS gridpoint documents and
// writes trimmed copies (only the properties internal/nwsfc decodes, no
// geometry) into internal/nwsfc/testdata. Run it from api/ to refresh the
// fixtures:
//
//	go run ./cmd/gen-nws-fixture
//
// Flags override the gridpoints and output directory.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

const userAgent = "(beach-ramp-status, github.com/donwb/beach)"

// keepProperties are the gridpoint series internal/nwsfc decodes; everything
// else is stripped to keep fixtures reviewable.
var keepProperties = []string{
	"updateTime",
	"temperature",
	"heatIndex",
	"probabilityOfPrecipitation",
	"probabilityOfThunder",
	"windSpeed",
	"windGust",
	"skyCover",
	"heatRisk",
	"hazards",
	"waveHeight",
	"wavePeriod",
}

func main() {
	baseURL := flag.String("base", "https://api.weather.gov", "NWS API base URL")
	landGrid := flag.String("land", "MLB/42,92", "land gridpoint (OFFICE/x,y)")
	marineGrid := flag.String("marine", "MLB/46,93", "marine gridpoint (OFFICE/x,y)")
	outDir := flag.String("out", "internal/nwsfc/testdata", "output directory")
	flag.Parse()

	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "creating %s: %v\n", *outDir, err)
		os.Exit(1)
	}

	for _, g := range []struct{ grid, file string }{
		{*landGrid, "land_gridpoint.json"},
		{*marineGrid, "marine_gridpoint.json"},
	} {
		path := filepath.Join(*outDir, g.file)
		if err := fetchTrimmed(*baseURL, g.grid, path); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", g.grid, err)
			os.Exit(1)
		}
		fmt.Printf("wrote %s from %s\n", path, g.grid)
	}
}

func fetchTrimmed(baseURL, grid, path string) error {
	url := fmt.Sprintf("%s/gridpoints/%s", baseURL, grid)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "application/geo+json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s returned status %d", url, resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var doc struct {
		Properties map[string]json.RawMessage `json:"properties"`
	}
	if err := json.Unmarshal(body, &doc); err != nil {
		return fmt.Errorf("decoding %s: %w", url, err)
	}

	trimmed := map[string]json.RawMessage{}
	for _, k := range keepProperties {
		if v, ok := doc.Properties[k]; ok {
			trimmed[k] = v
		}
	}

	out, err := json.MarshalIndent(map[string]any{"properties": trimmed}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o644)
}
