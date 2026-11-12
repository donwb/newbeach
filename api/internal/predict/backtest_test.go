package predict

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
)

// The backtest replays five months of real history (six representative
// ramps, checked-in fixtures, no network): train on the full span, then for
// each day ask the outlook at 9am ET whether each ramp is at risk, and
// compare against whether it actually tide-closed that day. The floors are
// pinned slightly below measured performance so engine changes that degrade
// real-world behavior fail here.

type fixtureEvent struct {
	S string `json:"s"`
	T string `json:"t"`
}

func loadHistoryFixture(t *testing.T) map[string][]models.StatusEvent {
	t.Helper()
	return loadHistoryFile(t, "testdata/history.json")
}

func loadHistoryFile(t *testing.T, path string) map[string][]models.StatusEvent {
	t.Helper()
	raw, err := os.ReadFile(path)
	require.NoError(t, err)
	var byRamp map[string][]fixtureEvent
	require.NoError(t, json.Unmarshal(raw, &byRamp))

	out := make(map[string][]models.StatusEvent, len(byRamp))
	for id, evs := range byRamp {
		for _, e := range evs {
			ts, err := time.Parse(time.RFC3339, e.T)
			require.NoError(t, err)
			out[id] = append(out[id], models.StatusEvent{AccessStatus: e.S, RecordedAt: ts})
		}
	}
	return out
}

func loadHiloFixture(t *testing.T) []models.TidePrediction {
	t.Helper()
	return loadHiloFile(t, "testdata/hilo.json")
}

func loadHiloFile(t *testing.T, path string) []models.TidePrediction {
	t.Helper()
	raw, err := os.ReadFile(path)
	require.NoError(t, err)
	var rows []struct {
		T    string `json:"t"`
		V    string `json:"v"`
		Type string `json:"type"`
	}
	require.NoError(t, json.Unmarshal(raw, &rows))

	preds := make([]models.TidePrediction, 0, len(rows))
	for _, r := range rows {
		ts, err := time.ParseInLocation("2006-01-02 15:04", r.T, eastern)
		require.NoError(t, err)
		h, err := strconv.ParseFloat(strings.TrimSpace(r.V), 64)
		require.NoError(t, err)
		height := h
		preds = append(preds, models.TidePrediction{Time: ts, Type: r.Type, Height: &height})
	}
	return preds
}

// loadWavesFixture returns NDBC 41113 wave observations covering the history
// span, ascending. Regenerate with cmd/gen-waves-fixture, which pulls the
// monthly stdmet archives plus the realtime2 window straight from NDBC.
func loadWavesFixture(t *testing.T) []models.WaveSample {
	t.Helper()
	raw, err := os.ReadFile("testdata/waves.json")
	require.NoError(t, err)
	var samples []models.WaveSample
	require.NoError(t, json.Unmarshal(raw, &samples))
	return samples
}

// summerFixtureEnd bounds the span the original backtests were measured on
// (history fetched 2026-08-16; hilo and waves ran a little past it). The
// fixtures have since been extended through king-tide season; trimming back
// reproduces the original data exactly, so the summer floors below keep
// meaning what they were measured to mean.
var (
	summerHistoryEnd = time.Date(2026, 8, 16, 12, 10, 0, 0, time.UTC)
	summerHiloEnd    = time.Date(2026, 8, 19, 4, 0, 0, 0, time.UTC) // midnight ET
	summerWavesEnd   = time.Date(2026, 8, 17, 0, 0, 0, 0, time.UTC)
)

