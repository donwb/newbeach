package predict

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

func TestPersistShift(t *testing.T) {
	p := Params{Persistence: &PersistenceParams{OpenRaiseFt: 0.6, ClosedDropFt: 0.4}}
	rp := RampParams{}

	assert.Equal(t, 0.0, Params{}.persistShift(PriorDay{Known: true}, rp), "unlearned → memoryless")
	assert.Equal(t, 0.0, p.persistShift(PriorDay{}, rp), "unknown prior → memoryless")
	assert.InDelta(t, 0.6, p.persistShift(PriorDay{Known: true}, rp), 1e-9, "rode out yesterday's tide raises the bar")
	assert.InDelta(t, -0.4, p.persistShift(PriorDay{Known: true, Closed: true}, rp), 1e-9, "closed yesterday lowers it")

	own := RampParams{Persistence: &PersistenceParams{OpenRaiseFt: 0.1, ClosedDropFt: 0}}
	assert.InDelta(t, 0.1, p.persistShift(PriorDay{Known: true}, own), 1e-9, "the ramp's own shifts win")

	huge := Params{Persistence: &PersistenceParams{OpenRaiseFt: 9}}
	assert.InDelta(t, maxPersistShiftFt, huge.persistShift(PriorDay{Known: true}, rp), 1e-9, "clamped")
}

func TestPersistDayShiftIsHeightAnchored(t *testing.T) {
	p := Params{Persistence: &PersistenceParams{OpenRaiseFt: 0.6, ClosedDropFt: 0.4}}
	rp := RampParams{}
	open := PriorDay{Known: true, MaxPeakFt: 2.8}
	closed := PriorDay{Known: true, Closed: true, MaxPeakFt: 2.8}

	assert.InDelta(t, 0.6, p.persistDayShift(open, rp, 3.4, 0), 1e-9, "today: full shift whatever the height")
	assert.InDelta(t, 0.6, p.persistDayShift(open, rp, 3.0, 2), 1e-9, "Saturday peak within tolerance of the tide it rode out")
	assert.Equal(t, 0.0, p.persistDayShift(open, rp, 3.1, 2), "the cycle pushed higher — no promise of openness")
	assert.InDelta(t, -0.4, p.persistDayShift(closed, rp, 3.4, 1), 1e-9, "the hedge carries one day")
	assert.Equal(t, 0.0, p.persistDayShift(closed, rp, 3.4, 2), "and no further")
}

// Two days of history: yesterday (the 15th) and today (the 16th). preds
// carry one daytime high each day.
func priorScenario() (time.Time, []models.TidePrediction) {
	h := 3.0
	preds := []models.TidePrediction{
		{Time: et(15, 14, 0), Type: "H", Height: &h},
		{Time: et(16, 2, 0), Type: "H", Height: &h},
		{Time: et(16, 15, 0), Type: "H", Height: &h},
	}
	return et(16, 9, 0), preds
}

func TestPriorDayFacts(t *testing.T) {
	now, preds := priorScenario()
	hist := map[string][]models.StatusEvent{
		// Closed around yesterday's 2pm high, reopened after.
		"closer": {
			{AccessStatus: "OPEN", RecordedAt: et(1, 8, 0)},
			{AccessStatus: tideClosedStatus, RecordedAt: et(15, 12, 30)},
			{AccessStatus: "OPEN", RecordedAt: et(15, 17, 0)},
		},
		// Stayed open all of yesterday.
		"rider": {
			{AccessStatus: "OPEN", RecordedAt: et(1, 8, 0)},
		},
		// Baseline row before the window: already tide-closed at midnight
		// (from the night before), still closed through yesterday's peak.
		"baseline": {
			{AccessStatus: tideClosedStatus, RecordedAt: et(14, 23, 0)},
			{AccessStatus: "OPEN", RecordedAt: et(15, 16, 0)},
		},
		// Only today's closure — must not leak into yesterday's answer.
		"today": {
			{AccessStatus: "OPEN", RecordedAt: et(1, 8, 0)},
			{AccessStatus: tideClosedStatus, RecordedAt: et(16, 8, 0)},
		},
		// History started today: no evidence about yesterday.
		"newcomer": {
			{AccessStatus: "OPEN", RecordedAt: et(16, 7, 0)},
		},
	}

	facts := priorDayFacts(now, hist, preds, 2.0)
	assert.Equal(t, PriorDay{Known: true, Closed: true, MaxPeakFt: 3.0}, facts["closer"])
	assert.Equal(t, PriorDay{Known: true, Closed: false, MaxPeakFt: 3.0}, facts["rider"])
	assert.Equal(t, PriorDay{Known: true, Closed: true, MaxPeakFt: 3.0}, facts["baseline"])
	assert.Equal(t, PriorDay{Known: true, Closed: false, MaxPeakFt: 3.0}, facts["today"], "today's closure is not yesterday's")
	assert.False(t, facts["newcomer"].Known)

	t.Run("a peak under the hard-open cutoff is no evidence", func(t *testing.T) {
		facts := priorDayFacts(now, hist, preds, 3.2)
		assert.False(t, facts["rider"].Known)
	})
	t.Run("no daytime peak yesterday is no evidence", func(t *testing.T) {
		facts := priorDayFacts(now, hist, preds[1:], 2.0)
		assert.False(t, facts["rider"].Known)
	})
}

