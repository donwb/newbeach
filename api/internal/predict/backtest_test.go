package predict

import (
	"encoding/json"
	"os"
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
	raw, err := os.ReadFile("testdata/history.json")
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
	raw, err := os.ReadFile("testdata/hilo.json")
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

// runBacktest trains on the full fixture span and replays each day's 9am ET
// outlook against what actually happened. waves nil replays tide-only —
// exactly the pre-wave engine.
func runBacktest(t *testing.T, history map[string][]models.StatusEvent, hilo []models.TidePrediction, waves []models.WaveSample) (Params, map[string]*backtestTally) {
	t.Helper()

	trainedAt := time.Date(2026, 8, 16, 0, 0, 0, 0, eastern)
	params := Train(history, hilo, waves, trainedAt)
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
		out := BuildOutlook(at, ramps, params, hilo, waveNearTime(waves, at))
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
	history := loadHistoryFixture(t)
	hilo := loadHiloFixture(t)
	waves := loadWavesFixture(t)

	params, tallies := runBacktest(t, history, hilo, waves)
	assertBacktestFloors(t, tallies, recallFloors, 0.60)

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
	history := loadHistoryFixture(t)
	hilo := loadHiloFixture(t)

	params, tallies := runBacktest(t, history, hilo, nil)
	assertBacktestFloors(t, tallies, recallFloors, 0.50)
	assert.Nil(t, params.Waves, "no wave data must mean no wave params")
}
