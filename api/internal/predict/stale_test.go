package predict

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func TestStaleDaysTurtleStuck(t *testing.T) {
	tests := []struct {
		name    string
		flipAt  time.Time
		wantDay bool
	}{
		{"normal 8:05 flip", et(16, 8, 5), false},
		{"late open inside grace", et(16, 9, 45), false},
		{"just past grace", et(16, 10, 10), true},
		{"the 2026-08-26 shape, standing past noon", et(16, 12, 30), true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			events := statusEvents(
				ev("OPEN", et(15, 8, 0)),
				ev(turtleClearedStatus, et(15, 19, 2)),
				ev("OPEN", tt.flipAt),
			)
			days := staleDaysForRamp(events, et(17, 0, 0))
			assert.Equal(t, tt.wantDay, days["2026-06-16"], "day 16")
			assert.False(t, days["2026-06-15"], "the evening it was set is never stale")
		})
	}
}

func TestStaleDaysTurtleSpansIntoNextMorning(t *testing.T) {
	// The DBS-075 2026-07-28 shape: set at 8:01am, stood all day and through
	// the night, flipped 6:30am the next day. Day one is stale; day two's
	// deadline was never inside the interval.
	events := statusEvents(
		ev("OPEN", et(14, 8, 0)),
		ev(turtleClearedStatus, et(15, 8, 1)),
		ev("OPEN", et(16, 6, 30)),
	)
	days := staleDaysForRamp(events, et(17, 0, 0))
	assert.True(t, days["2026-06-15"])
	assert.False(t, days["2026-06-16"])
}

func TestStaleDaysTurtleStillStandingNow(t *testing.T) {
	// A status with no later event runs to `now`: nothing is stale until the
	// grace deadline has actually passed.
	events := statusEvents(
		ev("OPEN", et(15, 8, 0)),
		ev(turtleClearedStatus, et(16, 6, 51)),
	)
	assert.Empty(t, staleDaysForRamp(events, et(16, 9, 0)), "9am: the county may still flip it")
	assert.True(t, staleDaysForRamp(events, et(16, 10, 30))["2026-06-16"], "10:30am: stale")
}

func TestStaleDaysTideCap(t *testing.T) {
	// A tide closure spanning past the next day's open: day one keeps its
	// real closure, the forgotten days are stale.
	events := statusEvents(
		ev("OPEN", et(14, 8, 0)),
		ev(tideClosedStatus, et(15, 14, 0)),
		ev("OPEN", et(17, 11, 0)),
	)
	days := staleDaysForRamp(events, et(18, 0, 0))
	assert.False(t, days["2026-06-15"], "the closure itself is real")
	assert.True(t, days["2026-06-16"])
	assert.True(t, days["2026-06-17"], "still standing at 10am")

	t.Run("an evening closure reopened before the next open is fine", func(t *testing.T) {
		events := statusEvents(
			ev("OPEN", et(14, 8, 0)),
			ev(tideClosedStatus, et(15, 17, 0)),
			ev("OPEN", et(16, 7, 45)),
		)
		assert.Empty(t, staleDaysForRamp(events, et(17, 0, 0)))
	})
	t.Run("an unbounded closure is capped at now", func(t *testing.T) {
		events := statusEvents(
			ev("OPEN", et(14, 8, 0)),
			ev(tideClosedStatus, et(15, 14, 0)),
		)
		assert.Empty(t, staleDaysForRamp(events, et(16, 9, 0)))
		assert.True(t, staleDaysForRamp(events, et(16, 11, 0))["2026-06-16"])
	})
}

func TestStaleDaysOutOfTurtleSeason(t *testing.T) {
	// December opens at sunrise; a turtle status standing until mid-afternoon
	// is stale whatever the exact sunrise was.
	dec := func(day, hour, min int) time.Time {
		return time.Date(2026, 12, day, hour, min, 0, 0, eastern)
	}
	events := statusEvents(
		ev("OPEN", dec(14, 8, 0)),
		ev(turtleClearedStatus, dec(15, 6, 30)),
		ev("OPEN", dec(15, 15, 0)),
	)
	assert.True(t, staleDaysForRamp(events, dec(16, 0, 0))["2026-12-15"])
}

func TestParseExcludedDays(t *testing.T) {
	assert.Nil(t, ParseExcludedDays(""))
	assert.Nil(t, ParseExcludedDays("not json"))
	assert.Nil(t, ParseExcludedDays(`{"wrong": "shape"}`))
	assert.Nil(t, ParseExcludedDays(`["also-not-a-date"]`))
	assert.Equal(t, map[string]bool{"2026-08-26": true},
		ParseExcludedDays(`["2026-08-26", "bad"]`), "invalid entries skip, valid ones survive")
}

