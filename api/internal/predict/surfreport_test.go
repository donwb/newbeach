package predict

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/weather"
)

func fp(v float64) *float64 { return &v }

func TestSurfQuality(t *testing.T) {
	// Wind FROM: 90 = onshore (E), 270 = offshore (W), 0/180 = cross.
	tests := []struct {
		name    string
		height  float64
		period  *float64
		windDir *float64
		windMph *float64
		want    string
	}{
		{name: "flat", height: 1.0, period: fp(9), windDir: fp(270), windMph: fp(5), want: SurfFlat},
		{name: "flat beats wind", height: 1.2, windDir: fp(90), windMph: fp(20), want: SurfFlat},
		{name: "blown onshore", height: 3.0, period: fp(9), windDir: fp(90), windMph: fp(18), want: SurfBlown},
		{name: "onshore moderate is choppy", height: 3.0, period: fp(9), windDir: fp(90), windMph: fp(10), want: SurfChoppy},
		{name: "short period is choppy", height: 3.0, period: fp(5), windDir: fp(270), windMph: fp(5), want: SurfChoppy},
		{name: "small clean offshore", height: 2.0, period: fp(8), windDir: fp(270), windMph: fp(10), want: SurfCleanSmall},
		{name: "small clean no wind data", height: 2.8, period: fp(8), want: SurfCleanSmall},
		{name: "good chest high", height: 4.0, period: fp(9), windDir: fp(270), windMph: fp(10), want: SurfGood},
		{name: "good cross light", height: 4.0, period: fp(8), windDir: fp(180), windMph: fp(6), want: SurfGood},
		{name: "firing", height: 5.0, period: fp(11), windDir: fp(270), windMph: fp(6), want: SurfFiring},
		{name: "firing needs period", height: 5.0, period: fp(8), windDir: fp(270), windMph: fp(6), want: SurfGood},
		{name: "chest high no period defaults small-clean phrasing", height: 4.0, windDir: fp(270), windMph: fp(5), want: SurfCleanSmall},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := surfQuality(tt.height, tt.period, tt.windDir, tt.windMph)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestSurfHeightLabel(t *testing.T) {
	assert.Equal(t, "", surfHeightLabel(1.0))
	assert.Equal(t, "knee-high", surfHeightLabel(2.0))
	assert.Equal(t, "waist-high", surfHeightLabel(3.0))
	assert.Equal(t, "chest-high", surfHeightLabel(4.0))
	assert.Equal(t, "head-high", surfHeightLabel(5.5))
	assert.Equal(t, "overhead", surfHeightLabel(7.0))
}

func TestWindShore(t *testing.T) {
	assert.Equal(t, "onshore", windShore(90))
	assert.Equal(t, "onshore", windShore(60))
	assert.Equal(t, "offshore", windShore(270))
	assert.Equal(t, "offshore", windShore(300))
	assert.Equal(t, "cross", windShore(0))
	assert.Equal(t, "cross", windShore(180))
}

// surfOutlook builds a minimal Outlook carrying the given per-ramp risks.
func surfOutlook(risks ...RampOutlook) *Outlook {
	return &Outlook{Ramps: risks}
}

func freshWave(now time.Time, heightFt float64, periodS *float64) *models.WaveSample {
	return &models.WaveSample{Time: now.Add(-30 * time.Minute), HeightFt: heightFt, DominantPeriodS: periodS}
}

func offshoreCond() *weather.Conditions {
	return &weather.Conditions{WindDirDeg: fp(270), WindSpeedMph: fp(6)}
}

func TestBuildSurfReportComposesTideClause(t *testing.T) {
	now := time.Date(2026, 8, 22, 9, 0, 0, 0, eastern)
	windowStart := time.Date(2026, 8, 22, 12, 0, 0, 0, eastern)
	// The time the ramp's own line quotes (peak minus lead) — later than the
	// window's lower bound, and the one the surf clause must repeat.
	quoted := time.Date(2026, 8, 22, 13, 0, 0, 0, eastern)

	t.Run("good surf plus likely closure", func(t *testing.T) {
		out := surfOutlook(RampOutlook{Risk: RiskLikely, Reason: ReasonHighTide,
			Window: &Window{Start: windowStart}, quotedClose: &quoted})
		sr := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), nil)
		require.NotNil(t, sr)
		assert.Equal(t, SurfGood, sr.Quality)
		assert.Contains(t, sr.Line, "closure's possible around 1pm")
		assert.NotContains(t, sr.Line, "12pm", "must quote the ramp line's time, not the window start")
	})

	t.Run("blown surf suppresses tide clause", func(t *testing.T) {
		out := surfOutlook(RampOutlook{Risk: RiskLikely, Reason: ReasonHighTide, Window: &Window{Start: windowStart}})
		cond := &weather.Conditions{WindDirDeg: fp(90), WindSpeedMph: fp(20)}
		sr := BuildSurfReport(now, out, freshWave(now, 3.0, fp(9)), cond, nil)
		require.NotNil(t, sr)
		assert.Equal(t, SurfBlown, sr.Quality)
		assert.NotContains(t, sr.Line, "closure", "blown out + closure clause is noise")
	})

	t.Run("closed now beats window copy", func(t *testing.T) {
		out := surfOutlook(RampOutlook{Risk: RiskClosedNow, Reason: ReasonHighTide})
		sr := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), nil)
		require.NotNil(t, sr)
		assert.Contains(t, sr.Line, "tide-closed right now")
	})

	t.Run("no tide risk no clause", func(t *testing.T) {
		out := surfOutlook(RampOutlook{Risk: RiskScheduled, Reason: ReasonEndOfDay})
		sr := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), nil)
		require.NotNil(t, sr)
		assert.NotContains(t, sr.Line, "closure")
		assert.NotContains(t, sr.Line, "tide")
	})
}

