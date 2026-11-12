//go:build assess

// Assessment harness (build tag `assess`, never run by CI). Walks the county
// fixtures day by day with params retrained nightly on only the history
// before each day, and dumps JSON lines for offline analysis: every scorecard
// grade, the stale days, served-style replays (pre-open / 9am / 1pm), and
// every tide closure's served reopen quote. Summarize with
// scripts/predict-assess.py; refresh the fixtures first (cmd/gen-*-fixture).
//
//	ASSESS_DIR=/tmp/assess go test -tags assess -run TestAssessDump -count=1 ./internal/predict/
//	ASSESS_COPY=1 go test -tags assess -run TestAssessCopy -v ./internal/predict/
package predict

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/stretchr/testify/require"
)

type assessOut struct{ w map[string]*bufio.Writer }

func (a *assessOut) put(name string, v any) {
	b, _ := json.Marshal(v)
	a.w[name].Write(b)
	a.w[name].WriteByte('\n')
}

func TestAssessDump(t *testing.T) {
	dir := os.Getenv("ASSESS_DIR")
	if dir == "" {
		t.Skip("ASSESS_DIR not set")
	}
	history := loadHistoryFile(t, "testdata/history_county.json")
	hilo := loadHiloFile(t, "testdata/hilo_8721164.json")
	waves := loadWavesFixture(t)
	sortWaveSamples(waves)
	levels := loadLevelsFixture(t)
	if os.Getenv("ASSESS_NO_SURGE") != "" {
		levels = nil
	}

	out := &assessOut{w: map[string]*bufio.Writer{}}
	for _, n := range []string{"grades", "served", "reopen", "params", "stale"} {
		f, err := os.Create(filepath.Join(dir, n+".jsonl"))
		require.NoError(t, err)
		defer f.Close()
		out.w[n] = bufio.NewWriter(f)
		defer out.w[n].Flush()
	}

	ids := make([]string, 0, len(history))
	for id := range history {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	closuresByRamp := map[string][]closureEvent{}
	for _, id := range ids {
		closuresByRamp[id] = closureEvents(history[id])
	}

	from := time.Date(2026, 5, 1, 0, 0, 0, 0, eastern)
	if s := os.Getenv("ASSESS_FROM"); s != "" {
		from, _ = time.ParseInLocation("2006-01-02", s, eastern)
	}
	to := time.Date(2026, 11, 12, 0, 0, 0, 0, eastern)

	// Stale days as the final trainer sees them.
	excl := findExclusions(history, to, nil)
	for id, days := range excl.stale {
		for d := range days {
			out.put("stale", map[string]any{"ramp": id, "day": d})
		}
	}

	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		params := Train(history, hilo, waves, levels, d, nil)
		day := d.Format("2006-01-02")
		for id, rp := range params.Ramps {
			out.put("params", map[string]any{"day": day, "ramp": id, "th": rp.ThresholdFt, "lead": rp.LeadMin, "lag": rp.LagMin, "rate": rp.CloseRate, "n": rp.NClosures})
		}
		out.put("params", map[string]any{"day": day, "ramp": "_county", "hard_open": params.HardOpenFt, "hard_close": params.HardCloseFt, "close_off": params.DayCloseOffsetMin, "waves": params.Waves, "persist": params.Persistence, "surge": params.Surge})

		sc := BuildScorecard(d, history, nil, params, hilo, waves, levels, nil)
		for _, rg := range sc.Ramps {
			for _, pg := range rg.Peaks {
				out.put("grades", map[string]any{"day": day, "ramp": rg.AccessID, "th": rg.ThresholdFt, "g": pg})
			}
		}

		// Served replays.
		_, sched := buildSchedule(d.Add(5*time.Hour), params)
		if sched.OpensAt == nil || sched.ClosesAt == nil {
			continue
		}
		dayEnd := d.AddDate(0, 0, 1)
		probes := map[string]time.Time{
			"preopen": sched.OpensAt.Add(-90 * time.Minute),
			"0900":    d.Add(9 * time.Hour),
			"1300":    d.Add(13 * time.Hour),
		}
		for label, now := range probes {
			ramps := make([]models.RampStatusWithSince, 0, len(ids))
			for i, id := range ids {
				st, since, ok := statusAt(history[id], now)
				if !ok {
					continue
				}
				s := since
				ramps = append(ramps, models.RampStatusWithSince{RampStatus: models.RampStatus{ID: int64(i + 1), AccessID: id, AccessStatus: st}, StatusSince: &s})
			}
			water, _ := params.withSurge(hilo, levels, now)
			prior := priorDayFacts(now, history, water, params.hardOpen(), nil)
			ol := BuildOutlook(now, ramps, params, hilo, latestWave(waves, now), levels, prior)
			for i, ro := range ol.Ramps {
				id := ro.AccessID
				st := ramps[i].AccessStatus
				// Truth: tide closures that begin after now and before the
				// day's (actual) end; and status at open+20m for preopen.
				var firstClose *time.Time
				for _, c := range closuresByRamp[id] {
					if c.closedAt.After(now) && c.closedAt.Before(dayEnd) && c.closedAt.In(eastern).Hour() >= 5 {
						cc := c.closedAt
						firstClose = &cc
						break
					}
				}
				rec := map[string]any{
					"day": day, "probe": label, "ramp": id, "status": st, "risk": ro.Risk, "reason": ro.Reason,
					"headline": ro.Headline, "detail": ro.Detail, "first_close": firstClose,
					"quoted_close": ro.quotedClose, "open_late": ro.openLate, "window": ro.Window,
					"opens": sched.OpensAt, "closes": sched.ClosesAt, "stale": excl.excluded(id, d),
				}
				if ol.Surge != nil {
					rec["surge"] = ol.Surge.AnomalyFt
				}
				if label == "preopen" {
					st2, _, _ := statusAt(history[id], sched.OpensAt.Add(20*time.Minute))
					rec["status_at_open"] = st2
					// When did it first become non-blocking after the open?
					for _, e := range history[id] {
						if e.RecordedAt.After(*sched.OpensAt) && e.RecordedAt.Before(dayEnd) && e.AccessStatus != tideClosedStatus && e.AccessStatus != turtleClearedStatus && e.AccessStatus != dayCloseStatus {
							at := e.RecordedAt
							rec["opened_at"] = &at
							break
						}
					}
				}
				out.put("served", rec)
			}
		}

		// Reopen replays: every tide closure that starts this day, served 20
		// minutes after posting.
		for _, id := range ids {
			for _, c := range closuresByRamp[id] {
				if c.closedAt.Before(d) || !c.closedAt.Before(dayEnd) {
					continue
				}
				now := c.closedAt.Add(20 * time.Minute)
				_, s := buildSchedule(now, params)
				water, surge := params.withSurge(hilo, levels, now)
				var fw *models.WaveSample
				if w := latestWave(waves, now); w != nil && now.Sub(w.Time) <= maxWaveAge {
					fw = w
				}
				rp, _ := effectiveParams(id, nil, params)
				est := servedReopen(water, c.closedAt, now, surge, stormWater(surge, fw), s, rp)
				next := ""
				for _, e := range history[id] {
					if e.RecordedAt.Equal(c.reopenedAt) {
						next = e.AccessStatus
						break
					}
				}
				rec := map[string]any{"day": day, "ramp": id, "closed_at": c.closedAt, "reopened_at": c.reopenedAt, "next": next, "est": est, "closes": s.ClosesAt, "opens": s.OpensAt}
				if surge != nil {
					rec["surge"] = surge.AnomalyFt
				}
				// Nearest high to the closure (predicted + effective heights).
				for i := range hilo {
					p := hilo[i]
					if p.Type == "H" && p.Height != nil && p.Time.Sub(c.closedAt).Abs() <= peakMatchWindow {
						rec["peak_at"] = p.Time
						rec["peak_ft"] = *p.Height
						rec["water_ft"] = *water[i].Height
						break
					}
				}
				out.put("reopen", rec)
			}
		}
	}
}

