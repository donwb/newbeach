package predict

import (
	"fmt"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// All outlook prose is generated here. The rules: times are approximate —
// always rounded to the half hour and softened with "around"/"by"/"~",
// never minute-precise promises (the county is too inconsistent for those);
// hedged verbs per risk level ("likely" closes, "could" close — never
// "will"); reopens are always "often back open ...". Clients render these
// strings verbatim so every platform tells the same story.

// fmtClock formats an Eastern instant casually: "1pm", "1:30pm", "11am".
func fmtClock(t time.Time) string {
	et := t.In(eastern)
	h12 := et.Hour() % 12
	if h12 == 0 {
		h12 = 12
	}
	ampm := "am"
	if et.Hour() >= 12 {
		ampm = "pm"
	}
	if et.Minute() == 0 {
		return fmt.Sprintf("%d%s", h12, ampm)
	}
	return fmt.Sprintf("%d:%02d%s", h12, et.Minute(), ampm)
}

// clockRange renders "1–4:30pm", dropping the first meridiem when both ends
// share it ("11am–1:30pm" otherwise).
func clockRange(start, end time.Time) string {
	s := fmtClock(start)
	if (start.In(eastern).Hour() >= 12) == (end.In(eastern).Hour() >= 12) {
		s = strings.TrimSuffix(strings.TrimSuffix(s, "am"), "pm")
	}
	return s + "–" + fmtClock(end)
}

// roundNearest30 snaps a display time to the nearest half hour — the copy's
// way of promising less precision than the math produced.
func roundNearest30(t time.Time) time.Time {
	return t.Round(30 * time.Minute)
}

// scheduleCopy is the "no tide trouble" detail line.
func scheduleCopy(sched Schedule) string {
	return "Open for driving until " + sched.ClosesLabel
}

// riskText builds the headline, detail, and short board hint for a ramp
// that is not currently closed.
func riskText(risk string, peak *models.TidePrediction, rp RampParams, sched Schedule, laterPeakRisky bool) (headline, detail, short string) {
	switch risk {
	case RiskLikely:
		closeAt := roundNearest30(peak.Time.Add(-time.Duration(rp.LeadMin) * time.Minute))
		reopenAt := roundNearest30(peak.Time.Add(time.Duration(rp.LagMin) * time.Minute))
		headline = "High-tide closure likely around " + fmtClock(closeAt)
		if sched.ClosesAt != nil && reopenAt.After(*sched.ClosesAt) {
			detail = "Might not reopen before the day's " + sched.ClosesLabel + " close"
		} else {
			detail = "Often back open by " + fmtClock(reopenAt) + " once the tide drops"
		}
		short = "closure likely ~" + fmtClock(closeAt)
	case RiskPossible:
		peakAt := roundNearest30(peak.Time)
		headline = "Could close around the " + fmtClock(peakAt) + " high tide"
		detail = "Depends on surf and sand · could just as well stay open"
		short = "could close ~" + fmtClock(peakAt)
	default:
		headline = "No tide trouble expected"
		detail = scheduleCopy(sched)
	}
	if laterPeakRisky && risk != RiskNone {
		detail += " · the next high tide could bring another round"
	}
	return headline, detail, short
}

// closedNowText builds the copy for a ramp that is tide-closed right now.
func closedNowText(reopen time.Time, sched Schedule) (headline, detail string, r *Reopen) {
	headline = "Closed for high tide"
	if reopen.IsZero() {
		detail = "Reopening depends on the county getting back out there"
		return headline, detail, nil
	}
	label := "often back open around " + fmtClock(roundNearest30(reopen))
	if sched.ClosesAt != nil && reopen.After(*sched.ClosesAt) {
		label = "may stay closed for the day"
	}
	detail = "The tide is the boss here · " + label
	return headline, detail, &Reopen{Label: label}
}
