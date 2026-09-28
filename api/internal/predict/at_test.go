package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

// June 10 2026 is a Wednesday; June 12 a Friday.

func TestBuildRampOutlookAtInsideWindow(t *testing.T) {
	now := et(10, 9, 0)
	at := et(12, 14, 0)
	// NS-141: threshold 2.1, lead 120, lag 80 → a 2.3 ft peak sits in the band.
	preds := []models.TidePrediction{h(et(11, 14, 0), 1.0), h(et(12, 14, 30), 2.3), h(et(13, 15, 0), 1.0)}

	res := BuildRampOutlookAt(now, at, ramp(1, "NS-141", "OPEN"), testParams(), preds, nil, nil, nil)

	assert.Equal(t, 2, res.DaysOut)
	assert.Equal(t, "Friday ~2pm", res.AtLabel)
	assert.Equal(t, RiskPossible, res.Outlook.Risk)
	assert.Equal(t, ReasonHighTide, res.Outlook.Reason)
	assert.Contains(t, res.Outlook.Headline, "Could close", "hedged, never a promise")
	require.NotNil(t, res.Outlook.Window)
	assert.Equal(t, RelationInside, res.Relation)
	require.NotNil(t, res.Schedule.OpensAt)
	assert.Equal(t, et(12, 8, 0), *res.Schedule.OpensAt, "the target day's frame, not today's")
	require.NotNil(t, res.Tide.NextPeakAt)
	assert.Equal(t, et(12, 14, 30), *res.Tide.NextPeakAt)
	assert.NotEmpty(t, res.Caveats, "a future day says it is tide-only")
}

func TestBuildRampOutlookAtBeforeOpen(t *testing.T) {
	now := et(10, 9, 0)
	at := et(11, 6, 0)
	preds := []models.TidePrediction{h(et(11, 14, 30), 1.5)}

	res := BuildRampOutlookAt(now, at, ramp(1, "NS-141", "OPEN"), testParams(), preds, nil, nil, nil)

	assert.Equal(t, RelationBeforeOpen, res.Relation)
	assert.Equal(t, RiskClosedNow, res.Outlook.Risk)
	assert.Equal(t, ReasonOvernight, res.Outlook.Reason)
	assert.Equal(t, "tomorrow ~6am", res.AtLabel)
	assert.Contains(t, res.Outlook.Detail, "opens around 8am")
}

func TestBuildRampOutlookAtAfterClose(t *testing.T) {
	now := et(10, 9, 0)
	at := et(12, 21, 0)
	preds := []models.TidePrediction{h(et(12, 14, 30), 2.3), h(et(13, 15, 0), 1.0)}

	res := BuildRampOutlookAt(now, at, ramp(1, "NS-141", "OPEN"), testParams(), preds, nil, nil, nil)

	assert.Equal(t, RelationAfterClose, res.Relation)
	// Replayed from the last minute of Friday's driving day, not rolled to
	// Saturday morning: the 2:30pm peak's lag has run out, so the story is
	// the day ending.
	assert.Equal(t, RiskScheduled, res.Outlook.Risk)
	assert.Equal(t, ReasonEndOfDay, res.Outlook.Reason)
	require.NotNil(t, res.Schedule.ClosesAt)
	assert.Equal(t, et(12, 19, 0), *res.Schedule.ClosesAt)
}

// The trap this file exists for: replaying BuildOutlook at a future instant
// loses the water-level anomaly (no fresh gauge sample near that clock).
// BuildRampOutlookAt adjusts the water with the real clock first, so high
// water today still raises a peak two days out.
func TestBuildRampOutlookAtKeepsSurgeOnFutureDays(t *testing.T) {
	now := et(10, 9, 0)
	at := et(12, 14, 0)
	params := testParams()
	params.Surge = &SurgeParams{BaselineFt: map[string]float64{"A": 0}}
	// NS-106: threshold 3.25, band 2.95–3.55, low close rate → 2.7 ft is a
	// quiet "none" on predicted water. +0.8 ft today decays to +0.45 two days
	// out → 3.15 ft, inside the band.
	preds := []models.TidePrediction{h(et(11, 14, 0), 2.7), h(et(12, 14, 30), 2.7), h(et(13, 15, 0), 2.7)}
	levels := flatLevels("A", now.Add(-14*time.Hour), now, 0.8)

	naive := BuildOutlook(at, []models.RampStatusWithSince{ramp(2, "NS-106", "OPEN")}, params, preds, nil, levels, nil)
	require.Len(t, naive.Ramps, 1)
	assert.NotEqual(t, RiskPossible, naive.Ramps[0].Risk, "the naive replay drops the anomaly")

	res := BuildRampOutlookAt(now, at, ramp(2, "NS-106", "OPEN"), params, preds, nil, levels, nil)
	assert.Equal(t, RiskPossible, res.Outlook.Risk, "the at path keeps it")
	require.NotNil(t, res.Surge)
	assert.InDelta(t, 0.8, res.Surge.AnomalyFt, 0.01)
	require.NotNil(t, res.Tide.NextPeakFt)
	assert.InDelta(t, 2.7, *res.Tide.NextPeakFt, 0.001, "tide context stays NOAA's own number")
}

