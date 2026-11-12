package predict

import (
	"strconv"
	"strings"
	"time"
)

// City verdict prose. Same voice rules as text.go: predicted times are
// half-hour rounded and hedged, facts (a ramp's closed-since time, the day's
// close label) may be quoted as they are, every line names its reason, and
// the pair always looks forward — what is true right now, and the next thing
// that changes it.

// countWord spells small counts the way the verdict reads aloud.
func countWord(n int) string {
	words := []string{"zero", "one", "two", "three", "four", "five", "six",
		"seven", "eight", "nine", "ten", "eleven", "twelve"}
	if n >= 0 && n < len(words) {
		return words[n]
	}
	return strconv.Itoa(n)
}

// capFirst uppercases the first letter of an ASCII word.
func capFirst(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// joinNames renders "A", "A and B", or "A, B and C".
func joinNames(names []string) string {
	switch len(names) {
	case 0:
		return ""
	case 1:
		return names[0]
	case 2:
		return names[0] + " and " + names[1]
	default:
		return strings.Join(names[:len(names)-1], ", ") + " and " + names[len(names)-1]
	}
}

// notePeak folds one at-risk ramp's risk peak into the city's: the
// earliest high still ahead, else (every at-risk ramp riding out a high
// that has passed) any of those.
func (a *cityAgg) notePeak(now time.Time, p *time.Time) {
	if p == nil {
		return
	}
	if cur := a.riskPeak; cur != nil && !(p.After(now) && (!cur.After(now) || p.Before(*cur))) {
		return
	}
	t := *p
	a.riskPeak = &t
}

// shutPhrase is the at-risk clause's verb phrase, naming the high the ramp
// rows hang their risk on — not simply the next high on the chart, which
// past the morning high is the one after the beach clears ("could shut on
// the ~11pm high" at 10am, 2026-11-12).
func shutPhrase(now time.Time, agg *cityAgg, tide TideContext) string {
	switch {
	case agg.riskPeak != nil && !agg.riskPeak.After(now):
		return "could still shut as the tide drops"
	case agg.riskPeak != nil:
		return "could shut on the ~" + fmtClock(roundNearest30(*agg.riskPeak)) + " high"
	case tide.NextPeakAt != nil:
		return "could shut on the ~" + fmtClock(roundNearest30(*tide.NextPeakAt)) + " high"
	default:
		return "could shut on the next high tide"
	}
}

// cityAllOpenText: every ramp open, driving day in full swing.
func cityAllOpenText(now time.Time, agg *cityAgg, sched Schedule, tide TideContext) (headline, detail string) {
	headline = allOpenHeadline(now, agg.rampCount)

	if agg.atRisk == 0 {
		lead := pickVariant(now, "quiet", noTideTroubleLeads)
		return headline, lead + " · open for driving until " + sched.ClosesLabel
	}

	shut := shutPhrase(now, agg, tide)
	switch {
	case agg.atRisk == agg.rampCount && agg.rampCount > 1:
		detail = "Any of them " + shut
	case agg.atRisk == 1:
		detail = "One " + shut
	default:
		detail = capFirst(countWord(agg.atRisk)) + " " + shut
	}
	// "first around" quotes the earliest time any ramp's own line quotes,
	// so the city never promises an hour the ramp rows don't. When that is
	// the peak itself the sentence already said it — don't repeat it.
	// Past the high the ramp rows say the odds fall with the water, so
	// "any time now" would contradict them.
	pastPeak := agg.riskPeak != nil && !agg.riskPeak.After(now)
	if agg.atRisk > 1 && agg.earliestClose != nil && !pastPeak {
		atPeak := agg.riskPeak != nil && agg.earliestClose.Equal(roundNearest30(*agg.riskPeak))
		switch {
		case !agg.earliestClose.After(now):
			detail += " · could go any time now"
		case !atPeak:
			detail += " · first around " + fmtClock(*agg.earliestClose)
		}
	}
	return headline, detail
}

// citySomeClosedText: at least one ramp is not plain open right now.
func citySomeClosedText(now time.Time, agg *cityAgg, sched Schedule, tide TideContext) (headline, detail string) {
	var closed, limited []notOpenRamp
	for _, r := range agg.notOpen {
		if r.category == "closed" {
			closed = append(closed, r)
		} else {
			limited = append(limited, r)
		}
	}

	// Nothing plain-open: say what the ramps actually are. "Closed" is
	// reserved for ramps that are shut — a city of limited ramps is
	// limited, and a one-ramp city gets its name, never "all one".
	switch {
	case agg.openCount > 0:
		headline = capFirst(countWord(agg.openCount)) + " of " + countWord(agg.rampCount) + " open"
	case agg.rampCount == 1 && len(agg.notOpen) == 1:
		headline = agg.notOpen[0].name + " " + agg.notOpen[0].category
	case len(closed) == 0:
		headline = "All " + countWord(agg.rampCount) + " limited"
	case len(limited) == 0:
		headline = "All " + countWord(agg.rampCount) + " closed"
	default:
		headline = "None of " + countWord(agg.rampCount) + " open"
	}

	var clauses []string
	if len(closed) > 0 {
		cause := "closed"
		allTide := true
		for _, r := range closed {
			if r.status != tideClosedStatus {
				allTide = false
			}
		}
		if allTide {
			cause = "closed for the tide"
		}
		var clause string
		if len(closed) <= 3 {
			clause = joinNames(namesOf(closed)) + " " + cause
		} else {
			clause = capFirst(countWord(len(closed))) + " ramps " + cause
		}
		if since := sharedSince(closed); since != nil {
			clause += " since " + fmtClock(*since)
		}
		clauses = append(clauses, clause)
	}
	// When the headline already said "All N limited" / "<name> limited",
	// the limited clause would only repeat it.
	if len(limited) > 0 && !(agg.openCount == 0 && len(closed) == 0) {
		if len(limited) <= 2 {
			clauses = append(clauses, joinNames(namesOf(limited))+" limited")
		} else {
			clauses = append(clauses, countWord(len(limited))+" limited")
		}
	}
	switch {
	case agg.atRisk > 0:
		clauses = append(clauses, countWord(agg.atRisk)+" more "+shutPhrase(now, agg, tide))
	case agg.openCount > 0:
		clauses = append(clauses, "the rest look clear until "+sched.ClosesLabel)
	case len(closed) == 0:
		// Every ramp limited, nothing more to add: the day is still on.
		clauses = append(clauses, "driving with limits until "+sched.ClosesLabel)
	}

	return headline, capFirst(strings.Join(clauses, " · "))
}

// cityGoldenText: everything open, the day's close inside goldenWindow.
func cityGoldenText(now time.Time, agg *cityAgg, season string, sched Schedule) (headline, detail string) {
	// In turtle season the fixed close comes well before dark, so the story
	// is the driving day, not the light.
	subject := "light"
	if season == "turtle" {
		subject = "driving"
	}
	rem := time.Duration(0)
	if sched.ClosesAt != nil {
		rem = sched.ClosesAt.Sub(now)
	}
	if rem <= 35*time.Minute {
		headline = "About half an hour of " + subject + " left"
	} else {
		headline = "Under an hour of " + subject + " left"
	}

	allOpen := "All " + countWord(agg.rampCount) + " open"
	if agg.rampCount == 1 {
		allOpen = "The ramp is open"
	}
	closeClause := "gates close at " + sched.ClosesLabel
	if season == "turtle" {
		closeClause = "gates close around " + sched.ClosesLabel
	}
	return headline, allOpen + " · " + closeClause
}

// cityOvernightText: outside driving hours entirely — the next thing that
// happens is the morning open.
func cityOvernightText(now time.Time, season string, sched Schedule, agg *cityAgg) (headline, detail string) {
	headline = "Driving is done for the day"
	if sched.OpensAt != nil {
		nowET, opensET := now.In(eastern), sched.OpensAt.In(eastern)
		if nowET.Year() == opensET.Year() && nowET.YearDay() == opensET.YearDay() {
			headline = "Closed until morning"
		}
	}
	if season == "turtle" {
		detail = "Every ramp reopens " + sched.OpensLabel
	} else {
		detail = "Every ramp reopens at " + sched.OpensLabel
	}
	// A high tide around the open: the ramp rows hedge the open, so the
	// city never promises it outright.
	if agg.openLate > 0 {
		opens := "around " + fmtClock(roundNearest30(*sched.OpensAt))
		cause := "the high tide"
		if agg.openLateWater {
			cause = "high water"
		}
		switch {
		case agg.openLate == agg.rampCount && agg.rampCount > 1:
			detail = "Opens " + opens + ", but " + cause + " could keep any of them closed past it"
		case agg.openLate == 1 && agg.rampCount == 1:
			detail = "Opens " + opens + ", but " + cause + " could keep it closed past it"
		default:
			detail = "Opens " + opens + ", but " + cause + " could keep " + countWord(agg.openLate) + " of them closed past it"
		}
	}
	return headline, detail
}

// namesOf projects the display names.
func namesOf(ramps []notOpenRamp) []string {
	names := make([]string, len(ramps))
	for i, r := range ramps {
		names[i] = r.name
	}
	return names
}

// sharedSince returns the group's common status-since time — only when every
// ramp has one and they agree to the minute, so "closed since 11:40am" is
// never claimed for a ramp it isn't true of.
func sharedSince(ramps []notOpenRamp) *time.Time {
	var since *time.Time
	for _, r := range ramps {
		if r.since == nil {
			return nil
		}
		if since == nil {
			since = r.since
			continue
		}
		if !r.since.Truncate(time.Minute).Equal(since.Truncate(time.Minute)) {
			return nil
		}
	}
	return since
}
