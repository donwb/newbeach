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
// hedged verbs throughout — a tide closure is always "possible", never
// "likely" or "will", because the county's call is genuinely theirs to
// make; reopens are always "often back open ...". Every string names the
// reason (tide, end of day, overnight) and looks forward: this line is a
// prediction of the next thing to happen, never a report of the last one.
// Clients render these strings verbatim so every platform tells the same
// story.

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

// quietText is the copy for a ramp with nothing to warn about.
func quietText(sched Schedule) (headline, detail string) {
	return "No tide trouble expected", scheduleCopy(sched)
}

// beforeOpenText is the copy for the hours when the beach is not drivable
// at all — overnight and the stretch before the morning open. The next
// thing that happens is the open, so that is what it predicts.
func beforeOpenText(season string, sched Schedule) (headline, detail string, r *Reopen) {
	at := fmtClock(roundNearest30(*sched.OpensAt))
	headline = "Closed until morning"
	if season == "turtle" {
		detail = "Beach driving opens around " + at + ", once ramps are cleared for turtles"
	} else {
		detail = "Beach driving opens at sunrise, around " + at
	}
	return headline, detail, &Reopen{Label: "opens around " + at}
}

// endOfDayText is the copy for the day's close — the county clearing the
// beach at dark, which has nothing to do with the tide. The posted time is
// itself soft (they often start early), so it stays hedged like every other
// clock time here.
func endOfDayText(season string, sched Schedule) (headline, detail, short string) {
	at := fmtClock(roundNearest30(*sched.ClosesAt))
	if season == "turtle" {
		headline = "Beach driving closes for the day around " + at
	} else {
		headline = "Beach driving closes at sunset, around " + at
	}
	detail = "End of the driving day, not the tide · they often start clearing a bit early"
	short = "closes for the day ~" + at
	return headline, detail, short
}

// quotedCloseAt is the clock time the ramp copy quotes for a tide closure:
// the learned close (peak minus lead) when the tide is likely to shut the
// ramp, the peak itself when a closure is only possible. Rounded to the half
// hour like every time in the copy. The city verdict reuses it so the two
// layers never disagree about when trouble starts.
func quotedCloseAt(risk string, peak models.TidePrediction, rp RampParams) time.Time {
	if risk == RiskLikely {
		return roundNearest30(peak.Time.Add(-time.Duration(rp.LeadMin) * time.Minute))
	}
	return roundNearest30(peak.Time)
}

// tideText builds the headline, detail, and short board hint for a ramp the
// tide might close. The copy is time-aware: a learned close time the clock
// has already passed is never quoted back — the ramp is visibly still open,
// so the copy moves to "any time now", and once the peak itself is behind
// us it moves to the falling-tide voice. Every string names the tide as the
// cause, so a reader always knows why the closure is coming.
func tideText(now time.Time, risk string, peak models.TidePrediction, rp RampParams, sched Schedule, laterPeakRisky bool) (headline, detail, short string) {
	closeAt := quotedCloseAt(RiskLikely, peak, rp)
	reopenAt := roundNearest30(peak.Time.Add(time.Duration(rp.LagMin) * time.Minute))
	reopenCopy := "Often back open by " + fmtClock(reopenAt) + " once the tide drops"
	if sched.ClosesAt != nil && reopenAt.After(*sched.ClosesAt) {
		reopenCopy = "Might not reopen before the day's " + sched.ClosesLabel + " close"
	}

	switch {
	case !now.Before(peak.Time):
		// The high is behind us and the ramp is still open — it has beaten
		// this tide so far, but the county does close late sometimes.
		headline = "Could still close while the tide drops"
		detail = "Past the high now · the odds fall with the water"
		short = "tide closure still possible"
	case risk == RiskLikely && !now.Before(closeAt):
		// The learned close time came and went with the ramp still open.
		// Say that, rather than repeating a time already in the past.
		headline = "High-tide closure possible any time now"
		detail = reopenCopy
		short = "tide closure possible soon"
	case risk == RiskLikely:
		headline = "High-tide closure possible around " + fmtClock(closeAt)
		detail = reopenCopy
		short = "tide closure possible ~" + fmtClock(closeAt)
	default:
		peakAt := roundNearest30(peak.Time)
		headline = "Could close around the " + fmtClock(peakAt) + " high tide"
		detail = "Depends on surf and sand · could just as well stay open"
		short = "could close on the ~" + fmtClock(peakAt) + " tide"
	}
	if laterPeakRisky {
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
