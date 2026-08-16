package predict

import (
	"fmt"
	"time"

	"github.com/donwb/beach/api/internal/models"
)

// All outlook prose is generated here, under strict rules: no bare clock
// times (the county is too inconsistent to promise minutes), hedged verbs
// per risk level ("likely" closes, "could" close — never "will"), and
// reopens are always "often back open ...". Clients render these strings
// verbatim so every platform tells the same story.

// timeBucket names a coarse Eastern-time stretch of day.
func timeBucket(t time.Time) string {
	switch h := t.In(eastern).Hour(); {
	case h >= 5 && h < 8:
		return "early morning"
	case h >= 8 && h < 11:
		return "midmorning"
	case h >= 11 && h < 13:
		return "midday"
	case h >= 13 && h < 16:
		return "midafternoon"
	case h >= 16 && h < 19:
		return "late afternoon"
	case h >= 19 && h < 21:
		return "evening"
	default:
		return "overnight"
	}
}

// windowLabel describes a window's span in bucket terms.
func windowLabel(start, end time.Time) string {
	sb, eb := timeBucket(start), timeBucket(end)
	if sb == eb {
		return sb
	}
	return sb + " into " + eb
}

// scheduleCopy is the "no tide trouble" detail line.
func scheduleCopy(sched Schedule) string {
	return "Open for driving until " + sched.ClosesLabel
}

// riskText builds the headline and detail for a not-currently-closed ramp.
func riskText(risk string, peak *models.TidePrediction, window *Window, sched Schedule, laterPeakRisky bool) (headline, detail string) {
	switch risk {
	case RiskLikely:
		headline = "High-tide closure likely " + timeBucket(peak.Time)
		if window != nil {
			detail = fmt.Sprintf("Usually closes ahead of high tides like this one · often back open by %s", timeBucket(window.End))
		} else {
			detail = "Usually closes ahead of high tides like this one"
		}
	case RiskPossible:
		headline = fmt.Sprintf("Could close around the %s high tide", timeBucket(peak.Time))
		detail = "Depends on surf and sand · could just as well stay open"
	default:
		headline = "No tide trouble expected"
		detail = scheduleCopy(sched)
	}
	if laterPeakRisky && risk != RiskNone {
		detail += " · the next high tide could bring another round"
	}
	return headline, detail
}

// closedNowText builds the copy for a ramp that is tide-closed right now.
func closedNowText(reopen time.Time, sched Schedule) (headline, detail string, r *Reopen) {
	headline = "Closed for high tide"
	if reopen.IsZero() {
		detail = "Reopening depends on the county getting back out there"
		return headline, detail, nil
	}
	label := "often back open by " + timeBucket(reopen)
	if sched.ClosesAt != nil && reopen.After(*sched.ClosesAt) {
		label = "may stay closed for the day"
	}
	detail = "The tide is the boss here · " + label
	return headline, detail, &Reopen{Label: label}
}
