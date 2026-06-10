package handlers

import (
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/noaa"
	"github.com/donwb/beach/api/internal/weather"
)

var eastern *time.Location

func init() {
	var err error
	eastern, err = time.LoadLocation("America/New_York")
	if err != nil {
		panic(fmt.Sprintf("failed to load America/New_York timezone: %v", err))
	}
}

// Tide chart geometry. The template renders the curve in an SVG with this
// viewBox; all coordinates in the payload are expressed in this space.
const (
	tideChartW    = 1000.0
	tideChartH    = 260.0
	tideChartPadY = 34.0
)

// trmnlRamp is one ramp row, pre-formatted for the TRMNL Liquid template.
type trmnlRamp struct {
	Name              string `json:"name"`
	AccessStatus      string `json:"access_status"`
	AccessStatusShort string `json:"access_status_short"`
	StatusCategory    string `json:"status_category"`
	StatusSince       string `json:"status_since,omitempty"`
}

// trmnlTideEvent is a high or low tide marker positioned on the chart.
type trmnlTideEvent struct {
	Type string `json:"type"` // "high" or "low"
	Time string `json:"time"` // "2:41 PM"
	X    int    `json:"x"`    // x coordinate in the chart viewBox
}

// trmnlTide carries tide state plus server-rendered SVG path data, so the
// Liquid template never has to do curve math.
type trmnlTide struct {
	Direction  string           `json:"direction"`
	Percentage int              `json:"percentage"`
	WaterTempF int              `json:"water_temp_f"`
	CurvePath  string           `json:"curve_path"`
	AreaPath   string           `json:"area_path"`
	NowX       int              `json:"now_x"`
	NowY       int              `json:"now_y"`
	Events     []trmnlTideEvent `json:"events"`
	NextHigh   string           `json:"next_high,omitempty"`
	NextLow    string           `json:"next_low,omitempty"`
}

// trmnlForecastPeriod is a single abbreviated NWS forecast period.
type trmnlForecastPeriod struct {
	Name  string `json:"name"`
	TempF int    `json:"temp_f"`
	Short string `json:"short"`
}

// trmnlWeather is the current-conditions summary plus a short forecast.
type trmnlWeather struct {
	TempF       int                   `json:"temp_f"`
	Description string                `json:"description"`
	WindSpeed   string                `json:"wind_speed"`
	WindDir     string                `json:"wind_direction"`
	Humidity    int                   `json:"humidity"`
	UVIndex     *int                  `json:"uv_index,omitempty"`
	Forecast    []trmnlForecastPeriod `json:"forecast"`
}

// trmnlActivityEntry is one line in the "today's activity" feed.
type trmnlActivityEntry struct {
	Time   string `json:"time"`
	Name   string `json:"name"`
	Status string `json:"status"`
}

// trmnlResponse is the full aggregate payload for the TRMNL X plugin.
// Tide and weather are omitted (null) when their upstream fetch fails so a
// partial dashboard still renders.
type trmnlResponse struct {
	LocalTime string               `json:"local_time"`
	LocalDate string               `json:"local_date"`
	Ramps     []trmnlRamp          `json:"ramps"`
	Tide      *trmnlTide           `json:"tide,omitempty"`
	Weather   *trmnlWeather        `json:"weather,omitempty"`
	Activity  []trmnlActivityEntry `json:"activity"`
}

// HandleV2Trmnl returns the aggregate dashboard payload for the TRMNL X
// private plugin: ramps with since-times, tide chart data, weather, and
// today's status changes — all pre-formatted for a near-logic-free template.
// GET /api/v2/trmnl?city=NEW+SMYRNA+BEACH
func HandleV2Trmnl(pool *pgxpool.Pool, noaaClient *noaa.Client, weatherClient *weather.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		city := c.QueryParam("city")
		if city == "" {
			city = "NEW SMYRNA BEACH"
		}

		now := time.Now().In(eastern)

		ramps, err := database.GetRampsWithStatusSince(ctx, pool, city)
		if err != nil {
			slog.Error("querying ramps for trmnl", "city", city, "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{
				"error": "failed to query ramps",
			})
		}
		sortRampsForDisplay(ramps)

		resp := trmnlResponse{
			LocalTime: formatClock(now),
			LocalDate: now.Format("Mon, Jan 2"),
			Ramps:     make([]trmnlRamp, 0, len(ramps)),
			Activity:  []trmnlActivityEntry{},
		}

		for _, r := range ramps {
			tr := trmnlRamp{
				Name:              prettyRampName(r.RampName),
				AccessStatus:      r.AccessStatus,
				AccessStatusShort: models.StatusToShort(r.AccessStatus),
				StatusCategory:    r.StatusCategory,
			}
			if r.StatusSince != nil {
				tr.StatusSince = formatSince(*r.StatusSince, now)
			}
			resp.Ramps = append(resp.Ramps, tr)
		}

		// Tide and weather are non-critical — log and render without them.
		if tideInfo, err := noaaClient.GetTideInfo(ctx); err != nil {
			slog.Warn("fetching tide info for trmnl, continuing without tides", "err", err)
		} else {
			resp.Tide = buildTrmnlTide(tideInfo, now)
		}

		if weatherInfo, err := weatherClient.GetWeather(ctx); err != nil {
			slog.Warn("fetching weather for trmnl, continuing without weather", "err", err)
		} else {
			resp.Weather = buildTrmnlWeather(weatherInfo)
		}

		if history, err := database.GetRecentHistory(ctx, pool, 50); err != nil {
			slog.Warn("querying recent history for trmnl, continuing without activity", "err", err)
		} else {
			resp.Activity = buildTrmnlActivity(history, city, now)
		}

		return c.JSON(http.StatusOK, resp)
	}
}

