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

func TestFmtClock(t *testing.T) {
	assert.Equal(t, "1pm", fmtClock(et(1, 13, 0)))
	assert.Equal(t, "1:30pm", fmtClock(et(1, 13, 30)))
	assert.Equal(t, "11am", fmtClock(et(1, 11, 0)))
	assert.Equal(t, "12pm", fmtClock(et(1, 12, 0)))
	assert.Equal(t, "12:30am", fmtClock(et(1, 0, 30)))
}

func TestClockRange(t *testing.T) {
	assert.Equal(t, "1–4:30pm", clockRange(et(1, 13, 0), et(1, 16, 30)))
	assert.Equal(t, "11am–1:30pm", clockRange(et(1, 11, 0), et(1, 13, 30)))
	assert.Equal(t, "8–10:30am", clockRange(et(1, 8, 0), et(1, 10, 30)))
}

func TestRiskForPeak(t *testing.T) {
	rp := RampParams{ThresholdFt: 2.6, CloseRate: 0.2}
	assert.Equal(t, RiskLikely, riskForPeak(3.6, rp, hardOpenFt, hardCloseFt), "hard close rule")
	assert.Equal(t, RiskNone, riskForPeak(1.9, rp, hardOpenFt, hardCloseFt), "hard open rule")
	assert.Equal(t, RiskLikely, riskForPeak(2.95, rp, hardOpenFt, hardCloseFt), "above threshold band")
	assert.Equal(t, RiskPossible, riskForPeak(2.5, rp, hardOpenFt, hardCloseFt), "inside band")
	assert.Equal(t, RiskNone, riskForPeak(2.25, rp, hardOpenFt, hardCloseFt), "below band, low close rate")

	flipper := RampParams{ThresholdFt: 3.85, CloseRate: 0.42}
	assert.Equal(t, RiskPossible, riskForPeak(2.6, flipper, hardOpenFt, hardCloseFt), "mid-range flipper stays possible")
	assert.Equal(t, RiskNone, riskForPeak(2.2, flipper, hardOpenFt, hardCloseFt), "below action zone")
}

// A station with lower tidal amplitude (e.g. prod's 8721164 vs the analysis
// station 8721147) must not have the fallback hard rules squash learned
// signals — the learned percentile cutoffs take over.
func TestRiskForPeakScalesToStation(t *testing.T) {
	rp := RampParams{ThresholdFt: 1.6, CloseRate: 0.6} // learned on a low-amplitude station
	// With learned cutoffs for that station, a 1.95 peak is decisively above
	// the threshold band → likely, even though the 8721147-scale fallback
	// rule (≤2.0 → none) would have wrongly silenced it.
	assert.Equal(t, RiskLikely, riskForPeak(1.95, rp, 1.2, 2.8))
	assert.Equal(t, RiskNone, riskForPeak(1.1, rp, 1.2, 2.8), "below learned hard-open")
	assert.Equal(t, RiskLikely, riskForPeak(2.9, rp, 1.2, 2.8), "above learned hard-close")
}

