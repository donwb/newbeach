package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func ramp(id int64, accessID, status string) models.RampStatusWithSince {
	return models.RampStatusWithSince{
		RampStatus: models.RampStatus{ID: id, AccessID: accessID, AccessStatus: status},
	}
}

// testParams: one eager closer, one tough ramp, one mid-range flipper.
func testParams() Params {
	return Params{
		Version: paramsVersion,
		Default: DefaultParams,
		Ramps: map[string]RampParams{
			"NS-141": {ThresholdFt: 2.1, Accuracy: 0.71, NClosures: 121, CloseRate: 0.67, LeadMin: 120, LagMin: 80},
			"NS-106": {ThresholdFt: 3.25, Accuracy: 0.76, NClosures: 47, CloseRate: 0.26, LeadMin: 94, LagMin: 53},
			"DB-041": {ThresholdFt: 3.85, Accuracy: 0.61, NClosures: 78, CloseRate: 0.42, LeadMin: 112, LagMin: 86},
		},
	}
}

func TestTimeBuckets(t *testing.T) {
	tests := []struct {
		hour int
		want string
	}{
		{5, "early morning"}, {9, "midmorning"}, {12, "midday"},
		{14, "midafternoon"}, {17, "late afternoon"}, {20, "evening"}, {23, "overnight"}, {2, "overnight"},
	}
	for _, tt := range tests {
		assert.Equal(t, tt.want, timeBucket(et(1, tt.hour, 0)), "hour %d", tt.hour)
	}
}

func TestWindowLabel(t *testing.T) {
	assert.Equal(t, "midafternoon", windowLabel(et(1, 13, 30), et(1, 15, 30)))
	assert.Equal(t, "midafternoon into late afternoon", windowLabel(et(1, 14, 0), et(1, 17, 30)))
}

func TestRiskForPeak(t *testing.T) {
	rp := RampParams{ThresholdFt: 2.6, CloseRate: 0.2}
	assert.Equal(t, RiskLikely, riskForPeak(3.6, rp), "hard close rule")
	assert.Equal(t, RiskNone, riskForPeak(1.9, rp), "hard open rule")
	assert.Equal(t, RiskLikely, riskForPeak(2.95, rp), "above threshold band")
	assert.Equal(t, RiskPossible, riskForPeak(2.5, rp), "inside band")
	assert.Equal(t, RiskNone, riskForPeak(2.25, rp), "below band, low close rate")

	flipper := RampParams{ThresholdFt: 3.85, CloseRate: 0.42}
	assert.Equal(t, RiskPossible, riskForPeak(2.6, flipper), "mid-range flipper stays possible")
	assert.Equal(t, RiskNone, riskForPeak(2.2, flipper), "below action zone")
}

// A turtle-season midafternoon: 3.4 ft peak at 3:30 PM ET.
func afternoonScenario() (time.Time, []models.TidePrediction) {
	now := et(16, 10, 0) // 2026-06-16 10:00 ET
	low1, high1 := 0.4, 3.4
	low2, high2 := 0.5, 3.2
	preds := []models.TidePrediction{
		{Time: et(16, 3, 0), Type: "H", Height: &high2},
		{Time: et(16, 9, 10), Type: "L", Height: &low1},
		{Time: et(16, 15, 30), Type: "H", Height: &high1},
		{Time: et(16, 21, 45), Type: "L", Height: &low2},
		{Time: et(17, 4, 0), Type: "H", Height: &high2},
	}
	return now, preds
}

func TestBuildOutlookTurtleSeasonRisk(t *testing.T) {
	now, preds := afternoonScenario()
	ramps := []models.RampStatusWithSince{
		ramp(1, "NS-141", "OPEN"),
		ramp(2, "NS-106", "OPEN"),
		ramp(3, "DB-041", "OPEN"),
	}

	out := BuildOutlook(now, ramps, testParams(), preds)

	assert.Equal(t, "turtle", out.Season)
	assert.Equal(t, "7pm", out.Schedule.ClosesLabel)
	require.NotNil(t, out.Tide.NextPeakFt)
	assert.InDelta(t, 3.4, *out.Tide.NextPeakFt, 0.001)
	require.Len(t, out.Ramps, 3)

	byID := map[string]RampOutlook{}
	for _, ro := range out.Ramps {
		byID[ro.AccessID] = ro
	}

	// 3.4 ft peak: eager closer far above threshold — likely.
	eager := byID["NS-141"]
	assert.Equal(t, RiskLikely, eager.Risk)
	assert.Equal(t, "High-tide closure likely midafternoon", eager.Headline)
	assert.Equal(t, "high", eager.Confidence)
	require.NotNil(t, eager.Window)
	assert.Equal(t, "Usually closes ahead of high tides like this one · often back open by late afternoon", eager.Detail)
	// 120 lead + 45 pad before 15:30 → 12:45 floor → 12:30.
	assert.Equal(t, et(16, 12, 30), eager.Window.Start.In(eastern))

	// Beachway at 3.25+0.3 > 3.4 > 3.25-0.3 — inside the band, possible.
	tough := byID["NS-106"]
	assert.Equal(t, RiskPossible, tough.Risk)
	assert.Equal(t, "Could close around the midafternoon high tide", tough.Headline)
	assert.Equal(t, "Depends on surf and sand · could just as well stay open", tough.Detail)

	// DB-041: 3.4 < 3.85-0.3 but close_rate 0.42 in the action zone — possible.
	flipper := byID["DB-041"]
	assert.Equal(t, RiskPossible, flipper.Risk)
}