// TestAssessCopy prints the served copy for a few instants (ASSESS_COPY=1).
func TestAssessCopy(t *testing.T) {
	if os.Getenv("ASSESS_COPY") == "" {
		t.Skip()
	}
	history := loadHistoryFile(t, "testdata/history_county.json")
	hilo := loadHiloFile(t, "testdata/hilo_8721164.json")
	waves := loadWavesFixture(t)
	sortWaveSamples(waves)
	levels := loadLevelsFixture(t)
	ids := []string{"NS-141", "NS-106", "DB-041", "OB-036", "PI-097"}
	for _, s := range []string{"2026-10-19 06:30", "2026-10-19 09:30", "2026-10-26 06:30", "2026-10-26 09:00", "2026-11-10 05:15", "2026-11-08 13:00", "2026-10-12 06:30"} {
		now, _ := time.ParseInLocation("2006-01-02 15:04", s, eastern)
		day := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, eastern)
		params := Train(history, hilo, waves, levels, day, nil)
		var ramps []models.RampStatusWithSince
		for i, id := range ids {
			st, since, _ := statusAt(history[id], now)
			ramps = append(ramps, models.RampStatusWithSince{RampStatus: models.RampStatus{ID: int64(i + 1), AccessID: id, AccessStatus: st, City: "X"}, StatusSince: &since})
		}
		water, _ := params.withSurge(hilo, levels, now)
		ol := BuildOutlook(now, ramps, params, hilo, latestWave(waves, now), levels, priorDayFacts(now, history, water, params.hardOpen(), nil))
		t.Logf("=== %s  surge %+.2f", s, func() float64 {
			if ol.Surge != nil {
				return ol.Surge.AnomalyFt
			}
			return 0
		}())
		for i, ro := range ol.Ramps {
			t.Logf("  %-7s [%s] %-10s %s · %s", ro.AccessID, ramps[i].AccessStatus, ro.Risk, ro.Headline, ro.Detail)
		}
	}
}