// loadSummerFixtures returns the history, hilo, and wave fixtures trimmed to
// the original Mar–Aug 2026 backtest span.
func loadSummerFixtures(t *testing.T) (map[string][]models.StatusEvent, []models.TidePrediction, []models.WaveSample) {
	t.Helper()
	history := loadHistoryFixture(t)
	for id, evs := range history {
		var kept []models.StatusEvent
		for _, e := range evs {
			if e.RecordedAt.Before(summerHistoryEnd) {
				kept = append(kept, e)
			}
		}
		history[id] = kept
	}
	var hilo []models.TidePrediction
	for _, p := range loadHiloFixture(t) {
		if p.Time.Before(summerHiloEnd) {
			hilo = append(hilo, p)
		}
	}
	var waves []models.WaveSample
	for _, w := range loadWavesFixture(t) {
		if w.Time.Before(summerWavesEnd) {
			waves = append(waves, w)
		}
	}
	return history, hilo, waves
}

// actualClosureDays returns the set of ET dates on which the ramp began a
// tide closure during plausible driving hours.
func actualClosureDays(events []models.StatusEvent) map[string]bool {
	days := make(map[string]bool)
	for _, c := range closureEvents(events) {
		et := c.closedAt.In(eastern)
		if h := et.Hour(); h >= 7 && h < 20 {
			days[et.Format("2006-01-02")] = true
		}
	}
	return days
}

// backtestTally is one ramp's day-level replay outcome counts.
type backtestTally struct {
	closures, flagged       int // closure days, and those flagged possible/likely
	likelyDays, likelyRight int // days flagged likely, and those that closed
	noneDays, noneRight     int // days flagged none, and those that stayed open
}

// loadLevelsFixture returns hourly observed-minus-predicted water levels at
// Trident Pier and Mayport covering the history span. Regenerate with
// cmd/gen-levels-fixture.
func loadLevelsFixture(t *testing.T) []models.WaterLevelSample {
	t.Helper()
	raw, err := os.ReadFile("testdata/levels.json")
	require.NoError(t, err)
	var levels []models.WaterLevelSample
	require.NoError(t, json.Unmarshal(raw, &levels))
	return levels
}

// runBacktest trains on the full fixture span and replays each day's 9am ET
// outlook against what actually happened. waves nil replays tide-only —
// exactly the pre-wave engine. levels nil replays on predicted heights —
// exactly the pre-surge engine. persistence false replays memoryless (no
// prior-day carry-over) — exactly the pre-persistence engine.
func runBacktest(t *testing.T, history map[string][]models.StatusEvent, hilo []models.TidePrediction, waves []models.WaveSample, levels []models.WaterLevelSample, persistence bool) (Params, map[string]*backtestTally) {
	t.Helper()

	trainedAt := time.Date(2026, 8, 16, 0, 0, 0, 0, eastern)
	params := Train(history, hilo, waves, levels, trainedAt, nil)
	require.NotEmpty(t, params.Ramps, "fixture ramps should all learn")

	ramps := make([]models.RampStatusWithSince, 0, len(history))
	firstDay := trainedAt
	for id, evs := range history {
		ramps = append(ramps, ramp(int64(len(ramps)+1), id, "OPEN"))
		if evs[0].RecordedAt.Before(firstDay) {
			firstDay = evs[0].RecordedAt
		}
	}

	tallies := make(map[string]*backtestTally)
	for id := range history {
		tallies[id] = &backtestTally{}
	}
	actual := make(map[string]map[string]bool)
	for id, evs := range history {
		actual[id] = actualClosureDays(evs)
	}

	for day := firstDay.In(eastern).AddDate(0, 0, 1); day.Before(trainedAt); day = day.AddDate(0, 0, 1) {
		at := time.Date(day.Year(), day.Month(), day.Day(), 9, 0, 0, 0, eastern)
		// The same persistence assumption prod makes: the observation
		// nearest the serve moment stands in for the day.
		// The prior the live model would have had that morning: derived
		// from the same history, but yesterday only — today's events are
		// dropped by priorDayFacts so the replay never peeks at its answer.
		var prior map[string]PriorDay
		if persistence {
			water, _ := params.withSurge(hilo, levels, at)
			prior = priorDayFacts(at, history, water, params.hardOpen(), nil)
		}
		out := BuildOutlook(at, ramps, params, hilo, waveNearTime(waves, at), levels, prior)
		date := day.Format("2006-01-02")

		for _, ro := range out.Ramps {
			tl := tallies[ro.AccessID]
			closed := actual[ro.AccessID][date]
			if closed {
				tl.closures++
				if ro.Risk == RiskPossible || ro.Risk == RiskLikely {
					tl.flagged++
				}
			}
			switch ro.Risk {
			case RiskLikely:
				tl.likelyDays++
				if closed {
					tl.likelyRight++
				}
			// Both mean "no tide closure predicted today" — scheduled only
			// says the driving day will end, which it always does.
			case RiskNone, RiskScheduled:
				tl.noneDays++
				if !closed {
					tl.noneRight++
				}
			}
		}
	}
	return params, tallies
}