// rampDisplayOrder is the fixed north-to-south presentation order for the New
// Smyrna Beach ramps (see REQUIREMENTS.md §12.2). Ramps not listed sort after
// these, alphabetically.
var rampDisplayOrder = map[string]int{
	"3RD AV":      0,
	"FLAGLER AV":  1,
	"CRAWFORD RD": 2,
	"BEACHWAY AV": 3,
	"27TH AV":     4,
}

func sortRampsForDisplay(ramps []models.RampStatusWithSince) {
	sort.SliceStable(ramps, func(i, j int) bool {
		oi, iok := rampDisplayOrder[ramps[i].RampName]
		oj, jok := rampDisplayOrder[ramps[j].RampName]
		switch {
		case iok && jok:
			return oi < oj
		case iok:
			return true
		case jok:
			return false
		default:
			return ramps[i].RampName < ramps[j].RampName
		}
	})
}

// prettyRampName converts a GIS ramp name like "3RD AV" or "CRAWFORD RD" to a
// display name like "3rd Ave" or "Crawford Rd".
func prettyRampName(name string) string {
	words := strings.Fields(name)
	for i, w := range words {
		switch w {
		case "AV", "AVE":
			words[i] = "Ave"
		case "RD":
			words[i] = "Rd"
		case "ST":
			words[i] = "St"
		case "BLVD":
			words[i] = "Blvd"
		case "DR":
			words[i] = "Dr"
		case "LN":
			words[i] = "Ln"
		case "CT":
			words[i] = "Ct"
		default:
			if len(w) > 0 && unicode.IsDigit(rune(w[0])) {
				// Ordinals: "3RD" → "3rd", "27TH" → "27th".
				words[i] = strings.ToLower(w)
			} else {
				words[i] = strings.ToUpper(w[:1]) + strings.ToLower(w[1:])
			}
		}
	}
	return strings.Join(words, " ")
}

func formatClock(t time.Time) string {
	return t.In(eastern).Format("3:04 PM")
}

// formatSince renders the time a status took effect relative to "now":
// a clock time for today, "Yest 4:11 PM" for yesterday, "Jun 8" otherwise.
func formatSince(t, now time.Time) string {
	t = t.In(eastern)
	now = now.In(eastern)
	ty, tm, td := t.Date()
	ny, nm, nd := now.Date()
	if ty == ny && tm == nm && td == nd {
		return formatClock(t)
	}
	yest := now.AddDate(0, 0, -1)
	yy, ym, yd := yest.Date()
	if ty == yy && tm == ym && td == yd {
		return "Yest " + formatClock(t)
	}
	return t.Format("Jan 2")
}

// tideChart maps today's hourly tide predictions into chart viewBox space.
type tideChart struct {
	points   []models.TidePredictionPoint
	dayStart time.Time
	xs, ys   []float64
}

// newTideChart builds the coordinate mapping. Returns false when there are too
// few points to draw a curve.
func newTideChart(points []models.TidePredictionPoint, dayStart time.Time) (*tideChart, bool) {
	if len(points) < 2 {
		return nil, false
	}

	minH, maxH := points[0].Height, points[0].Height
	for _, p := range points {
		if p.Height < minH {
			minH = p.Height
		}
		if p.Height > maxH {
			maxH = p.Height
		}
	}
	span := maxH - minH
	if span == 0 {
		span = 1
	}

	tc := &tideChart{
		points:   points,
		dayStart: dayStart,
		xs:       make([]float64, len(points)),
		ys:       make([]float64, len(points)),
	}
	for i, p := range points {
		tc.xs[i] = timeToChartX(p.Time, dayStart)
		tc.ys[i] = tideChartPadY + (1-(p.Height-minH)/span)*(tideChartH-2*tideChartPadY)
	}
	return tc, true
}

// timeToChartX maps a time to an x coordinate across the 24-hour viewBox.
func timeToChartX(t, dayStart time.Time) float64 {
	frac := t.Sub(dayStart).Minutes() / (24 * 60)
	if frac < 0 {
		frac = 0
	}
	if frac > 1 {
		frac = 1
	}
	return frac * tideChartW
}