func TestExclusionsMergeManualAndStale(t *testing.T) {
	history := map[string][]models.StatusEvent{
		"stuck": statusEvents(
			ev("OPEN", et(15, 8, 0)),
			ev(turtleClearedStatus, et(16, 6, 51)),
			ev("OPEN", et(16, 12, 30)),
		),
		"fine": statusEvents(ev("OPEN", et(15, 8, 0))),
	}
	excl := findExclusions(history, et(17, 0, 0), map[string]bool{"2026-06-20": true})

	assert.True(t, excl.excluded("stuck", et(16, 15, 30)))
	assert.False(t, excl.excluded("fine", et(16, 15, 30)), "heuristic days are per-ramp")
	assert.True(t, excl.excluded("stuck", et(20, 12, 0)), "manual days hit every ramp")
	assert.True(t, excl.excluded("fine", et(20, 12, 0)))
	assert.False(t, excl.excluded("fine", et(19, 12, 0)))

	var zero exclusions
	assert.False(t, zero.excluded("stuck", et(16, 15, 30)), "zero value excludes nothing")
}

func TestTrainQuarantinesStaleDay(t *testing.T) {
	// 14 separable days, then a 15th with a big peak the ramp sat out under a
	// stuck turtle status. Quarantined, the 15th must not count as "rode out
	// a 3.2 ft peak" — the learned params match the 14-day baseline exactly.
	var peaks []models.TidePrediction
	for day := 1; day <= 14; day++ {
		height := 2.2
		if day%2 == 0 {
			height = 3.2
		}
		peaks = append(peaks, h(et(day, 13, 0), height))
	}
	baseline := Train(map[string][]models.StatusEvent{
		"NS-999": buildSeparableHistory(peaks, 2.8),
	}, peaks, nil, et(15, 0, 0), nil)

	peaks = append(peaks, h(et(15, 13, 0), 3.2))
	stuckDay := append(buildSeparableHistory(peaks[:14], 2.8),
		ev(turtleClearedStatus, et(15, 6, 51)),
		ev("OPEN", et(15, 12, 30)),
	)
	quarantined := Train(map[string][]models.StatusEvent{"NS-999": stuckDay}, peaks, nil, et(16, 0, 0), nil)
	assert.Equal(t, baseline.Ramps["NS-999"], quarantined.Ramps["NS-999"])

	// Sanity: had the ramp genuinely stayed open that day, the close rate
	// would have moved — the quarantine, not coincidence, kept it fixed.
	openDay := append(buildSeparableHistory(peaks[:14], 2.8), ev("OPEN", et(15, 6, 51)))
	counted := Train(map[string][]models.StatusEvent{"NS-999": openDay}, peaks, nil, et(16, 0, 0), nil)
	assert.NotEqual(t, baseline.Ramps["NS-999"].CloseRate, counted.Ramps["NS-999"].CloseRate)
}

func TestBuildScorecardStaleDay(t *testing.T) {
	history := map[string][]models.StatusEvent{
		// Stuck in the overnight turtle status through the graded day's peak.
		"NS-141": statusEvents(
			ev("OPEN", et(1, 8, 0)),
			ev(turtleClearedStatus, et(16, 6, 51)),
			ev("OPEN", et(16, 12, 30)),
		),
		// A normal ramp the same day still grades.
		"NS-106": statusEvents(ev("OPEN", et(1, 8, 0))),
	}

	sc := BuildScorecard(et(16, 0, 0), history, nil, testParams(), scorecardPreds(), nil, nil)

	byID := map[string]RampGrade{}
	for _, rg := range sc.Ramps {
		byID[rg.AccessID] = rg
	}
	stuck := byID["NS-141"]
	require.Len(t, stuck.Peaks, 1)
	assert.Equal(t, OutcomeStale, stuck.Peaks[0].Outcome)
	assert.NotEmpty(t, stuck.Peaks[0].Risk, "the risk it would have called still shows")
	assert.Nil(t, stuck.Peaks[0].Window, "no window grading on a stale day")

	require.Len(t, byID["NS-106"].Peaks, 1)
	assert.NotEqual(t, OutcomeStale, byID["NS-106"].Peaks[0].Outcome)

	assert.Equal(t, 1, sc.Summary.Stale)
	assert.Equal(t, 1, sc.Summary.Graded, "stale pairs stay out of the graded count")

	t.Run("a manually excluded day stales every ramp", func(t *testing.T) {
		sc := BuildScorecard(et(16, 0, 0), history, nil, testParams(), scorecardPreds(), nil,
			map[string]bool{"2026-06-16": true})
		assert.Equal(t, 2, sc.Summary.Stale)
		assert.Equal(t, 0, sc.Summary.Graded)
		assert.Nil(t, sc.Summary.Recall)
		assert.Nil(t, sc.Summary.Precision)
	})
}
