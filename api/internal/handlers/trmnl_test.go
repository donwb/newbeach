package handlers

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/weather"
)

func TestPrettyRampName(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"ordinal avenue", "3RD AV", "3rd Ave"},
		{"named avenue", "FLAGLER AV", "Flagler Ave"},
		{"road", "CRAWFORD RD", "Crawford Rd"},
		{"beachway", "BEACHWAY AV", "Beachway Ave"},
		{"two digit ordinal", "27TH AV", "27th Ave"},
		{"boulevard", "DUNLAWTON BLVD", "Dunlawton Blvd"},
		{"already short word", "A ST", "A St"},
		{"empty", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, models.PrettyRampName(tt.in))
		})
	}
}

func TestFormatSince(t *testing.T) {
	now := time.Date(2026, 6, 10, 13, 9, 0, 0, eastern)

	tests := []struct {
		name string
		in   time.Time
		want string
	}{
		{"earlier today", time.Date(2026, 6, 10, 6, 2, 0, 0, eastern), "6:02 AM"},
		{"yesterday", time.Date(2026, 6, 9, 16, 11, 0, 0, eastern), "Yest 4:11 PM"},
		{"older", time.Date(2026, 6, 1, 8, 0, 0, 0, eastern), "Jun 1"},
		{"today in utc", time.Date(2026, 6, 10, 6+4, 2, 0, 0, time.UTC), "6:02 AM"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, formatSince(tt.in, now))
		})
	}
}

func TestSortRampsForDisplay(t *testing.T) {
	mk := func(name string) models.RampStatusWithSince {
		return models.RampStatusWithSince{RampStatus: models.RampStatus{RampName: name}}
	}

	ramps := []models.RampStatusWithSince{
		mk("27TH AV"), mk("BEACHWAY AV"), mk("CRAWFORD RD"), mk("ZULU AV"), mk("3RD AV"), mk("FLAGLER AV"), mk("ALPHA AV"),
	}
	sortRampsForDisplay(ramps)

	got := make([]string, len(ramps))
	for i, r := range ramps {
		got[i] = r.RampName
	}
	assert.Equal(t, []string{"3RD AV", "FLAGLER AV", "CRAWFORD RD", "BEACHWAY AV", "27TH AV", "ALPHA AV", "ZULU AV"}, got)
}

func hourlyPoints(dayStart time.Time, heights []float64) []models.TidePredictionPoint {
	points := make([]models.TidePredictionPoint, len(heights))
	for i, h := range heights {
		points[i] = models.TidePredictionPoint{Time: dayStart.Add(time.Duration(i) * time.Hour), Height: h}
	}
	return points
}

func TestNewTideChart(t *testing.T) {
	dayStart := time.Date(2026, 6, 10, 0, 0, 0, 0, eastern)

	t.Run("too few points", func(t *testing.T) {
		_, ok := newTideChart(hourlyPoints(dayStart, []float64{1.0}), dayStart)
		assert.False(t, ok)
	})

	t.Run("coordinates span the viewbox", func(t *testing.T) {
		heights := make([]float64, 24)
		for i := range heights {
			heights[i] = float64(i % 7)
		}
		tc, ok := newTideChart(hourlyPoints(dayStart, heights), dayStart)
		require.True(t, ok)

		assert.InDelta(t, 0, tc.xs[0], 0.01)
		assert.InDelta(t, 23.0/24.0*tideChartW, tc.xs[23], 0.01)
		for _, y := range tc.ys {
			assert.GreaterOrEqual(t, y, tideChartPadY)
			assert.LessOrEqual(t, y, tideChartH-tideChartPadY)
		}
	})

	t.Run("flat curve does not divide by zero", func(t *testing.T) {
		tc, ok := newTideChart(hourlyPoints(dayStart, []float64{2, 2, 2}), dayStart)
		require.True(t, ok)
		for _, y := range tc.ys {
			assert.False(t, y != y, "y must not be NaN")
		}
	})
}