// assertBacktestFloors pins recall and calibration. The recall floors are the
// regression net — they predate the wave model and never move down.
// calibrationFloor is what "likely" and "none" must each score when they have
// a real sample: the tide-only engine earns 0.50; the wave-aware engine
// demonstrably earns 0.60.
func assertBacktestFloors(t *testing.T, tallies map[string]*backtestTally, recallFloor map[string]float64, calibrationFloor float64) {
	t.Helper()
	for id, tl := range tallies {
		require.Greater(t, tl.closures, 0, "%s: fixture should contain closures", id)
		recall := float64(tl.flagged) / float64(tl.closures)
		t.Logf("%-8s closure days=%3d recall=%.2f  likely: %d/%d right  none: %d/%d right",
			id, tl.closures, recall, tl.likelyRight, tl.likelyDays, tl.noneRight, tl.noneDays)

		assert.GreaterOrEqual(t, recall, recallFloor[id], "%s recall regressed", id)

		// Calibration: "likely" and "none" should each be right more often
		// than wrong. Only assert on real samples.
		if tl.likelyDays >= 10 {
			assert.GreaterOrEqual(t, float64(tl.likelyRight)/float64(tl.likelyDays), calibrationFloor,
				"%s: 'likely' is poorly calibrated", id)
		}
		if tl.noneDays >= 10 {
			assert.GreaterOrEqual(t, float64(tl.noneRight)/float64(tl.noneDays), calibrationFloor,
				"%s: 'none' days keep closing anyway", id)
		}
	}
}

// Recall floors pinned a few points below the measured runs so noise doesn't
// flake the build. The mid-band ramps' misses are surf-driven closures the
// tide alone can't see; the calm raise deliberately trades a few recall
// points on those ramps for a 40% cut in false "likely" days — but no ramp
// may ever drop below its floor, and shrinking maxWaveShiftFt (never the
// floors) is the fix if one does.
// Measured 2026-08-18 — tide-only / wave-aware:
//
//	NS-141 0.98/0.95, NS-118 0.97/0.95, NS-106 0.55/0.66,
//	DB-041 0.78/0.90, DBS-075 0.81/0.90, PI-097 0.16/0.58.
var recallFloors = map[string]float64{
	"NS-141": 0.85, "NS-118": 0.85, "NS-106": 0.40,
	"DB-041": 0.60, "DBS-075": 0.70, "PI-097": 0.15,
}

