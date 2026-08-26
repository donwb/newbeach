package predict

import (
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// maxPersistShiftFt clamps each learned persistence shift. It is wider than
// the wave clamp because the observed effect is bigger — a ramp that rode
// out yesterday's tide needs a clearly higher one to close today — but the
// hard cutoffs still never move, so an extreme tide flags whatever
// happened yesterday.
const maxPersistShiftFt = 1.5

// priorAnchorToleranceFt is how much higher than yesterday's max peak a
// future day's peak may be and still count as "the tide the ramp already
// rode out" when the weekend planner carries the open-yesterday raise
// forward. Day-to-day peak deltas are almost all within ±0.25 ft.
const priorAnchorToleranceFt = 0.25

// PriorDay is what one ramp did on the previous Eastern calendar day — the
// serve-time input to the persistence prior.
type PriorDay struct {
	// Closed is true when the ramp was tide-closed around any daytime peak
	// yesterday (same labeling as training, labelPeaks).
	Closed bool `json:"closed"`
	// MaxPeakFt is yesterday's highest daytime predicted peak — the anchor
	// the weekend planner compares future peaks against.
	MaxPeakFt float64 `json:"max_peak_ft"`
	// Known is false when yesterday carries no evidence: no history coverage,
	// no daytime peak, or a peak below the hard-open cutoff (nothing could
	// have closed, so "stayed open" says nothing). Unknown → shift 0.
	Known bool `json:"known"`
}

// YesterdayContext is the per-ramp payload echo of the prior, present when
// the prior was computed for the ramp, so an operator can see what the
// model saw. Applied reports whether it actually moved the threshold.
type YesterdayContext struct {
	Closed  bool    `json:"closed"`
	PeakFt  float64 `json:"peak_ft"`
	Applied bool    `json:"applied"`
}

// priorDayFacts derives each ramp's PriorDay for the Eastern calendar day
// before `date`. historyByRamp must be ascending per ramp and should cover
// yesterday — a ramp whose first event is after yesterday's end is unknown.
// preds are any hilo predictions covering yesterday. hardOpenFt is the
// no-evidence floor (params.hardOpen()). excludedDays (ParseExcludedDays;
// nil is fine) joins the staleness heuristics: a stale yesterday is unknown,
// never evidence of "stayed open".
func priorDayFacts(date time.Time, historyByRamp map[string][]models.StatusEvent, preds []models.TidePrediction, hardOpenFt float64, excludedDays map[string]bool) map[string]PriorDay {
	et := date.In(eastern)
	dayStart := time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern).AddDate(0, 0, -1)
	dayEnd := dayStart.AddDate(0, 0, 1)
	excl := findExclusions(historyByRamp, date, excludedDays)

	var yPeaks []models.TidePrediction
	maxPeak := 0.0
	for _, p := range tidePeaks(preds) {
		if !p.Time.Before(dayStart) && p.Time.Before(dayEnd) {
			yPeaks = append(yPeaks, p)
			if *p.Height > maxPeak {
				maxPeak = *p.Height
			}
		}
	}

	out := make(map[string]PriorDay, len(historyByRamp))
	for id, events := range historyByRamp {
		pd := PriorDay{MaxPeakFt: maxPeak}
		if len(yPeaks) == 0 || len(events) == 0 || !events[0].RecordedAt.Before(dayEnd) || maxPeak <= hardOpenFt || excl.excluded(id, dayStart) {
			out[id] = pd
			continue
		}
		// Only yesterday's events decide yesterday: anything at or after
		// today's midnight is dropped so today never leaks into its own
		// prior (the backtest and scorecard replay with full history).
		var evs []models.StatusEvent
		for _, e := range events {
			if e.RecordedAt.Before(dayEnd) {
				evs = append(evs, e)
			}
		}
		pd.Known = true
		for _, closed := range labelPeaks(yPeaks, closureEvents(evs)) {
			if closed {
				pd.Closed = true
				break
			}
		}
		out[id] = pd
	}
	return out
}

// persistShift maps a ramp's prior day to the effective-threshold shift:
// positive when it rode out yesterday's tide (more tide needed to close
// today), negative when it closed. The ramp's own learned shifts win over
// the county-wide ones. Unknown prior or unlearned params → 0 → exactly
// the memoryless model.
func (p Params) persistShift(prior PriorDay, rp RampParams) float64 {
	pp := rp.Persistence
	if pp == nil {
		pp = p.Persistence
	}
	if !prior.Known || pp == nil {
		return 0
	}
	if prior.Closed {
		return -clampPersist(pp.ClosedDropFt)
	}
	return clampPersist(pp.OpenRaiseFt)
}

// persistDayShift is the weekend planner's version: anchored on yesterday's
// peak height so the prior switches off once the tide cycle pushes higher.
// Today gets the full shift. For a future day the open-yesterday raise only
// applies while that day's peak is no higher than the one the ramp already
// rode out (plus tolerance) — a forecast must never promise openness it
// can't back — and the closed-yesterday drop, a hedge, carries one day.
func (p Params) persistDayShift(prior PriorDay, rp RampParams, dayPeakFt float64, daysOut int) float64 {
	shift := p.persistShift(prior, rp)
	switch {
	case daysOut <= 0:
		return shift
	case shift > 0 && dayPeakFt > prior.MaxPeakFt+priorAnchorToleranceFt:
		return 0
	case shift < 0 && daysOut > 1:
		return 0
	}
	return shift
}

func clampPersist(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > maxPersistShiftFt {
		return maxPersistShiftFt
	}
	return v
}
