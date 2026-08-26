package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

// scorecardScenario: June 16, two daytime peaks (3.4 ft at 15:30, plus an
// overnight peak that must be ignored) and a quiet neighboring day.
func scorecardPreds() []models.TidePrediction {
	low1, low2 := 0.4, 0.5
	big, small, overnight := 3.4, 2.5, 3.6
	return []models.TidePrediction{
		{Time: et(15, 14, 45), Type: "H", Height: &small},   // previous day
		{Time: et(16, 3, 0), Type: "H", Height: &overnight}, // overnight — excluded
		{Time: et(16, 9, 10), Type: "L", Height: &low1},
		{Time: et(16, 15, 30), Type: "H", Height: &big},
		{Time: et(16, 21, 45), Type: "L", Height: &low2},
		{Time: et(17, 16, 15), Type: "H", Height: &small}, // next day
	}
}

func statusEvents(pairs ...models.StatusEvent) []models.StatusEvent { return pairs }

func ev(status string, at time.Time) models.StatusEvent {
	return models.StatusEvent{AccessStatus: status, RecordedAt: at}
}

func TestOutcomeFor(t *testing.T) {
	tests := []struct {
		risk   string
		closed bool
		want   string
	}{
		{RiskLikely, true, OutcomeHit},
		{RiskPossible, true, OutcomeCovered},
		{RiskNone, true, OutcomeMiss},
		{RiskLikely, false, OutcomeFalseAlarm},
		{RiskPossible, false, OutcomeHedged},
		{RiskNone, false, OutcomeQuiet},
	}
	for _, tt := range tests {
		assert.Equal(t, tt.want, outcomeFor(tt.risk, tt.closed), "risk=%s closed=%v", tt.risk, tt.closed)
	}
}

func TestBuildScorecardGradesTheDay(t *testing.T) {
	history := map[string][]models.StatusEvent{
		// Eager closer (threshold 2.1): closed 13:40–17:05 around the 15:30
		// peak — a hit, and inside the predicted window.
		"NS-141": statusEvents(
			ev("OPEN", et(1, 8, 0)),
			ev("CLOSED FOR HIGH TIDE", et(16, 13, 40)),
			ev("OPEN", et(16, 17, 5)),
		),
		// Tough ramp (threshold 3.25, band tops at 3.55): 3.4 is inside the
		// band → possible; it stayed open all day — a hedge, no penalty.
		"NS-106": statusEvents(
			ev("OPEN", et(1, 8, 0)),
		),
		// Flipper (threshold 3.85, close rate 0.42): 3.4 is below its band but
		// the mid-range rule keeps it possible; it closed — covered.
		"DB-041": statusEvents(
			ev("OPEN", et(1, 8, 0)),
			ev("CLOSED FOR HIGH TIDE", et(16, 14, 55)),
			ev("OPEN", et(16, 17, 40)),
		),
		// History starts after the graded day — must be skipped entirely.
		"CB-999": statusEvents(
			ev("OPEN", et(20, 8, 0)),
		),
	}

	sc := BuildScorecard(et(16, 0, 0), history, nil, testParams(), scorecardPreds(), nil, nil)

	assert.Equal(t, "2026-06-16", sc.Date)
	assert.Equal(t, "turtle", sc.Season)
	require.Len(t, sc.Peaks, 1, "only the 15:30 daytime peak counts")
	assert.Equal(t, et(16, 15, 30), sc.Peaks[0].Time)

	require.Len(t, sc.Ramps, 3, "late-history ramp skipped")
	byID := map[string]RampGrade{}
	for _, rg := range sc.Ramps {
		byID[rg.AccessID] = rg
	}

	eager := byID["NS-141"]
	require.Len(t, eager.Peaks, 1)
	assert.Equal(t, OutcomeHit, eager.Peaks[0].Outcome)
	require.NotNil(t, eager.Peaks[0].Window)
	require.NotNil(t, eager.Peaks[0].WindowHit)
	assert.True(t, *eager.Peaks[0].WindowHit, "closed 13:40, window starts 12:30")
	require.NotNil(t, eager.Peaks[0].ClosedAt)
	assert.Equal(t, et(16, 13, 40), eager.Peaks[0].ClosedAt.In(eastern))
	require.NotNil(t, eager.Peaks[0].ReopenedAt)
	assert.Equal(t, et(16, 17, 5), eager.Peaks[0].ReopenedAt.In(eastern))

	tough := byID["NS-106"]
	require.Len(t, tough.Peaks, 1)
	assert.Equal(t, OutcomeHedged, tough.Peaks[0].Outcome)
	assert.Nil(t, tough.Peaks[0].Window, "no window grading for open ramps")

	flipper := byID["DB-041"]
	require.Len(t, flipper.Peaks, 1)
	assert.Equal(t, OutcomeCovered, flipper.Peaks[0].Outcome)

	assert.Equal(t, 3, sc.Summary.Graded)
	assert.Equal(t, 1, sc.Summary.Hits)
	assert.Equal(t, 1, sc.Summary.Covered)
	assert.Equal(t, 1, sc.Summary.Hedged)
	assert.Equal(t, 0, sc.Summary.Misses)
	assert.Equal(t, 0, sc.Summary.FalseAlarms)
	require.NotNil(t, sc.Summary.Recall)
	assert.InDelta(t, 1.0, *sc.Summary.Recall, 0.001, "both closures were flagged")
	require.NotNil(t, sc.Summary.Precision)
	assert.InDelta(t, 1.0, *sc.Summary.Precision, 0.001)
	assert.Equal(t, 2, sc.Summary.WindowGraded)
	assert.Equal(t, 2, sc.Summary.WindowHits)
}