func TestBacktestAgainstRealHistory(t *testing.T) {
	history, hilo, waves := loadSummerFixtures(t)

	params, tallies := runBacktest(t, history, hilo, waves, nil, true)
	assertBacktestFloors(t, tallies, recallFloors, 0.60)

	// The persistence prior must learn from this span — the data shows a
	// ramp that rode out yesterday's tide mostly rides out today's — and
	// the open-side raise is where that signal lives.
	require.NotNil(t, params.Persistence, "persistence params should learn from five months of data")
	t.Logf("persistence: open raise=%.2f closed drop=%.2f n=%d acc=%.3f",
		params.Persistence.OpenRaiseFt, params.Persistence.ClosedDropFt,
		params.Persistence.NSamples, params.Persistence.Accuracy)
	assert.Greater(t, params.Persistence.OpenRaiseFt, 0.0,
		"open-yesterday suppression should be learnable from this span")

	// The wave regime split must actually learn from this span — Aug 17-18
	// style calm-flat false alarms are in the fixture data, so a nil or
	// zero-shift result is a real finding, not noise to delete.
	require.NotNil(t, params.Waves, "wave params should learn from five months of data")
	t.Logf("waves: calm<=%.2fft raise=%.2f  rough>=%.2fft drop=%.2f  n=%d acc=%.3f",
		params.Waves.CalmMaxFt, params.Waves.CalmRaiseFt,
		params.Waves.RoughMinFt, params.Waves.RoughDropFt,
		params.Waves.NSamples, params.Waves.Accuracy)
	assert.Greater(t, params.Waves.CalmRaiseFt, 0.0,
		"calm suppression should be learnable from this span")
}

// The tide-only path must keep reproducing the pre-wave engine: with no wave
// data at train or serve time, every floor still holds.
func TestBacktestTideOnlyFallback(t *testing.T) {
	history, hilo, _ := loadSummerFixtures(t)

	params, tallies := runBacktest(t, history, hilo, nil, nil, false)
	assertBacktestFloors(t, tallies, recallFloors, 0.50)
	assert.Nil(t, params.Waves, "no wave data must mean no wave params")
}

// The memoryless path must keep reproducing the pre-persistence engine:
// with no prior at serve time, every floor still holds.
func TestBacktestPersistenceOff(t *testing.T) {
	history, hilo, waves := loadSummerFixtures(t)

	_, tallies := runBacktest(t, history, hilo, waves, nil, false)
	assertBacktestFloors(t, tallies, recallFloors, 0.60)
}

// peakTally aggregates scorecard outcomes over many graded days.
type peakTally struct {
	n, closed, misses, likely, likelyRight int
	cost                                   float64
}

func (p *peakTally) add(pg PeakGrade) {
	switch pg.Outcome {
	case OutcomeStale:
		return // never graded
	case OutcomeHit:
		p.likelyRight++
		p.likely++
		p.closed++
	case OutcomeCovered:
		p.closed++
		p.cost += costCovered
	case OutcomeMiss:
		p.closed++
		p.misses++
		p.cost += costMiss
	case OutcomeFalseAlarm:
		p.likely++
		p.cost += costFalseAlarm
	case OutcomeHedged:
		p.cost += costHedged
	}
	p.n++
}

// score is gradeScore's scale over the tally: 1 is every call a hit or quiet.
func (p peakTally) score() float64 { return 1 - p.cost/(costMiss*float64(p.n)) }

func (p peakTally) precision() float64 { return float64(p.likelyRight) / float64(p.likely) }

func (p peakTally) String() string {
	return fmt.Sprintf("graded=%d closed=%d misses=%d likely=%d/%d score=%.3f",
		p.n, p.closed, p.misses, p.likelyRight, p.likely, p.score())
}

// walkForward grades every day in [from, to) the way production would have
// served it: params retrained each Monday on only the history before it (a
// weekly stand-in for the nightly trainer that keeps the test fast), each
// day's peaks graded by the scorecard. Tallies are keyed by "all" and by
// "YYYY-MM"; per-ramp recall counts ride alongside.
func walkForward(history map[string][]models.StatusEvent, hilo []models.TidePrediction, waves []models.WaveSample, levels []models.WaterLevelSample, from, to time.Time) (map[string]*peakTally, map[string]*peakTally) {
	tallies := map[string]*peakTally{}
	byRamp := map[string]*peakTally{}
	var params Params
	trained := false
	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		if !trained || d.Weekday() == time.Monday {
			params = Train(history, hilo, waves, levels, d, nil)
			trained = true
		}
		for _, rg := range BuildScorecard(d, history, nil, params, hilo, waves, levels, nil).Ramps {
			if byRamp[rg.AccessID] == nil {
				byRamp[rg.AccessID] = &peakTally{}
			}
			for _, pg := range rg.Peaks {
				for _, k := range []string{"all", d.Format("2006-01")} {
					if tallies[k] == nil {
						tallies[k] = &peakTally{}
					}
					tallies[k].add(pg)
				}
				byRamp[rg.AccessID].add(pg)
			}
		}
	}
	return tallies, byRamp
}

