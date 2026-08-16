package predict

import (
	"math"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/solar"
)

// Risk levels, mildest first. closed_now is factual: the ramp is tide-closed
// right now, so the outlook carries a reopen estimate instead of a window.
const (
	RiskNone      = "none"
	RiskPossible  = "possible"
	RiskLikely    = "likely"
	RiskClosedNow = "closed_now"
)

// Hard county-wide rules from the historical analysis: peaks at or above
// hardCloseFt closed essentially everything; peaks at or below hardOpenFt
// closed nothing.
const (
	hardCloseFt = 3.5
	hardOpenFt  = 2.0

	// hysteresisFt is the half-width of the "could go either way" band
	// around a ramp's learned threshold.
	hysteresisFt = 0.3

	// midRangeFt/midRangeCloseRate: below its threshold band, a ramp that
	// still closes this often around peaks keeps a "possible" instead of
	// "none" once the peak reaches the county's observed action zone.
	midRangeFt        = 2.4
	midRangeCloseRate = 0.35

	// windowPadding is added on both sides of the learned lead/lag offsets
	// so the window reads as the rough stretch it is.
	windowPadding = 45 * time.Minute

	// reopenAfterLow is the fallback reopen estimate: the county tends to
	// reopen roughly this long after the low tide that follows a closure.
	reopenAfterLow = 90 * time.Minute
)

// Window is a coarse predicted closure window, pre-rounded to half hours so
// clients can shade it without implying precision.
type Window struct {
	Label string    `json:"label"`
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}

// Reopen carries only a casual label — never a clock time.
type Reopen struct {
	Label string `json:"label"`
}

// RampOutlook is one ramp's tide outlook for the rest of the driving day.
type RampOutlook struct {
	AccessID   string  `json:"access_id"`
	RampID     int64   `json:"ramp_id"`
	Risk       string  `json:"risk"`
	Confidence string  `json:"confidence"`
	Headline   string  `json:"headline"`
	Detail     string  `json:"detail,omitempty"`
	Window     *Window `json:"window,omitempty"`
	Reopen     *Reopen `json:"reopen,omitempty"`
}

// Schedule is the driving-hours frame for the day: fixed clock hours in
// turtle season, sunrise-to-sunset otherwise.
type Schedule struct {
	OpensLabel  string     `json:"opens_label"`
	ClosesLabel string     `json:"closes_label"`
	OpensAt     *time.Time `json:"opens_at,omitempty"`
	ClosesAt    *time.Time `json:"closes_at,omitempty"`
}

// TideContext is the shared tide backdrop for the outlook.
type TideContext struct {
	NextPeakFt *float64   `json:"next_peak_ft,omitempty"`
	NextPeakAt *time.Time `json:"next_peak_at,omitempty"`
}

// Outlook is the full response served at /api/v2/outlook.
type Outlook struct {
	GeneratedAt time.Time     `json:"generated_at"`
	Season      string        `json:"season"`
	Schedule    Schedule      `json:"schedule"`
	Tide        TideContext   `json:"tide"`
	Ramps       []RampOutlook `json:"ramps"`
}

// inTurtleSeason reports whether the Eastern date falls in Volusia County's
// sea-turtle nesting season, May 1 through October 31.
func inTurtleSeason(t time.Time) bool {
	m := t.In(eastern).Month()
	return m >= time.May && m <= time.October
}

// buildSchedule derives the day's driving-hours frame.
func buildSchedule(now time.Time) (string, Schedule) {
	et := now.In(eastern)

	if inTurtleSeason(now) {
		opens := time.Date(et.Year(), et.Month(), et.Day(), 8, 0, 0, 0, eastern)
		closes := time.Date(et.Year(), et.Month(), et.Day(), 19, 0, 0, 0, eastern)
		if et.After(closes) {
			opens = opens.AddDate(0, 0, 1)
			closes = closes.AddDate(0, 0, 1)
		}
		return "turtle", Schedule{
			OpensLabel:  "around 8am, once ramps are cleared for turtles",
			ClosesLabel: "7pm",
			OpensAt:     &opens,
			ClosesAt:    &closes,
		}
	}

	sunrise, sunset := solar.Events(now, solar.NSB)
	sched := Schedule{
		OpensLabel:  "around sunrise",
		ClosesLabel: "around sunset",
	}
	if sunrise != nil && sunset != nil {
		closes := sunset.Add(-15 * time.Minute)
		if now.After(closes) {
			nextRise, nextSet := solar.Events(now.AddDate(0, 0, 1), solar.NSB)
			if nextRise != nil && nextSet != nil {
				c := nextSet.Add(-15 * time.Minute)
				sched.OpensAt = nextRise
				sched.ClosesAt = &c
			}
		} else {
			sched.OpensAt = sunrise
			sched.ClosesAt = &closes
		}
	}
	return "standard", sched
}

