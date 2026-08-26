package predict

import (
	"encoding/json"
	"log/slog"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

const (
	// turtleClearedStatus is the county's overnight turtle-season status. It
	// must match the GIS vocabulary exactly (see models.StatusToShort).
	turtleClearedStatus = "CLOSED - CLEARED FOR TURTLES"

	// staleOpenGrace: a blocking status still standing this long past the
	// posted open marks the ET day as stale — the county forgot to flip the
	// board, so the day carries no tide evidence. Two hours, not less: history
	// shows routine late opens up to ~9:50am that are real calls, not
	// clerical staleness.
	staleOpenGrace = 2 * time.Hour

	// ExcludedDaysKey is the settings-table key for manually quarantined
	// days: a JSON array of ET dates (["2026-08-26"]), county-wide. Editable
	// via POST /api/v2/admin/settings.
	ExcludedDaysKey = "prediction_excluded_days"
)

// ParseExcludedDays parses the manual exclusion setting. Empty or
// unparseable input yields nil (warn, never fail — a bad setting must not
// break training or serving); individually invalid dates are skipped.
func ParseExcludedDays(raw string) map[string]bool {
	if raw == "" {
		return nil
	}
	var days []string
	if err := json.Unmarshal([]byte(raw), &days); err != nil {
		slog.Warn("ignoring unparseable "+ExcludedDaysKey, "err", err)
		return nil
	}
	out := make(map[string]bool, len(days))
	for _, d := range days {
		if _, err := time.ParseInLocation("2006-01-02", d, eastern); err != nil {
			slog.Warn("skipping invalid date in "+ExcludedDaysKey, "date", d)
			continue
		}
		out[d] = true
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// exclusions is the merged quarantine of ET days whose recorded statuses are
// county clerical staleness rather than real beach calls. The zero value
// excludes nothing. Excluded days are dropped from peak labeling everywhere
// (training, scorecard, persistence prior) — "unknown", never "stayed open".
type exclusions struct {
	manual map[string]bool            // ET date → every ramp
	stale  map[string]map[string]bool // accessID → ET date
}

// excluded reports whether t's ET calendar day is quarantined for the ramp.
func (x exclusions) excluded(accessID string, t time.Time) bool {
	d := t.In(eastern).Format("2006-01-02")
	return x.manual[d] || x.stale[accessID][d]
}

// findExclusions runs the staleness heuristics over each ramp's ascending
// events and merges in the manually excluded days. now bounds the interval of
// each ramp's final status — a status standing at 9am today excludes nothing
// until the grace deadline has actually passed.
func findExclusions(historyByRamp map[string][]models.StatusEvent, now time.Time, manual map[string]bool) exclusions {
	x := exclusions{manual: manual}
	for id, events := range historyByRamp {
		if days := staleDaysForRamp(events, now); len(days) > 0 {
			if x.stale == nil {
				x.stale = make(map[string]map[string]bool)
			}
			x.stale[id] = days
		}
	}
	return x
}

// staleDaysForRamp finds a ramp's stale ET days. Two signatures, both "a
// blocking status still standing at open + staleOpenGrace":
//
//   - The overnight turtle status never flipped at the morning open (the
//     observed 2026-08-26 failure) — every day it stands past the grace
//     deadline is stale.
//   - A CLOSED FOR HIGH TIDE episode spanning past the NEXT day's open — the
//     county forgot to reopen. Day one keeps its real closure; the later
//     days are stale. This also bounds labelPeaks' otherwise unbounded
//     "during" clause, since peaks on stale days are filtered out upstream.
func staleDaysForRamp(events []models.StatusEvent, now time.Time) map[string]bool {
	days := make(map[string]bool)

	for i, e := range events {
		if e.AccessStatus != turtleClearedStatus {
			continue
		}
		end := now
		if i+1 < len(events) {
			end = events[i+1].RecordedAt
		}
		markStaleDays(days, e.RecordedAt, end, time.Time{})
	}

	for _, c := range closureEvents(events) {
		end := c.reopenedAt
		if end.IsZero() {
			end = now
		}
		markStaleDays(days, c.closedAt, end, c.closedAt)
	}

	if len(days) == 0 {
		return nil
	}
	return days
}

// markStaleDays marks every ET day in [start, end) whose open + grace
// deadline the interval contains. keep exempts one day (a tide episode's
// real first day); its zero value exempts nothing. postedHours failing
// (solar edge cases) fails safe: no exclusion.
func markStaleDays(days map[string]bool, start, end, keep time.Time) {
	keepDay := ""
	if !keep.IsZero() {
		keepDay = keep.In(eastern).Format("2006-01-02")
	}
	et := start.In(eastern)
	d := time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern)
	for ; d.Before(end); d = d.AddDate(0, 0, 1) {
		if d.Format("2006-01-02") == keepDay {
			continue
		}
		opens, _, ok := postedHours(d)
		if !ok {
			continue
		}
		deadline := opens.Add(staleOpenGrace)
		if !deadline.Before(start) && deadline.Before(end) {
			days[d.Format("2006-01-02")] = true
		}
	}
}
