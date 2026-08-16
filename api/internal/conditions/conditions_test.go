package conditions

import (
	"bufio"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func TestParseMph(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want *float64
	}{
		{"simple", "12 mph", ptr(12.0)},
		{"range takes max", "10 to 15 mph", ptr(15.0)},
		{"zero", "0 mph", ptr(0.0)},
		{"empty", "", nil},
		{"garbage", "breezy", nil},
		{"decimal", "7.5 mph", ptr(7.5)},
		{"whitespace", "  8 mph  ", ptr(8.0)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ParseMph(tt.in)
			if tt.want == nil {
				assert.Nil(t, got)
				return
			}
			require.NotNil(t, got)
			assert.InDelta(t, *tt.want, *got, 0.001)
		})
	}
}

// ndbcFixture mirrors the live realtime2 format for station 41113, including
// MM missing markers and a newest row without wave data.
const ndbcFixture = `#YY  MM DD hh mm WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP  VIS PTDY  TIDE
#yr  mo dy hr mn degT m/s  m/s     m   sec   sec degT   hPa  degC  degC  degC  nmi  hPa    ft
2026 08 16 12 56  MM   MM   MM    MM    MM   MM   MM     MM    MM  28.3    MM   MM   MM    MM
2026 08 16 12 26  MM   MM   MM   0.5     8   4.7 115     MM    MM  28.3    MM   MM   MM    MM
2026 08 16 11 56  MM   MM   MM   0.6     9   4.8 115     MM    MM  28.3    MM   MM   MM    MM
`

func TestParseNDBCRealtime(t *testing.T) {
	t.Run("skips rows without wave data", func(t *testing.T) {
		obs, err := parseNDBCRealtime(bufio.NewScanner(strings.NewReader(ndbcFixture)))
		require.NoError(t, err)
		// 0.5 m -> 1.64 ft, from the newest row that has WVHT.
		assert.InDelta(t, 1.64, obs.WaveHeightFt, 0.01)
		require.NotNil(t, obs.DominantPeriodS)
		assert.InDelta(t, 8.0, *obs.DominantPeriodS, 0.001)
		assert.Equal(t, time.Date(2026, 8, 16, 12, 26, 0, 0, time.UTC), obs.ObservedAt)
	})

	t.Run("all rows missing waves", func(t *testing.T) {
		fixture := `#YY  MM DD hh mm WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP  VIS PTDY  TIDE
#yr  mo dy hr mn degT m/s  m/s     m   sec   sec degT   hPa  degC  degC  degC  nmi  hPa    ft
2026 08 16 12 56  MM   MM   MM    MM    MM   MM   MM     MM    MM  28.3    MM   MM   MM    MM
`
		_, err := parseNDBCRealtime(bufio.NewScanner(strings.NewReader(fixture)))
		assert.Error(t, err)
	})

	t.Run("empty feed", func(t *testing.T) {
		_, err := parseNDBCRealtime(bufio.NewScanner(strings.NewReader("")))
		assert.Error(t, err)
	})
}

func TestInterpolateHeight(t *testing.T) {
	base := time.Date(2026, 8, 16, 10, 0, 0, 0, time.UTC)
	points := []models.TidePredictionPoint{
		{Time: base, Height: 1.0},
		{Time: base.Add(time.Hour), Height: 2.0},
		{Time: base.Add(2 * time.Hour), Height: 1.5},
	}

	tests := []struct {
		name   string
		at     time.Time
		want   float64
		wantOK bool
	}{
		{"midpoint", base.Add(30 * time.Minute), 1.5, true},
		{"exact point", base.Add(time.Hour), 2.0, true},
		{"second segment", base.Add(90 * time.Minute), 1.75, true},
		{"before series", base.Add(-time.Minute), 0, false},
		{"after series", base.Add(3 * time.Hour), 0, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := interpolateHeight(points, tt.at)
			assert.Equal(t, tt.wantOK, ok)
			if tt.wantOK {
				assert.InDelta(t, tt.want, got, 0.001)
			}
		})
	}
}

func ptr(f float64) *float64 { return &f }