// paths renders the curve as a Catmull-Rom-smoothed cubic Bézier path, plus a
// closed copy for the shaded area under the curve.
func (tc *tideChart) paths() (curve, area string) {
	n := len(tc.points)
	at := func(i int) (float64, float64) {
		if i < 0 {
			i = 0
		}
		if i > n-1 {
			i = n - 1
		}
		return tc.xs[i], tc.ys[i]
	}

	var b strings.Builder
	fmt.Fprintf(&b, "M%.1f,%.1f", tc.xs[0], tc.ys[0])
	for i := 0; i < n-1; i++ {
		x0, y0 := at(i - 1)
		x1, y1 := at(i)
		x2, y2 := at(i + 1)
		x3, y3 := at(i + 2)
		c1x, c1y := x1+(x2-x0)/6, y1+(y2-y0)/6
		c2x, c2y := x2-(x3-x1)/6, y2-(y3-y1)/6
		fmt.Fprintf(&b, " C%.1f,%.1f %.1f,%.1f %.1f,%.1f", c1x, c1y, c2x, c2y, x2, y2)
	}
	curve = b.String()
	area = fmt.Sprintf("%s L%.1f,%.1f L%.1f,%.1f Z", curve, tc.xs[n-1], tideChartH, tc.xs[0], tideChartH)
	return curve, area
}

// at returns the chart coordinates for an arbitrary time, linearly
// interpolating height between the bracketing hourly points.
func (tc *tideChart) at(t time.Time) (x, y float64) {
	n := len(tc.points)
	if !t.After(tc.points[0].Time) {
		return tc.xs[0], tc.ys[0]
	}
	if !t.Before(tc.points[n-1].Time) {
		return tc.xs[n-1], tc.ys[n-1]
	}
	for i := 0; i < n-1; i++ {
		a, b := tc.points[i], tc.points[i+1]
		if t.Before(a.Time) || t.After(b.Time) {
			continue
		}
		total := b.Time.Sub(a.Time).Seconds()
		if total <= 0 {
			return tc.xs[i], tc.ys[i]
		}
		frac := t.Sub(a.Time).Seconds() / total
		return tc.xs[i] + frac*(tc.xs[i+1]-tc.xs[i]), tc.ys[i] + frac*(tc.ys[i+1]-tc.ys[i])
	}
	return tc.xs[n-1], tc.ys[n-1]
}

// buildTrmnlTide assembles the tide section of the payload, including the
// pre-rendered SVG chart paths. The curve is omitted (empty paths) when hourly
// predictions are unavailable.
func buildTrmnlTide(info *models.TideInfo, now time.Time) *trmnlTide {
	t := &trmnlTide{
		Direction:  info.Direction,
		Percentage: info.Percentage,
		WaterTempF: int(info.WaterTempAvg + 0.5),
		Events:     []trmnlTideEvent{},
	}

	dayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, eastern)

	for _, p := range info.Predictions {
		ev := trmnlTideEvent{
			Type: "low",
			Time: formatClock(p.Time),
			X:    int(timeToChartX(p.Time, dayStart) + 0.5),
		}
		if p.Type == "H" {
			ev.Type = "high"
		}
		t.Events = append(t.Events, ev)

		if p.Time.After(now) {
			if p.Type == "H" && t.NextHigh == "" {
				t.NextHigh = formatClock(p.Time)
			}
			if p.Type == "L" && t.NextLow == "" {
				t.NextLow = formatClock(p.Time)
			}
		}
	}

	if tc, ok := newTideChart(info.HourlyPredictions, dayStart); ok {
		t.CurvePath, t.AreaPath = tc.paths()
		x, y := tc.at(now)
		t.NowX, t.NowY = int(x+0.5), int(y+0.5)
	}

	return t
}

// buildTrmnlWeather assembles the weather section: rounded current conditions
// plus up to three abbreviated forecast periods.
func buildTrmnlWeather(info *weather.WeatherInfo) *trmnlWeather {
	if info == nil || info.Current == nil {
		return nil
	}

	w := &trmnlWeather{
		TempF:       int(info.Current.Temperature + 0.5),
		Description: info.Current.Description,
		WindSpeed:   info.Current.WindSpeed,
		WindDir:     info.Current.WindDirection,
		Humidity:    info.Current.Humidity,
		UVIndex:     info.Current.UVIndex,
		Forecast:    []trmnlForecastPeriod{},
	}

	for _, p := range info.Forecast {
		if len(w.Forecast) == 3 {
			break
		}
		w.Forecast = append(w.Forecast, trmnlForecastPeriod{
			Name:  p.Name,
			TempF: p.Temperature,
			Short: p.ShortDesc,
		})
	}

	return w
}

// buildTrmnlActivity filters recent history down to today's changes for the
// given city, newest first, capped at six entries.
func buildTrmnlActivity(history []models.RampHistoryEntry, city string, now time.Time) []trmnlActivityEntry {
	entries := []trmnlActivityEntry{}
	ny, nm, nd := now.In(eastern).Date()

	for _, h := range history {
		if len(entries) == 6 {
			break
		}
		if h.City != city {
			continue
		}
		t := h.RecordedAt.In(eastern)
		hy, hm, hd := t.Date()
		if hy != ny || hm != nm || hd != nd {
			continue
		}
		entries = append(entries, trmnlActivityEntry{
			Time:   formatClock(t),
			Name:   prettyRampName(h.RampName),
			Status: h.AccessStatus,
		})
	}

	return entries
}
