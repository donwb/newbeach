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

func TestBacktestAgainstRealHistory(t *testing.T) {
	history := loadHistoryFixture(t)
	hilo := loadHiloFixture(t)

	trainedAt := time.Date(2026, 8, 16, 0, 0, 0, 0, eastern)
	params := Train(history, hilo, trainedAt)
	require.NotEmpty(t, params.Ramps, "fixture ramps should all learn")

	ramps := make([]models.RampStatusWithSince, 0, len(history))
	firstDay := trainedAt
	for id, evs := range history {
		ramps = append(ramps, ramp(int64(len(ramps)+1), id, "OPEN"))
		if evs[0].RecordedAt.Before(firstDay) {
			firstDay = evs[0].RecordedAt
		}
	}

	type tally struct {
		closures, flagged       int // closure days, and those flagged possible/likely
		likelyDays, likelyRight int // days flagged likely, and those that closed
		noneDays, noneRight     int // days flagged none, and those that stayed open
	}
	tallies := make(map[string]*tally)
	for id := range history {
		tallies[id] = &tally{}
	}
	actual := make(map[string]map[string]bool)
	for id, evs := range history {
		actual[id] = actualClosureDays(evs)
	}

	for day := firstDay.In(eastern).AddDate(0, 0, 1); day.Before(trainedAt); day = day.AddDate(0, 0, 1) {
		at := time.Date(day.Year(), day.Month(), day.Day(), 9, 0, 0, 0, eastern)
		out := BuildOutlook(at, ramps, params, hilo)
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
			case RiskNone:
				tl.noneDays++
				if !closed {
					tl.noneRight++
				}
			}
		}
	}

	// Recall floors pinned a few points below the measured run (see t.Log
	// output) so noise doesn't flake the build. The mid-band ramps' misses
	// are surf-driven closures that tide-only features can't see — floors
	// stay honest about that until wave data joins the model.
	// Measured 2026-08-16: NS-141 0.93, NS-118 0.93, NS-106 0.48,
	// DB-041 0.71, DBS-075 0.76, PI-097 0.21.
	recallFloor := map[string]float64{
		"NS-141": 0.85, "NS-118": 0.85, "NS-106": 0.40,
		"DB-041": 0.60, "DBS-075": 0.70, "PI-097": 0.15,
	}

	for id, tl := range tallies {
		require.Greater(t, tl.closures, 0, "%s: fixture should contain closures", id)
		recall := float64(tl.flagged) / float64(tl.closures)
		t.Logf("%-8s closure days=%3d recall=%.2f  likely: %d/%d right  none: %d/%d right",
			id, tl.closures, recall, tl.likelyRight, tl.likelyDays, tl.noneRight, tl.noneDays)

		assert.GreaterOrEqual(t, recall, recallFloor[id], "%s recall regressed", id)

		// Calibration: "likely" and "none" should each be right more often
		// than wrong. Mid-band ramps hover near 0.55-0.6 on "none" — the
		// tide-blind surf closures again. Only assert on real samples.
		if tl.likelyDays >= 10 {
			assert.GreaterOrEqual(t, float64(tl.likelyRight)/float64(tl.likelyDays), 0.50,
				"%s: 'likely' is poorly calibrated", id)
		}
		if tl.noneDays >= 10 {
			assert.GreaterOrEqual(t, float64(tl.noneRight)/float64(tl.noneDays), 0.50,
				"%s: 'none' days keep closing anyway", id)
		}
	}
}