// effectiveParams resolves a ramp's parameters: learned when available,
// county default otherwise, with an operator-set closure height from
// ramp_metadata overriding the learned threshold.
func effectiveParams(ramp models.RampStatusWithSince, params Params) (RampParams, bool) {
	rp, learned := params.Ramps[ramp.AccessID]
	if !learned {
		rp = params.Default
	}
	if ramp.ClosureHeightFt != nil && *ramp.ClosureHeightFt > 0 {
		rp.ThresholdFt = *ramp.ClosureHeightFt
		// The operator's threshold is authoritative — don't let the learned
		// base rate second-guess it via the mid-range rule.
		rp.CloseRate = 0
	}
	return rp, learned
}

// confidence buckets how much to trust a ramp's learned behavior.
func confidence(rp RampParams, learned bool) string {
	switch {
	case !learned || rp.NClosures < 10:
		return "low"
	case rp.Accuracy >= 0.7 && rp.NClosures >= 20:
		return "high"
	default:
		return "medium"
	}
}

// riskForPeak classifies one predicted peak against a ramp's parameters.
// hardOpen/hardClose are the county-wide cutoffs (learned percentiles of the
// peak distribution, so they track the configured station's height scale).
func riskForPeak(peakFt float64, rp RampParams, hardOpen, hardClose float64) string {
	switch {
	case peakFt >= hardClose:
		return RiskLikely
	case peakFt <= hardOpen:
		return RiskNone
	case peakFt >= rp.ThresholdFt+hysteresisFt:
		return RiskLikely
	case peakFt >= rp.ThresholdFt-hysteresisFt:
		return RiskPossible
	case peakFt >= midRangeFt && rp.CloseRate >= midRangeCloseRate:
		return RiskPossible
	default:
		return RiskNone
	}
}

func riskRank(r string) int {
	switch r {
	case RiskLikely:
		return 2
	case RiskPossible:
		return 1
	default:
		return 0
	}
}

// roundDown30/roundUp30 snap times to half-hour boundaries in Eastern time.
func roundDown30(t time.Time) time.Time {
	et := t.In(eastern)
	return et.Truncate(30 * time.Minute)
}

func roundUp30(t time.Time) time.Time {
	down := roundDown30(t)
	if down.Equal(t.In(eastern)) {
		return down
	}
	return down.Add(30 * time.Minute)
}

// closureWindow builds the coarse window around a peak, clamped to the
// driving day.
func closureWindow(peak models.TidePrediction, rp RampParams, sched Schedule) *Window {
	start := peak.Time.Add(-time.Duration(rp.LeadMin)*time.Minute - windowPadding)
	end := peak.Time.Add(time.Duration(rp.LagMin)*time.Minute + windowPadding)
	if sched.OpensAt != nil && start.Before(*sched.OpensAt) {
		start = *sched.OpensAt
	}
	if sched.ClosesAt != nil && end.After(*sched.ClosesAt) {
		end = *sched.ClosesAt
	}
	if !end.After(start) {
		return nil
	}
	start = roundDown30(start)
	end = roundUp30(end)
	return &Window{Label: windowLabel(start, end), Start: start, End: end}
}

// heightAtCos interpolates the tide height at t between hilo extremes using
// the half-cosine curve tides actually follow.
func heightAtCos(preds []models.TidePrediction, t time.Time) (float64, bool) {
	for i := 1; i < len(preds); i++ {
		p0, p1 := preds[i-1], preds[i]
		if p0.Height == nil || p1.Height == nil {
			continue
		}
		if t.Before(p0.Time) || t.After(p1.Time) {
			continue
		}
		span := p1.Time.Sub(p0.Time).Seconds()
		if span <= 0 {
			return *p0.Height, true
		}
		frac := t.Sub(p0.Time).Seconds() / span
		blend := (1 - math.Cos(frac*math.Pi)) / 2
		return *p0.Height + (*p1.Height-*p0.Height)*blend, true
	}
	return 0, false
}