func TestTrainLearnsHardCutoffs(t *testing.T) {
	// 50 peaks spread 1.0..3.45 → P05 ≈ 1.1, P97 ≈ 3.35.
	var peaks []models.TidePrediction
	for i := 0; i < 50; i++ {
		peaks = append(peaks, h(et(1+i%28, 13, 0).Add(time.Duration(i)*time.Minute), 1.0+float64(i)*0.05))
	}
	params := Train(map[string][]models.StatusEvent{}, peaks, et(28, 0, 0))
	assert.InDelta(t, 1.1, params.HardOpenFt, 0.11)
	assert.InDelta(t, 3.35, params.HardCloseFt, 0.11)
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

	// 3.4 ft peak: eager closer far above threshold — likely. Close time =
	// peak 15:30 − 120m lead = 13:30; reopen = 15:30 + 80m lag ≈ 17:00.
	eager := byID["NS-141"]
	assert.Equal(t, RiskLikely, eager.Risk)
	assert.Equal(t, "High-tide closure likely around 1:30pm", eager.Headline)
	assert.Equal(t, "Often back open by 5pm once the tide drops", eager.Detail)
	assert.Equal(t, "closure likely ~1:30pm", eager.Short)
	assert.Equal(t, "high", eager.Confidence)
	require.NotNil(t, eager.Window)
	// 120 lead + 45 pad before 15:30 → 12:45 floor → 12:30; 80 lag + 45
	// pad after → 17:35 ceil → 18:00.
	assert.Equal(t, et(16, 12, 30), eager.Window.Start.In(eastern))
	assert.Equal(t, "12:30–6pm", eager.Window.Label)

	// Beachway at 3.25+0.3 > 3.4 > 3.25-0.3 — inside the band, possible.
	tough := byID["NS-106"]
	assert.Equal(t, RiskPossible, tough.Risk)
	assert.Equal(t, "Could close around the 3:30pm high tide", tough.Headline)
	assert.Equal(t, "Depends on surf and sand · could just as well stay open", tough.Detail)
	assert.Equal(t, "could close ~3:30pm", tough.Short)

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
	// ~90m after (≈17:00), rounded to the half hour.
	assert.Equal(t, "often back open around 5pm", ro.Reopen.Label)

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
	require.NotNil(t, out.Schedule.ClosesAt)
	// Mid-December NSB sunset ~5:30 PM ET; schedule closes 15 min early and
	// the labels carry the approximate clock times.
	assert.Equal(t, 17, out.Schedule.ClosesAt.In(eastern).Hour())
	assert.Regexp(t, `^sunrise \(~\d{1,2}(:30)?am\)$`, out.Schedule.OpensLabel)
	assert.Regexp(t, `^sunset \(~\d{1,2}(:30)?pm\)$`, out.Schedule.ClosesLabel)
	assert.Equal(t, "Open for driving until "+out.Schedule.ClosesLabel, out.Ramps[0].Detail)
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

// The clock moving past a predicted close time must change the story: the
// ramp is visibly still open, so the outlook stops quoting a time in the
// past, softens as the peak goes by, and finally clears.
func TestBuildOutlookDecaysAsClockPasses(t *testing.T) {
	_, preds := afternoonScenario()
	ramps := []models.RampStatusWithSince{ramp(1, "NS-141", "OPEN")}

	// Peak 15:30, NS-141 lead 120 / lag 80 → close ~13:30, lag ends 16:50.

	// Before the learned close time: the clock time is a fair thing to quote.
	ahead := BuildOutlook(et(16, 12, 0), ramps, testParams(), preds).Ramps[0]
	assert.Equal(t, RiskLikely, ahead.Risk)
	assert.Equal(t, "High-tide closure likely around 1:30pm", ahead.Headline)
	assert.Equal(t, "closure likely ~1:30pm", ahead.Short)

	// Past it, still open: same risk, but no stale clock time in the copy.
	due := BuildOutlook(et(16, 14, 0), ramps, testParams(), preds).Ramps[0]
	assert.Equal(t, RiskLikely, due.Risk, "a late closure is still a closure")
	assert.Equal(t, "High-tide closure likely any time now", due.Headline)
	assert.Equal(t, "Often back open by 5pm once the tide drops", due.Detail)
	assert.Equal(t, "closure likely soon", due.Short)

	// Past the peak: the ramp beat this tide, so likely softens to possible.
	falling := BuildOutlook(et(16, 16, 0), ramps, testParams(), preds).Ramps[0]
	assert.Equal(t, RiskPossible, falling.Risk)
	assert.Equal(t, "Could still close while the tide drops", falling.Headline)
	assert.Equal(t, "could still close", falling.Short)

	// Past the learned lag: the peak stops counting.
	done := BuildOutlook(et(16, 17, 0), ramps, testParams(), preds).Ramps[0]
	assert.Equal(t, RiskNone, done.Risk)
	assert.Equal(t, "No tide trouble expected", done.Headline)
	assert.Empty(t, done.Short)
	assert.Nil(t, done.Window)
}

// A "possible" peak still ahead keeps quoting the high-tide time — that
// time has not passed, so there is nothing stale about it.
func TestBuildOutlookPossibleKeepsPeakTimeUntilItPasses(t *testing.T) {
	_, preds := afternoonScenario()
	ramps := []models.RampStatusWithSince{ramp(2, "NS-106", "OPEN")}

	ahead := BuildOutlook(et(16, 14, 30), ramps, testParams(), preds).Ramps[0]
	assert.Equal(t, RiskPossible, ahead.Risk)
	assert.Equal(t, "Could close around the 3:30pm high tide", ahead.Headline)

	// NS-106 lag is 53 min → the 15:30 peak stops counting at 16:23.
	past := BuildOutlook(et(16, 16, 30), ramps, testParams(), preds).Ramps[0]
	assert.Equal(t, RiskNone, past.Risk)
}