// The water-level anomaly, graded county-wide on the production tide
// station: all 27 ramps, May–Sep 2026, walk-forward. The anomaly exists for
// king-tide season — September ran +0.4–0.8 ft over prediction for weeks and
// +1.2 ft on 9/24, and the predicted-tide engine missed whole days of
// closures under it — but it has to earn its keep all season, so the whole
// span is graded and the surge engine must beat the predicted-tide engine
// on the metrics the outcome taxonomy cares about.
//
// This needs the county-wide pool. On the six-ramp summer fixture the
// anomaly soaks up the storm days that taught the rough-water drop, the drop
// trains to zero, and PI-097 (whose recall is all rough-water drop) loses
// it; with 27 ramps the drop still learns and PI-097 improves.
//
// Measured 2026-09-25 (weekly retrain as below): misses 111 → 21, likely
// precision 0.593 → 0.742, grade score 0.857 → 0.892 and better in every
// month; September misses 28 → 4. Daily retrain agrees (114 → 28). Two ramps
// gave recall back — DBS-067 (1.00 → 0.83, twelve closures) and NS-106
// (0.80 → 0.74) — both on normal-water days, as training on real water
// raised their bars; 22 ramps gained.
func TestBacktestSurgeCounty(t *testing.T) {
	history := loadHistoryFile(t, "testdata/history_county.json")
	hilo := loadHiloFile(t, "testdata/hilo_8721164.json")
	waves := loadWavesFixture(t)
	levels := loadLevelsFixture(t)

	from := time.Date(2026, 5, 1, 0, 0, 0, 0, eastern)
	to := time.Date(2026, 9, 25, 0, 0, 0, 0, eastern)
	off, offRamps := walkForward(history, hilo, waves, nil, from, to)
	surge, surgeRamps := walkForward(history, hilo, waves, levels, from, to)

	for _, k := range []string{"2026-05", "2026-06", "2026-07", "2026-08", "2026-09", "all"} {
		t.Logf("%-7s off   %s", k, off[k])
		t.Logf("%-7s surge %s", k, surge[k])
	}
	// The headline claims, pinned below the measured run so the weekly
	// retrain and small fixture refreshes don't flake them.
	assert.LessOrEqual(t, surge["all"].misses*3, off["all"].misses, "surge should cut misses by at least two thirds")
	assert.GreaterOrEqual(t, surge["all"].score(), off["all"].score()+0.02, "surge should grade clearly better")
	assert.GreaterOrEqual(t, surge["all"].precision(), off["all"].precision(), "'likely' must not get less trustworthy")
	assert.LessOrEqual(t, surge["2026-09"].misses, 8, "king-tide season is the point")
	for _, k := range []string{"2026-05", "2026-06", "2026-07", "2026-08", "2026-09"} {
		assert.GreaterOrEqual(t, surge[k].score(), off[k].score()-0.005, "%s: surge should never grade worse than the predicted-tide engine", k)
	}

	// No ramp may give back much recall for the county's gain. The worst
	// measured is DBS-067 (−0.17, twelve closures).
	for id, o := range offRamps {
		s := surgeRamps[id]
		offRecall := 1 - float64(o.misses)/float64(max(o.closed, 1))
		surgeRecall := 1 - float64(s.misses)/float64(max(s.closed, 1))
		t.Logf("%-8s closed=%3d recall off=%.2f surge=%.2f", id, o.closed, offRecall, surgeRecall)
		assert.GreaterOrEqual(t, surgeRecall, offRecall-0.20, "%s gave back too much recall", id)
	}

	params := Train(history, hilo, waves, levels, to, nil)
	require.NotNil(t, params.Surge)
	assert.Len(t, params.Surge.BaselineFt, 2, "both gauges should baseline")
	require.NotNil(t, params.Waves)
	assert.Greater(t, params.Waves.RoughDropFt, 0.0, "county-wide, surge must not absorb the rough-water drop")
	t.Logf("surge: %+v  waves: %+v  persistence: %+v", *params.Surge, *params.Waves, params.Persistence)
}