func TestBuildSurfReportDegradation(t *testing.T) {
	now := time.Date(2026, 8, 22, 9, 0, 0, 0, eastern)
	out := surfOutlook()

	t.Run("elevated rip rides the field, not the prose", func(t *testing.T) {
		srf := &weather.SurfZone{RipCurrentRisk: "High"}
		sr := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), srf)
		require.NotNil(t, sr)
		assert.Equal(t, "High", sr.RipRisk)
		assert.NotContains(t, strings.ToLower(sr.Line), "rip")
	})

	t.Run("low rip stays out of the prose", func(t *testing.T) {
		srf := &weather.SurfZone{RipCurrentRisk: "Low"}
		sr := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), srf)
		require.NotNil(t, sr)
		assert.Equal(t, "Low", sr.RipRisk)
		assert.NotContains(t, strings.ToLower(sr.Line), "rip")
	})

	t.Run("no wind data still phrases", func(t *testing.T) {
		sr := BuildSurfReport(now, out, freshWave(now, 3.0, fp(9)), nil, nil)
		require.NotNil(t, sr)
		assert.NotEmpty(t, sr.Line)
		assert.Equal(t, "waist-high", sr.HeightLabel)
	})

	t.Run("stale wave with elevated rip is rip-only", func(t *testing.T) {
		stale := &models.WaveSample{Time: now.Add(-8 * time.Hour), HeightFt: 4.0}
		srf := &weather.SurfZone{RipCurrentRisk: "Moderate"}
		sr := BuildSurfReport(now, out, stale, nil, srf)
		require.NotNil(t, sr)
		assert.Empty(t, sr.Quality)
		assert.Contains(t, sr.Line, "rip current risk is moderate")
	})

	t.Run("stale wave and low rip is no report", func(t *testing.T) {
		stale := &models.WaveSample{Time: now.Add(-8 * time.Hour), HeightFt: 4.0}
		srf := &weather.SurfZone{RipCurrentRisk: "Low"}
		assert.Nil(t, BuildSurfReport(now, out, stale, nil, srf))
	})

	t.Run("nothing at all is no report", func(t *testing.T) {
		assert.Nil(t, BuildSurfReport(now, out, nil, nil, nil))
	})
}

func TestBuildSurfReportDeterministic(t *testing.T) {
	now := time.Date(2026, 8, 22, 9, 0, 0, 0, eastern)
	out := surfOutlook()
	srf := &weather.SurfZone{RipCurrentRisk: "Moderate"}
	a := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), srf)
	b := BuildSurfReport(now, out, freshWave(now, 4.0, fp(9)), offshoreCond(), srf)
	assert.Equal(t, a.Line, b.Line, "same inputs must produce the same string")
}