func TestBuildOutlookQuietDay(t *testing.T) {
	now := et(16, 10, 0)
	low, high := 0.3, 1.8
	preds := []models.TidePrediction{
		{Time: et(16, 9, 0), Type: "L", Height: &low},
		{Time: et(16, 15, 0), Type: "H", Height: &high},
		{Time: et(16, 21, 0), Type: "L", Height: &low},
	}

	out := BuildOutlook(now, []models.RampStatusWithSince{ramp(1, "NS-141", "OPEN")}, testParams(), preds)
	ro := out.Ramps[0]
	assert.Equal(t, RiskNone, ro.Risk, "1.8 ft peak closes nothing, even the eager closer")
	assert.Equal(t, "No tide trouble expected", ro.Headline)
	assert.Equal(t, "Open for driving until 7pm", ro.Detail)
	assert.Nil(t, ro.Window)
}

func TestBuildOutlookClosedNow(t *testing.T) {
	now, preds := afternoonScenario()
	// Closed at 14:00 ET on the rising side of the 15:30 peak.
	closedRamp := ramp(1, "NS-141", "CLOSED FOR HIGH TIDE")
	since := et(16, 14, 0)
	closedRamp.StatusSince = &since

	out := BuildOutlook(et(16, 14, 30), []models.RampStatusWithSince{closedRamp}, testParams(), preds)
	ro := out.Ramps[0]
	assert.Equal(t, RiskClosedNow, ro.Risk)
	assert.Equal(t, "Closed for high tide", ro.Headline)
	require.NotNil(t, ro.Reopen)
	// Symmetric falling-limb crossing: closed 90m before peak → reopens
	// ~90m after (≈17:00, late afternoon).
	assert.Equal(t, "often back open by late afternoon", ro.Reopen.Label)

	_ = now
}

func TestBuildOutlookMetadataOverride(t *testing.T) {
	now, preds := afternoonScenario()
	r := ramp(1, "NS-141", "OPEN")
	override := 4.2 // operator says this ramp basically never closes
	r.ClosureHeightFt = &override

	out := BuildOutlook(now, []models.RampStatusWithSince{r}, testParams(), preds)
	assert.Equal(t, RiskNone, out.Ramps[0].Risk, "operator override beats learned threshold")
}

func TestBuildOutlookOffSeason(t *testing.T) {
	// 2026-12-16 10:00 ET — off-season, standard hours.
	now := time.Date(2026, 12, 16, 10, 0, 0, 0, eastern)
	low, high := 0.3, 1.8
	preds := []models.TidePrediction{
		{Time: now.Add(-2 * time.Hour), Type: "L", Height: &low},
		{Time: now.Add(3 * time.Hour), Type: "H", Height: &high},
	}

	out := BuildOutlook(now, []models.RampStatusWithSince{ramp(1, "NS-141", "OPEN")}, testParams(), preds)
	assert.Equal(t, "standard", out.Season)
	assert.Equal(t, "around sunset", out.Schedule.ClosesLabel)
	require.NotNil(t, out.Schedule.ClosesAt)
	// Mid-December NSB sunset ~5:30 PM ET; schedule closes 15 min early.
	assert.Equal(t, 17, out.Schedule.ClosesAt.In(eastern).Hour())
	assert.Equal(t, "Open for driving until around sunset", out.Ramps[0].Detail)
}

func TestReopenEstimateFallsBackToLowTide(t *testing.T) {
	// Closure logged on the falling side (feed lag): falling-limb estimator
	// declines, fallback = next low + 90 min.
	low, high := 0.4, 3.0
	preds := []models.TidePrediction{
		{Time: et(16, 9, 0), Type: "H", Height: &high},
		{Time: et(16, 15, 0), Type: "L", Height: &low},
		{Time: et(16, 21, 0), Type: "H", Height: &high},
	}
	closedAt := et(16, 10, 0) // after the high — falling side
	reopen := reopenEstimate(preds, closedAt, et(16, 10, 30))
	assert.Equal(t, et(16, 16, 30), reopen.In(eastern), "next low 15:00 + 90m")
}