func TestBuildOutlookPersistence(t *testing.T) {
	now, preds := afternoonScenario()
	ramps := []models.RampStatusWithSince{ramp(1, "NS-106", "OPEN")}
	params := testParams()
	params.Persistence = &PersistenceParams{OpenRaiseFt: 0.6, ClosedDropFt: 0.5}

	find := func(out Outlook) RampOutlook { return out.Ramps[0] }

	memoryless := find(BuildOutlook(now, ramps, params, preds, nil, nil))
	assert.Equal(t, RiskPossible, memoryless.Risk)
	assert.Nil(t, memoryless.Yesterday)

	rode := find(BuildOutlook(now, ramps, params, preds, nil, map[string]PriorDay{"NS-106": {Known: true, MaxPeakFt: 3.3}}))
	assert.Equal(t, RiskScheduled, rode.Risk, "rode out a near-identical tide yesterday → no tide call today")
	require.NotNil(t, rode.Yesterday)
	assert.True(t, rode.Yesterday.Applied)
	assert.False(t, rode.Yesterday.Closed)

	closed := find(BuildOutlook(now, ramps, params, preds, nil, map[string]PriorDay{"NS-106": {Known: true, Closed: true, MaxPeakFt: 3.3}}))
	assert.Equal(t, RiskPossible, closed.Risk, "closed yesterday never promotes to likely")
	require.NotNil(t, closed.Yesterday)
	assert.True(t, closed.Yesterday.Closed)
	assert.Contains(t, closed.Detail, "closed for yesterday's tide too")

	unknown := find(BuildOutlook(now, ramps, params, preds, nil, map[string]PriorDay{"NS-106": {}}))
	assert.Equal(t, memoryless.Risk, unknown.Risk)
	assert.Nil(t, unknown.Yesterday, "an unknown prior is not echoed")
}

func TestTideTextPersistenceClause(t *testing.T) {
	now, preds := afternoonScenario()
	rp := testParams().Ramps["NS-141"]
	_, sched := buildSchedule(now, testParams())
	peak := preds[2]

	_, plain, _ := tideText(now, RiskPossible, peak, rp, sched, false, nil)
	_, rode, _ := tideText(now, RiskPossible, peak, rp, sched, false, &YesterdayContext{Applied: true})
	_, idle, _ := tideText(now, RiskPossible, peak, rp, sched, false, &YesterdayContext{Applied: false})
	assert.Equal(t, plain, idle, "a prior that didn't move the call stays out of the copy")
	assert.True(t, strings.HasSuffix(rode, " · rode out yesterday's tide"), rode)
	assert.LessOrEqual(t, len(rode), 90, "detail line stays a line")
}