func TestTideChartPaths(t *testing.T) {
	dayStart := time.Date(2026, 6, 10, 0, 0, 0, 0, eastern)
	tc, ok := newTideChart(hourlyPoints(dayStart, []float64{0, 2, 4, 2, 0}), dayStart)
	require.True(t, ok)

	curve, area := tc.paths()

	assert.True(t, strings.HasPrefix(curve, "M"), "curve starts with a move")
	assert.Contains(t, curve, "C", "curve uses cubic segments")
	assert.True(t, strings.HasPrefix(area, curve), "area extends the curve path")
	assert.True(t, strings.HasSuffix(area, "Z"), "area is a closed path")
}

func TestTideChartAt(t *testing.T) {
	dayStart := time.Date(2026, 6, 10, 0, 0, 0, 0, eastern)
	tc, ok := newTideChart(hourlyPoints(dayStart, []float64{0, 4, 0}), dayStart)
	require.True(t, ok)

	tests := []struct {
		name  string
		t     time.Time
		wantX float64
		wantY float64
	}{
		{"before range clamps to first", dayStart.Add(-time.Hour), tc.xs[0], tc.ys[0]},
		{"after range clamps to last", dayStart.Add(48 * time.Hour), tc.xs[2], tc.ys[2]},
		{"exact point", dayStart.Add(time.Hour), tc.xs[1], tc.ys[1]},
		{"midpoint interpolates", dayStart.Add(30 * time.Minute), (tc.xs[0] + tc.xs[1]) / 2, (tc.ys[0] + tc.ys[1]) / 2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			x, y := tc.at(tt.t)
			assert.InDelta(t, tt.wantX, x, 0.01)
			assert.InDelta(t, tt.wantY, y, 0.01)
		})
	}
}

func TestBuildTrmnlTide(t *testing.T) {
	now := time.Date(2026, 6, 10, 13, 9, 0, 0, eastern)
	dayStart := time.Date(2026, 6, 10, 0, 0, 0, 0, eastern)

	heights := make([]float64, 24)
	for i := range heights {
		heights[i] = float64((i * 13) % 5)
	}

	info := &models.TideInfo{
		Direction:    "Rising",
		Percentage:   24,
		WaterTempAvg: 78.6,
		Predictions: []models.TidePrediction{
			{Time: dayStart.Add(8*time.Hour + 21*time.Minute), Type: "L"},
			{Time: dayStart.Add(14*time.Hour + 41*time.Minute), Type: "H"},
			{Time: dayStart.Add(20*time.Hour + 55*time.Minute), Type: "L"},
		},
		HourlyPredictions: hourlyPoints(dayStart, heights),
	}

	tide := buildTrmnlTide(info, now)

	assert.Equal(t, "Rising", tide.Direction)
	assert.Equal(t, 24, tide.Percentage)
	assert.Equal(t, 79, tide.WaterTempF)
	assert.Equal(t, "2:41 PM", tide.NextHigh)
	assert.Equal(t, "8:55 PM", tide.NextLow, "next low is the evening one, not the morning one already past")
	assert.NotEmpty(t, tide.CurvePath)
	assert.NotEmpty(t, tide.AreaPath)
	assert.GreaterOrEqual(t, tide.NowX, 0)
	assert.LessOrEqual(t, tide.NowX, int(tideChartW))

	require.Len(t, tide.Events, 3)
	assert.Equal(t, "low", tide.Events[0].Type)
	assert.Equal(t, "8:21 AM", tide.Events[0].Time)
	assert.Equal(t, "high", tide.Events[1].Type)
	assert.True(t, tide.Events[0].X < tide.Events[1].X && tide.Events[1].X < tide.Events[2].X)
}

