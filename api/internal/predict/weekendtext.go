package predict

import (
	"fmt"
	"math"
	"strings"

	"github.com/donwb/beach/api/internal/models"
)

// Weekend prose follows the same rules as text.go: half-hour rounded times
// hedged with "around"/"~", tide closures are always "possible" (never
// promised), and every string names its reason. Clients render verbatim.

// verdictAdjective is the casual word for a verdict in headline copy.
func verdictAdjective(v string) string {
	switch v {
	case VerdictGreat:
		return "great"
	case VerdictGood:
		return "good"
	case VerdictMixed:
		return "a mixed bag"
	case VerdictTough:
		return "rough"
	default:
		return "a question mark"
	}
}

// weekendHeadline frames the response around the weekend days in view.
func weekendHeadline(days []WeekendDay) string {
	var sat, sun *WeekendDay
	for i := range days {
		switch {
		case days[i].Weekday == "Saturday" && sat == nil:
			sat = &days[i]
		case days[i].Weekday == "Sunday" && sun == nil:
			sun = &days[i]
		}
	}

	switch {
	case sat != nil && sun != nil:
		sr, ur := verdictRank(sat.Verdict), verdictRank(sun.Verdict)
		switch {
		case sr >= 2 && ur >= 2:
			return "Both weekend days look " + verdictAdjective(betterOf(sat.Verdict, sun.Verdict))
		case sr > ur:
			return "Saturday's the day this weekend — Sunday looks " + verdictAdjective(sun.Verdict)
		case ur > sr:
			return "Sunday's the day this weekend — Saturday looks " + verdictAdjective(sat.Verdict)
		default:
			return "The weekend looks " + verdictAdjective(sat.Verdict)
		}
	case sat != nil:
		return "Saturday looks " + verdictAdjective(sat.Verdict)
	case sun != nil:
		return "Sunday looks " + verdictAdjective(sun.Verdict)
	default:
		return "The week ahead, day by day"
	}
}

func betterOf(a, b string) string {
	if verdictRank(a) >= verdictRank(b) {
		return a
	}
	return b
}

// worstPeak returns the day's highest predicted peak, or nil.
func worstPeak(facts dayFacts) *models.TidePrediction {
	var worst *models.TidePrediction
	for i := range facts.tidePeaks {
		if worst == nil || *facts.tidePeaks[i].Height > *worst.Height {
			worst = &facts.tidePeaks[i]
		}
	}
	return worst
}

// dayText builds one day's headline and detail. The headline carries the
// day's primary story; the detail collects the supporting clauses, joined in
// the " · " voice the live outlook uses.
func dayText(verdict string, facts dayFacts, window *Window, vp VerdictParams) (headline, detail string) {
	extremeHeat := facts.heatAdvisory || (facts.maxHeatIdxF != nil && *facts.maxHeatIdxF >= vp.HeatIndexF)
	cold := facts.hasWeather && facts.maxTempF != nil && *facts.maxTempF < vp.ColdHighF
	gusty := facts.maxGustMph != nil && *facts.maxGustMph >= vp.GustToughMph
	washout := facts.hasWeather && facts.stormFrac >= vp.StormWashoutFrac
	stormsShaped := facts.hasWeather && !washout && facts.firstStormAt != nil

	// Headline: one primary story, worst first.
	switch {
	case gusty:
		headline = fmt.Sprintf("Windy enough to wreck it — gusts near %d mph", roundTo5(*facts.maxGustMph))
	case cold:
		headline = "More of a bundled-up walk than a beach day"
	case facts.pressure == PressureHigh:
		headline = "Big tide day — ramp closures possible " + peakClause(facts)
	case washout:
		headline = "Storms look parked over most of the day"
	case !facts.hasWeather:
		// True both for days past the forecast horizon and for an NWS
		// outage — either way there is no weather read, only tides.
		if facts.pressure == PressureNone {
			headline = "No weather call for this day yet — the tides look fine"
		} else {
			headline = "No weather call for this day yet — but a ramp-closing tide is possible"
		}
	case stormsShaped && window != nil:
		headline = "Best stretch looks like roughly " + window.Label + " — storms possible after"
	case facts.pressure == PressureSome && window != nil:
		headline = "Looks " + verdictAdjective(verdict) + " — best around " + window.Label + ", clear of the tide"
	case facts.pressure == PressureSome:
		headline = "Looks " + verdictAdjective(verdict) + " — a high-tide closure is possible " + peakClause(facts)
	case verdict == VerdictGreat:
		headline = "Wide open — any time works"
	default:
		headline = "Looks " + verdictAdjective(verdict)
	}

	// Detail clauses, each naming its reason.
	var clauses []string
	if facts.pressure != PressureNone {
		if len(facts.dicey) > 0 {
			clauses = append(clauses, "the usual first-to-close ramps — "+strings.Join(facts.dicey, ", ")+" — are the ones to watch")
		} else {
			clauses = append(clauses, "a high tide could close some ramps for a stretch")
		}
	}
	if stormsShaped && !strings.Contains(headline, "storms") {
		clauses = append(clauses, "storms possible after "+fmtClock(roundNearest30(*facts.firstStormAt)))
	}
	if extremeHeat && !cold {
		clauses = append(clauses, "brutal heat by midday — mornings are kinder")
	}
	if !gusty && facts.maxWindMph != nil && *facts.maxWindMph >= vp.WindDegradeMph {
		clauses = append(clauses, fmt.Sprintf("breezy — around %d mph", roundTo5(*facts.maxWindMph)))
	}
	if cold && facts.maxTempF != nil {
		clauses = append(clauses, fmt.Sprintf("high only around %d°", roundTo5(*facts.maxTempF)))
	}
	if len(clauses) == 0 && window == nil && verdict == VerdictGreat {
		clauses = append(clauses, "open for driving "+facts.frame.OpensLabel+" to "+facts.frame.ClosesLabel)
	}

	return headline, strings.Join(clauses, " · ")
}

// peakClause renders "around the ~1:30pm high tide" for the day's worst peak,
// or a timeless fallback.
func peakClause(facts dayFacts) string {
	p := worstPeak(facts)
	if p == nil {
		return "on the high tide"
	}
	return "around the ~" + fmtClock(roundNearest30(p.Time)) + " high tide"
}

// roundTo5 rounds a measurement to the nearest 5 — the numeric version of the
// half-hour rule: promise less precision than the math produced.
func roundTo5(v float64) int {
	return int(math.Round(v/5) * 5)
}