func TestBuildRampOutlookAtReplaysClosedRampAsOpen(t *testing.T) {
	now := et(10, 9, 0)
	at := et(10, 14, 0)
	preds := []models.TidePrediction{h(et(10, 14, 30), 1.5), h(et(11, 15, 0), 1.5)}

	res := BuildRampOutlookAt(now, at, ramp(1, "NS-141", "CLOSED FOR HIGH TIDE"), testParams(), preds, nil, nil, nil)

	assert.Equal(t, 0, res.DaysOut)
	assert.Equal(t, "today ~2pm", res.AtLabel)
	assert.NotEqual(t, RiskClosedNow, res.Outlook.Risk, "today's status says nothing about 2pm")
	assert.Empty(t, res.Caveats, "today carries no future-day caveats")
}

func TestValidateHorizon(t *testing.T) {
	now := et(10, 15, 0)
	assert.NoError(t, validateHorizon(now, et(10, 9, 0)), "earlier today is allowed")
	assert.NoError(t, validateHorizon(now, et(17, 9, 0)), "a week out is allowed")
	assert.ErrorIs(t, validateHorizon(now, et(9, 23, 0)), ErrPastTime)
	assert.ErrorIs(t, validateHorizon(now, et(18, 9, 0)), ErrBeyondHorizon)
}

func TestDaysBetweenET(t *testing.T) {
	assert.Equal(t, 0, daysBetweenET(et(10, 9, 0), et(10, 23, 30)))
	assert.Equal(t, 1, daysBetweenET(et(10, 23, 0), et(11, 0, 30)))
	assert.Equal(t, 3, daysBetweenET(et(10, 9, 0), et(13, 9, 0)))
}

func TestRampDisplayName(t *testing.T) {
	short := "Flagler"
	r := ramp(1, "NS-141", "OPEN")
	r.RampName = "FLAGLER AV"
	assert.Equal(t, "Flagler Ave", RampDisplayName(r))
	r.ShortName = &short
	assert.Equal(t, "Flagler", RampDisplayName(r))
	assert.Equal(t, "NS-999", RampDisplayName(ramp(1, "NS-999", "OPEN")))
}

func TestBuildCityOutlookAt(t *testing.T) {
	now := et(10, 9, 0)
	at := et(12, 14, 0)
	ramps := []models.RampStatusWithSince{
		ramp(1, "NS-141", "OPEN"),
		ramp(2, "NS-106", "CLOSED FOR HIGH TIDE"),
		ramp(3, "NS-110", "OPEN"),
	}
	for i := range ramps {
		ramps[i].City = "NEW SMYRNA BEACH"
	}
	// 2.3 ft: inside NS-141's band (possible), below NS-106's (none), and
	// NS-110 is unlearned → county default.
	preds := []models.TidePrediction{h(et(11, 14, 0), 1.0), h(et(12, 14, 30), 2.3), h(et(13, 15, 0), 1.0)}

	res := BuildCityOutlookAt(now, at, ramps, testParams(), preds, nil, nil, nil)

	assert.Equal(t, "NEW SMYRNA BEACH", res.City)
	assert.Equal(t, "New Smyrna Beach", res.DisplayName)
	assert.Equal(t, "Friday ~2pm", res.AtLabel)
	assert.Equal(t, RelationOpenHours, res.Relation)
	assert.Equal(t, 3, res.RampCount)
	require.Len(t, res.Ramps, 3)
	assert.Equal(t, RiskPossible, res.Ramps[0].Risk, "NS-141 in its band")
	assert.Equal(t, RelationInside, res.Ramps[0].Relation)
	assert.NotEqual(t, RiskClosedNow, res.Ramps[1].Risk, "closed today says nothing about Friday")
	assert.Equal(t, 3, res.Counts[RiskPossible]+res.Counts[RiskNone]+res.Counts[RiskScheduled]+res.Counts[RiskLikely])
	require.NotNil(t, res.Verdict)
	assert.Equal(t, "NEW SMYRNA BEACH", res.Verdict.City)
	assert.NotEmpty(t, res.Verdict.Headline)
	assert.Contains(t, res.Caveats[len(res.Caveats)-1], "assumed open")

	before := BuildCityOutlookAt(now, et(12, 6, 0), ramps, testParams(), preds, nil, nil, nil)
	assert.Equal(t, RelationBeforeOpen, before.Relation)
	assert.Equal(t, 3, before.Counts[RiskClosedNow])

	after := BuildCityOutlookAt(now, et(12, 21, 0), ramps, testParams(), preds, nil, nil, nil)
	assert.Equal(t, RelationAfterClose, after.Relation)
}

func TestCityRamps(t *testing.T) {
	a := ramp(1, "NS-141", "OPEN")
	a.City = "NEW SMYRNA BEACH"
	b := ramp(2, "DB-041", "OPEN")
	b.City = "DAYTONA BEACH"
	assert.Len(t, cityRamps([]models.RampStatusWithSince{a, b}, "NEW SMYRNA BEACH"), 1)
	assert.Empty(t, cityRamps([]models.RampStatusWithSince{a, b}, "PONCE INLET"))
}