func TestBuildTrmnlTideWithoutHourly(t *testing.T) {
	now := time.Date(2026, 6, 10, 13, 9, 0, 0, eastern)
	info := &models.TideInfo{Direction: "Dropping", Percentage: 80, WaterTempAvg: 75.2}

	tide := buildTrmnlTide(info, now)

	assert.Empty(t, tide.CurvePath)
	assert.Empty(t, tide.AreaPath)
	assert.Equal(t, 75, tide.WaterTempF)
	assert.Empty(t, tide.Events)
}

func TestBuildTrmnlWeather(t *testing.T) {
	uv := 8
	info := &weather.WeatherInfo{
		Current: &weather.Conditions{
			Temperature:   81.7,
			WindSpeed:     "12 mph",
			WindDirection: "E",
			Description:   "Sunny",
			Humidity:      64,
			UVIndex:       &uv,
		},
		Forecast: []weather.Forecast{
			{Name: "This Afternoon", Temperature: 84, ShortDesc: "Sunny"},
			{Name: "Tonight", Temperature: 71, ShortDesc: "Mostly Clear"},
			{Name: "Thursday", Temperature: 84, ShortDesc: "Chance Showers"},
			{Name: "Thursday Night", Temperature: 72, ShortDesc: "Showers"},
		},
	}

	w := buildTrmnlWeather(info)

	require.NotNil(t, w)
	assert.Equal(t, 82, w.TempF)
	assert.Equal(t, "Sunny", w.Description)
	require.NotNil(t, w.UVIndex)
	assert.Equal(t, 8, *w.UVIndex)
	require.Len(t, w.Forecast, 3, "forecast is capped at three periods")
	assert.Equal(t, "This Afternoon", w.Forecast[0].Name)
}

func TestBuildTrmnlWeatherNilCurrent(t *testing.T) {
	assert.Nil(t, buildTrmnlWeather(nil))
	assert.Nil(t, buildTrmnlWeather(&weather.WeatherInfo{}))
}

func TestBuildTrmnlActivity(t *testing.T) {
	now := time.Date(2026, 6, 10, 13, 9, 0, 0, eastern)
	city := "NEW SMYRNA BEACH"

	mk := func(name string, recordedAt time.Time, entryCity string) models.RampHistoryEntry {
		return models.RampHistoryEntry{
			RampName:     name,
			AccessStatus: "CLOSED FOR HIGH TIDE",
			RecordedAt:   recordedAt,
			City:         entryCity,
		}
	}

	history := []models.RampHistoryEntry{
		mk("CRAWFORD RD", time.Date(2026, 6, 10, 12, 48, 0, 0, eastern), city),
		mk("27TH AV", time.Date(2026, 6, 10, 12, 30, 0, 0, eastern), "DAYTONA BEACH"),
		mk("FLAGLER AV", time.Date(2026, 6, 9, 18, 0, 0, 0, eastern), city),
		mk("BEACHWAY AV", time.Date(2026, 6, 10, 6, 2, 0, 0, eastern), city),
	}

	entries := buildTrmnlActivity(history, city, now)

	require.Len(t, entries, 2, "other cities and other days are filtered out")
	assert.Equal(t, "Crawford Rd", entries[0].Name)
	assert.Equal(t, "12:48 PM", entries[0].Time)
	assert.Equal(t, "Beachway Ave", entries[1].Name)
}

func TestBuildTrmnlActivityCap(t *testing.T) {
	now := time.Date(2026, 6, 10, 13, 9, 0, 0, eastern)
	city := "NEW SMYRNA BEACH"

	var history []models.RampHistoryEntry
	for i := 0; i < 10; i++ {
		history = append(history, models.RampHistoryEntry{
			RampName:     "3RD AV",
			AccessStatus: "OPEN",
			RecordedAt:   time.Date(2026, 6, 10, 8, i, 0, 0, eastern),
			City:         city,
		})
	}

	entries := buildTrmnlActivity(history, city, now)
	assert.Len(t, entries, 6)
}