// reopenEstimate ports the web client's falling-limb estimator: the water
// that forced the closure recedes to the same height on the way down, so the
// reopen estimate is the falling curve's return to the closure-time height.
// Fallback: the low tide after the closure plus the county-practice offset.
// Returns zero time when nothing applies.
func reopenEstimate(preds []models.TidePrediction, closedAt, now time.Time) time.Time {
	if closureHeight, ok := heightAtCos(preds, closedAt); ok {
		// Only meaningful when the closure precedes a high — i.e. the tide
		// was still coming up.
		var nextExt *models.TidePrediction
		for i := range preds {
			if preds[i].Time.After(closedAt) {
				nextExt = &preds[i]
				break
			}
		}
		if nextExt != nil && nextExt.Type == "H" {
			limit := closedAt.Add(30 * time.Hour)
			step := 5 * time.Minute
			prev := nextExt.Time
			for t := prev.Add(step); t.Before(limit); t = t.Add(step) {
				h, ok := heightAtCos(preds, t)
				if !ok {
					break
				}
				if h <= closureHeight {
					lo, hi := prev, t
					for i := 0; i < 20; i++ {
						mid := lo.Add(hi.Sub(lo) / 2)
						if m, ok := heightAtCos(preds, mid); ok && m <= closureHeight {
							hi = mid
						} else {
							lo = mid
						}
					}
					if hi.After(now) {
						return hi
					}
					break
				}
				prev = t
			}
		}
	}

	for _, p := range preds {
		if p.Type == "L" && p.Time.After(closedAt) {
			reopen := p.Time.Add(reopenAfterLow)
			if reopen.After(now) {
				return reopen
			}
			break
		}
	}
	return time.Time{}
}

// BuildOutlook computes the full outlook. preds are hilo predictions
// covering at least [now-1d, now+2d]; ramps come from
// GetRampsWithStatusSince. Pure — no I/O, fully testable.
func BuildOutlook(now time.Time, ramps []models.RampStatusWithSince, params Params, preds []models.TidePrediction) Outlook {
	season, sched := buildSchedule(now)

	out := Outlook{
		GeneratedAt: now.UTC(),
		Season:      season,
		Schedule:    sched,
		Ramps:       make([]RampOutlook, 0, len(ramps)),
	}

	// Shared tide context: the next high-tide peak from now.
	for i := range preds {
		if preds[i].Type == "H" && preds[i].Time.After(now) && preds[i].Height != nil {
			out.Tide.NextPeakFt = preds[i].Height
			t := preds[i].Time
			out.Tide.NextPeakAt = &t
			break
		}
	}

	// Peaks that could disturb the current driving day: highs between now
	// and the day's close.
	var dayPeaks []models.TidePrediction
	for _, p := range preds {
		if p.Type != "H" || p.Height == nil || !p.Time.After(now) {
			continue
		}
		if sched.ClosesAt != nil && p.Time.After(sched.ClosesAt.Add(time.Hour)) {
			continue
		}
		dayPeaks = append(dayPeaks, p)
	}

	for _, ramp := range ramps {
		rp, learned := effectiveParams(ramp, params)
		ro := RampOutlook{
			AccessID:   ramp.AccessID,
			RampID:     ramp.ID,
			Confidence: confidence(rp, learned),
		}

		if ramp.AccessStatus == tideClosedStatus {
			ro.Risk = RiskClosedNow
			closedAt := now
			if ramp.StatusSince != nil {
				closedAt = *ramp.StatusSince
			}
			reopen := reopenEstimate(preds, closedAt, now)
			ro.Headline, ro.Detail, ro.Reopen = closedNowText(reopen, sched)
			out.Ramps = append(out.Ramps, ro)
			continue
		}

		// Riskiest remaining peak wins; note a second troublesome peak.
		risk := RiskNone
		var riskPeak *models.TidePrediction
		var laterPeakRisky bool
		for i := range dayPeaks {
			r := riskForPeak(*dayPeaks[i].Height, rp, params.hardOpen(), params.hardClose())
			if riskRank(r) > riskRank(risk) {
				risk = r
				riskPeak = &dayPeaks[i]
			} else if riskPeak != nil && i > 0 && riskRank(r) >= 1 {
				laterPeakRisky = true
			}
		}

		ro.Risk = risk
		if riskPeak != nil && riskRank(risk) >= 1 {
			ro.Window = closureWindow(*riskPeak, rp, sched)
		}
		ro.Headline, ro.Detail = riskText(risk, riskPeak, ro.Window, sched, laterPeakRisky)
		out.Ramps = append(out.Ramps, ro)
	}

	return out
}