func TestBuildScorecardMissAndFalseAlarm(t *testing.T) {
	low := 0.4
	mid := 1.95 // at or below hard open (2.0) → none for everyone
	big := 3.7  // above hard close (3.5) → likely for everyone
	preds := []models.TidePrediction{
		{Time: et(16, 9, 0), Type: "L", Height: &low},
		{Time: et(16, 11, 0), Type: "H", Height: &mid},
		{Time: et(16, 18, 30), Type: "H", Height: &big},
	}

	history := map[string][]models.StatusEvent{
		// Closed around the 11:00 peak the model called "none" — a miss —
		// and stayed open through the 18:30 peak it called likely — false alarm.
		"NS-141": statusEvents(
			ev("OPEN", et(1, 8, 0)),
			ev("CLOSED FOR HIGH TIDE", et(16, 10, 30)),
			ev("OPEN", et(16, 12, 45)),
		),
	}

	sc := BuildScorecard(et(16, 0, 0), history, nil, testParams(), preds, nil, nil)

	require.Len(t, sc.Ramps, 1)
	require.Len(t, sc.Ramps[0].Peaks, 2)
	assert.Equal(t, OutcomeMiss, sc.Ramps[0].Peaks[0].Outcome)
	assert.Equal(t, OutcomeFalseAlarm, sc.Ramps[0].Peaks[1].Outcome)

	require.NotNil(t, sc.Summary.Recall)
	assert.InDelta(t, 0.0, *sc.Summary.Recall, 0.001)
	require.NotNil(t, sc.Summary.Precision)
	assert.InDelta(t, 0.0, *sc.Summary.Precision, 0.001)
	assert.Equal(t, 0, sc.Summary.WindowGraded, "missed closures have no window to grade")
}

func TestBuildScorecardMetadataOverride(t *testing.T) {
	history := map[string][]models.StatusEvent{
		"NS-141": statusEvents(ev("OPEN", et(1, 8, 0))),
	}
	override := 4.2
	heights := map[string]*float64{"NS-141": &override}

	sc := BuildScorecard(et(16, 0, 0), history, heights, testParams(), scorecardPreds(), nil, nil)

	require.Len(t, sc.Ramps, 1)
	assert.Equal(t, 4.2, sc.Ramps[0].ThresholdFt)
	require.Len(t, sc.Ramps[0].Peaks, 1)
	assert.Equal(t, OutcomeQuiet, sc.Ramps[0].Peaks[0].Outcome,
		"operator threshold silences the 3.4 ft peak, and the ramp indeed stayed open")
}

func TestBuildScorecardNoPeaks(t *testing.T) {
	low := 0.4
	preds := []models.TidePrediction{{Time: et(16, 9, 0), Type: "L", Height: &low}}
	sc := BuildScorecard(et(16, 0, 0), map[string][]models.StatusEvent{
		"NS-141": statusEvents(ev("OPEN", et(1, 8, 0))),
	}, nil, testParams(), preds, nil, nil)

	assert.Empty(t, sc.Peaks)
	assert.Empty(t, sc.Ramps)
	assert.Equal(t, 0, sc.Summary.Graded)
}