func TestTrainPersistParams(t *testing.T) {
	assert.Nil(t, trainPersistParams(nil))
	assert.Nil(t, trainPersistParams(make([]persistSample, minPersistPoolSamples-1)), "under the pool floor")

	// Synthetic county: peaks 2.4–3.2 around a 2.8 threshold. Ramps that
	// rode out yesterday's tide only close above 3.1; ramps that closed
	// yesterday close from 2.5 up.
	var pool []persistSample
	for i := 0; i < 40; i++ {
		h := 2.4 + 0.02*float64(i)
		pool = append(pool, persistSample{peakFt: h, thresholdFt: 2.8, label: h >= 3.1, priorClosed: false})
		pool = append(pool, persistSample{peakFt: h, thresholdFt: 2.8, label: h >= 2.5, priorClosed: true})
	}
	pp := trainPersistParams(pool)
	require.NotNil(t, pp)
	assert.InDelta(t, 0.3, pp.OpenRaiseFt, 0.051)
	assert.InDelta(t, 0.3, pp.ClosedDropFt, 0.051)
	assert.Equal(t, 80, pp.NSamples)
	assert.Greater(t, pp.Accuracy, 0.9)

	t.Run("no gain → nil", func(t *testing.T) {
		var flat []persistSample
		for i := 0; i < 40; i++ {
			h := 2.4 + 0.02*float64(i)
			flat = append(flat, persistSample{peakFt: h, thresholdFt: 2.8, label: h >= 2.8, priorClosed: i%2 == 0})
		}
		assert.Nil(t, trainPersistParams(flat))
	})
}

func TestTrainLearnsPersistenceFromFixture(t *testing.T) {
	history := loadHistoryFixture(t)
	hilo := loadHiloFixture(t)
	params := Train(history, hilo, nil, time.Date(2026, 8, 16, 0, 0, 0, 0, eastern))
	require.NotNil(t, params.Persistence)
	assert.Greater(t, params.Persistence.OpenRaiseFt, 0.0)
	own := 0
	for id, rp := range params.Ramps {
		if rp.Persistence != nil {
			own++
			t.Logf("%s: open raise=%.2f closed drop=%.2f n=%d acc=%.3f", id, rp.Persistence.OpenRaiseFt, rp.Persistence.ClosedDropFt, rp.Persistence.NSamples, rp.Persistence.Accuracy)
		}
	}
	assert.GreaterOrEqual(t, own, 3, "the busy ramps should learn their own shifts")
}

func TestScorecardGradesWithPrior(t *testing.T) {
	history := loadHistoryFixture(t)
	hilo := loadHiloFixture(t)
	params := Train(history, hilo, nil, time.Date(2026, 8, 16, 0, 0, 0, 0, eastern))
	sc := BuildScorecard(time.Date(2026, 7, 10, 0, 0, 0, 0, eastern), history, nil, params, hilo, nil)
	require.NotEmpty(t, sc.Ramps)
	assert.NotNil(t, sc.Persistence)
	seen := false
	for _, rg := range sc.Ramps {
		for _, pg := range rg.Peaks {
			if pg.Yesterday != nil {
				seen = true
			}
		}
	}
	assert.True(t, seen, "graded peaks carry the prior they were graded under")
}

// The planner carries "rode out yesterday's tide" forward only while the
// future day's peak is no higher than the one already ridden out.
func TestWeekendPersistenceIsHeightAnchored(t *testing.T) {
	now := etTime(t, "2026-08-19 10:00") // Wednesday
	// 2.7 ft peaks (inside the default band → "possible") through Friday,
	// then the cycle builds: Saturday 3.0, Sunday 3.1.
	heights := []float64{2.7, 2.7, 2.7, 3.0, 3.1, 2.7, 2.7, 2.7}
	var preds []models.TidePrediction
	for d, h := range heights {
		preds = append(preds, highAt(t, now.AddDate(0, 0, d).Format("2006-01-02")+" 13:00", h))
	}
	params := weekendTestParams()
	params.Persistence = &PersistenceParams{OpenRaiseFt: 0.6}
	prior := map[string]PriorDay{}
	for _, r := range testRamps() {
		prior[r.AccessID] = PriorDay{Known: true, MaxPeakFt: 2.7}
	}
	land := flatLand(now, now.AddDate(0, 0, 7), nil)

	memoryless := BuildWeekendOutlook(now, testRamps(), params, DefaultVerdictParams(), preds, land, nil, nil)
	withPrior := BuildWeekendOutlook(now, testRamps(), params, DefaultVerdictParams(), preds, land, nil, prior)

	assert.Equal(t, PressureSome, day(t, memoryless, "Friday").ClosurePressure)
	assert.Equal(t, PressureNone, day(t, withPrior, "Friday").ClosurePressure, "same tide as the one they rode out → carried forward")
	assert.Equal(t, day(t, memoryless, "Saturday").ClosurePressure, day(t, withPrior, "Saturday").ClosurePressure, "the cycle pushed higher → the prior switches off")
	assert.NotEqual(t, PressureNone, day(t, withPrior, "Saturday").ClosurePressure)
}