// statusAt is a ramp's status (and since when) at t, from its ascending
// history.
func statusAt(events []models.StatusEvent, t time.Time) (string, time.Time, bool) {
	i := sort.Search(len(events), func(i int) bool { return events[i].RecordedAt.After(t) })
	if i == 0 {
		return "", time.Time{}, false
	}
	return events[i-1].AccessStatus, events[i-1].RecordedAt, true
}

// latestWave is the newest buoy observation at or before t — what the
// live outlook would have read.
func latestWave(waves []models.WaveSample, t time.Time) *models.WaveSample {
	i := sort.Search(len(waves), func(i int) bool { return waves[i].Time.After(t) })
	if i == 0 {
		return nil
	}
	w := waves[i-1]
	return &w
}

// fallTally grades what the outlook would have served, Sep 15–Nov 11 2026.
type fallTally struct {
	held, caught, flagged             int // pre-open "could keep it closed" vs shut at the open
	dayRight, dayWrong, promisedNever int // reopen quotes for ramps closed right now
	timed                             int
	timedAbsH                         float64
}

// servedFall replays the King Tide season the way production served it:
// params retrained each Monday on the history before it, the outlook built
// 90 minutes before each open (was the ramp held shut at the open?), and
// every tide closure's reopen quote served 20 minutes after posting (did it
// reopen mid-day, run to the close, or come in on time?). Ramp-days the
// staleness quarantine removes are skipped.
func servedFall(t *testing.T, history map[string][]models.StatusEvent, hilo []models.TidePrediction, waves []models.WaveSample, levels []models.WaterLevelSample, from, to time.Time) fallTally {
	t.Helper()
	sortWaveSamples(waves)
	ids := make([]string, 0, len(history))
	for id := range history {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	excl := findExclusions(history, to, nil)

	var ft fallTally
	var params Params
	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		if d.Equal(from) || d.Weekday() == time.Monday {
			params = Train(history, hilo, waves, levels, d, nil)
		}
		_, sched := buildSchedule(d.Add(5*time.Hour), params)
		require.NotNil(t, sched.OpensAt)
		dayEnd := d.AddDate(0, 0, 1)

		now := sched.OpensAt.Add(-90 * time.Minute)
		var ramps []models.RampStatusWithSince
		for i, id := range ids {
			if st, since, ok := statusAt(history[id], now); ok && !excl.excluded(id, d) {
				s := since
				ramps = append(ramps, models.RampStatusWithSince{RampStatus: models.RampStatus{ID: int64(i + 1), AccessID: id, AccessStatus: st}, StatusSince: &s})
			}
		}
		water, _ := params.withSurge(hilo, levels, now)
		prior := priorDayFacts(now, history, water, params.hardOpen(), nil)
		for _, ro := range BuildOutlook(now, ramps, params, hilo, latestWave(waves, now), levels, prior).Ramps {
			st, _, _ := statusAt(history[ro.AccessID], sched.OpensAt.Add(20*time.Minute))
			held := st == tideClosedStatus
			if held {
				ft.held++
			}
			if ro.openLate != nil {
				ft.flagged++
				if held {
					ft.caught++
				}
			}
		}

		for _, id := range ids {
			for _, c := range closureEvents(history[id]) {
				if c.closedAt.Before(d) || !c.closedAt.Before(dayEnd) || !c.closedAt.Before(*sched.ClosesAt) || c.closedAt.In(eastern).Hour() < 5 {
					continue
				}
				now := c.closedAt.Add(20 * time.Minute)
				_, s := buildSchedule(now, params)
				water, surge := params.withSurge(hilo, levels, now)
				var fresh *models.WaveSample
				if w := latestWave(waves, now); w != nil && now.Sub(w.Time) <= maxWaveAge {
					fresh = w
				}
				rp, _ := effectiveParams(id, nil, params)
				est := servedReopen(water, c.closedAt, now, surge, stormWater(surge, fresh), s, rp)
				if est.IsZero() {
					continue
				}
				var next string
				for _, e := range history[id] {
					if e.RecordedAt.Equal(c.reopenedAt) {
						next = e.AccessStatus
						break
					}
				}
				ranToClose := c.reopenedAt.IsZero() || next == dayCloseStatus || !c.reopenedAt.Before(s.ClosesAt.Add(-20*time.Minute))
				switch saidDay := est.After(*s.ClosesAt); {
				case saidDay && ranToClose:
					ft.dayRight++
				case saidDay:
					ft.dayWrong++
				case ranToClose:
					ft.promisedNever++
				default:
					ft.timed++
					ft.timedAbsH += est.Sub(c.reopenedAt).Abs().Hours()
				}
			}
		}
	}
	return ft
}

