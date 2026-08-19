package weather

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"
)

// The NWS Surf Zone Forecast (product type SRF) is the official beach-day
// text product: rip current risk, surf height, water temperature, UV. It is
// issued about twice a day (roughly 07z and 15z). The rip current risk is
// relayed verbatim — this app never computes its own safety calls.

const (
	// srfTTL: how long a fetched product is served before refetching.
	srfTTL = 2 * time.Hour
	// srfMaxStale: a product older than this is not worth relaying — the
	// feature degrades to buoy-only copy rather than serving yesterday's
	// rip call.
	srfMaxStale = 24 * time.Hour
)

// SurfZone is the parsed first-day section of the Surf Zone Forecast for the
// configured zone. String fields hold the label's text verbatim (trailing
// period trimmed); empty means the line was absent.
type SurfZone struct {
	RipCurrentRisk string    // "Low" | "Moderate" | "High"
	SurfHeight     string    // e.g. "Around 2 feet"
	WaterTemp      string    // e.g. "In the lower 80s"
	UVIndex        string    // e.g. "Very High"
	IssuedAt       time.Time // product issuance time
}

// GetSurfZone returns the current parsed Surf Zone Forecast, cached per
// srfTTL and serving a stale copy through upstream failures up to
// srfMaxStale. Returns an error when nothing usable is available — callers
// degrade rather than fail.
func (c *Client) GetSurfZone(ctx context.Context) (*SurfZone, error) {
	c.mu.Lock()
	if c.srfCached != nil && c.now().Sub(c.srfFetchedAt) < srfTTL {
		sz := c.srfCached
		c.mu.Unlock()
		return sz, nil
	}
	c.mu.Unlock()

	sz, err := c.fetchSurfZone(ctx)
	if err != nil {
		c.mu.Lock()
		defer c.mu.Unlock()
		if c.srfCached != nil && c.now().Sub(c.srfCached.IssuedAt) < srfMaxStale {
			slog.Warn("serving stale surf zone forecast", "err", err)
			return c.srfCached, nil
		}
		return nil, err
	}
	if c.now().Sub(sz.IssuedAt) >= srfMaxStale {
		return nil, fmt.Errorf("surf zone forecast is stale (issued %s)", sz.IssuedAt)
	}

	c.mu.Lock()
	c.srfCached = sz
	c.srfFetchedAt = c.now()
	c.mu.Unlock()
	return sz, nil
}

// --- NWS product API shapes ---

type nwsProductListResponse struct {
	Graph []struct {
		ID           string `json:"id"`
		IssuanceTime string `json:"issuanceTime"`
	} `json:"@graph"`
}

type nwsProductResponse struct {
	IssuanceTime string `json:"issuanceTime"`
	ProductText  string `json:"productText"`
}

// fetchSurfZone pulls the latest SRF product and parses the configured zone.
func (c *Client) fetchSurfZone(ctx context.Context) (*SurfZone, error) {
	listURL := fmt.Sprintf("%s/products?type=SRF&office=%s&limit=1", c.baseURL, c.srfOffice)
	var list nwsProductListResponse
	if err := c.doJSON(ctx, listURL, &list); err != nil {
		return nil, fmt.Errorf("listing SRF products: %w", err)
	}
	if len(list.Graph) == 0 {
		return nil, fmt.Errorf("no SRF products for office %s", c.srfOffice)
	}

	var product nwsProductResponse
	productURL := fmt.Sprintf("%s/products/%s", c.baseURL, list.Graph[0].ID)
	if err := c.doJSON(ctx, productURL, &product); err != nil {
		return nil, fmt.Errorf("fetching SRF product: %w", err)
	}

	sz, err := parseSurfZone(product.ProductText, c.srfZone)
	if err != nil {
		return nil, fmt.Errorf("parsing SRF product: %w", err)
	}
	if issued, err := time.Parse(time.RFC3339, product.IssuanceTime); err == nil {
		sz.IssuedAt = issued
	}
	return sz, nil
}

// dottedLabelRe matches the product's rigid "Label....Value." lines, e.g.
// "Rip Current Risk*...........Moderate."
var dottedLabelRe = regexp.MustCompile(`^([A-Za-z ]+?)\*{0,2}\.{2,}(.+?)\s*$`)

// parseSurfZone extracts the first day section of the zone whose UGC header
// contains zoneID (e.g. "FLZ141"). Pure and deliberately defensive: any
// structural surprise is an error, and the caller degrades to buoy-only copy.
func parseSurfZone(productText, zoneID string) (*SurfZone, error) {
	// Zone sections are separated by "$$"; the one we want has the UGC code
	// in its header block.
	section := ""
	for _, part := range strings.Split(productText, "$$") {
		if strings.Contains(part, zoneID) {
			section = part
			break
		}
	}
	if section == "" {
		return nil, fmt.Errorf("zone %s not found in product", zoneID)
	}

	// First day block: from the first ".SOMETHING..." day header to the next
	// day header (or the section's end). Day headers look like
	// ".REST OF TODAY...", ".TODAY...", ".WEDNESDAY...".
	dayRe := regexp.MustCompile(`(?m)^\.([A-Z][A-Z ]+)\.\.\.`)
	headers := dayRe.FindAllStringIndex(section, -1)
	if len(headers) == 0 {
		return nil, fmt.Errorf("no day sections in zone %s", zoneID)
	}
	dayEnd := len(section)
	if len(headers) > 1 {
		dayEnd = headers[1][0]
	}
	day := section[headers[0][0]:dayEnd]

	sz := &SurfZone{}
	found := 0
	for _, line := range strings.Split(day, "\n") {
		m := dottedLabelRe.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		label := strings.TrimSpace(m[1])
		value := strings.TrimSuffix(strings.TrimSpace(m[2]), ".")
		switch label {
		case "Rip Current Risk":
			sz.RipCurrentRisk = value
			found++
		case "Surf Height":
			sz.SurfHeight = value
			found++
		case "Water Temperature":
			sz.WaterTemp = value
			found++
		case "UV Index":
			sz.UVIndex = value
			found++
		}
	}
	if found == 0 {
		return nil, fmt.Errorf("no recognized labels in zone %s first day section", zoneID)
	}
	return sz, nil
}