// King Tide season, 2026-09-15 → 11-11, county-wide on the production
// station: the fall review (2026-11-12) found the peak calls fine but the
// served story wrong on exactly the days people asked — mornings the county
// never opened with no warning, and reopen times quoted on days the beach
// stayed shut. Measured with this replay before → after the review:
// pre-open held mornings caught 288 → 516 of 596 at 0.89 precision;
// reopens promised but never delivered 240 → 80 (for 24 more wrong "may
// stay closed for the day"); quoted reopen error on the rest 1.37 → 1.07h.
// Peaks: "likely" precision 0.86 → 0.99 once days the ramp never opened
// stopped counting as "stayed open" (the last week of October, 0.70 →
// 0.97), at an unchanged miss count. Floors sit below the measured run.
func TestBacktestKingTideFall(t *testing.T) {
	history := loadHistoryFile(t, "testdata/history_county.json")
	hilo := loadHiloFile(t, "testdata/hilo_8721164.json")
	waves := loadWavesFixture(t)
	levels := loadLevelsFixture(t)
	from := time.Date(2026, 9, 15, 0, 0, 0, 0, eastern)
	to := time.Date(2026, 11, 12, 0, 0, 0, 0, eastern)

	ft := servedFall(t, history, hilo, waves, levels, from, to)
	t.Logf("pre-open: held %d caught %d flagged %d", ft.held, ft.caught, ft.flagged)
	t.Logf("reopen: for-the-day right %d wrong %d, promised-never %d, timed %d mean |err| %.2fh",
		ft.dayRight, ft.dayWrong, ft.promisedNever, ft.timed, ft.timedAbsH/float64(ft.timed))

	peaks, _ := walkForward(history, hilo, waves, levels, from, to)
	t.Logf("peaks: %s precision %.3f", peaks["all"], peaks["all"].precision())

	assert.GreaterOrEqual(t, ft.caught, 480, "most mornings the county never opened should have been warned")
	assert.GreaterOrEqual(t, float64(ft.caught)/float64(ft.flagged), 0.85, "a pre-open warning should usually come true")
	assert.LessOrEqual(t, ft.promisedNever, 100, "reopen times quoted on days the beach stayed shut")
	assert.LessOrEqual(t, ft.dayWrong, 45, "'may stay closed for the day' on days it reopened")
	assert.LessOrEqual(t, ft.timedAbsH/float64(ft.timed), 1.2, "quoted reopen error, hours")
	assert.LessOrEqual(t, peaks["all"].misses, 5)
	assert.GreaterOrEqual(t, peaks["all"].precision(), 0.95)
}
