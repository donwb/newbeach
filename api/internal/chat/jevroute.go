package chat

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/jev"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/predict"
)

// The Jev router asks one System One request over the question and
// assembles the plan in code. Jev answers the semantic parts — what is
// being asked, which city, which ramp, which day, what time of day, and
// the clock components as closed sets — and code owns everything Jev is
// documented to be bad at: the calendar arithmetic, the "1–7 means
// afternoon" rule, the past-instant check, the board-city fallback. The
// questions are literal on purpose (Jev reads exactly what is written),
// and every answer the plan consumes must clear a confidence floor or the
// question goes to the model, as the pattern router does on any doubt.

const (
	// The gates read probability, not Jev's confidence statistic: the
	// probability of the chosen outcome *as code will treat it*, summing
	// options that lead to the same plan (day "today" and "unstated" both
	// mean now). Confidence measures peakedness, which punishes exactly
	// the overlaps code doesn't care about.
	//
	// routeIntentFloor is what the intent's probability must reach.
	// Conservative to start; the eval (make jev-eval) reports how the
	// fixture behaves as it moves.
	routeIntentFloor = 0.7
	// routePartFloor applies to every other consumed Choice.
	routePartFloor = 0.6

	intentStatus  = "open_or_closed"
	intentBestDay = "best_day"
	intentPast    = "past"
	intentOther   = "other"

	// The roster Choice has ~28 options, where the confidence statistic
	// (how peaked the distribution is) runs low even for a clear pick, so
	// it is gated on the chosen option's own probability and its margin
	// over the runner-up instead.
	rampMinProb   = 0.5
	rampMinMargin = 0.25

	noneNamed = "none_named"
)

// routeTrace is what the Jev router saw, for logs and the eval. The
// *Conf fields hold the probability of the chosen outcome class (see the
// gate constants), not Jev's confidence statistic.
type routeTrace struct {
	Intent      string
	IntentConf  float64
	City        string
	CityConf    float64
	Ramp        string
	RampConf    float64
	RampProb    float64 // the chosen option's own probability
	RampMargin  float64 // over the runner-up
	Day         string
	DayConf     float64
	Daypart     string
	DaypartConf float64
	Hour        string
	HourConf    float64
	Minute      string
	Meridiem    string
	Reason      string // why the plan was not made, "" when it was
	Err         string // the call failed (plan unusable, fall back)
	Latency     time.Duration
	InputTokens int64
	Model       string
}

// cityOptions are the Choice options for the city question: option → the
// GIS key, with the aliases people use spelled into the descriptions.
var cityOptions = []struct{ key, gis, desc string }{
	{"ponce_inlet", "PONCE INLET", "Ponce Inlet — also 'Ponce' or 'the Inlet'"},
	{"new_smyrna_beach", "NEW SMYRNA BEACH", "New Smyrna Beach — also 'NSB', 'New Smyrna', or 'Smyrna'"},
	{"daytona_beach_shores", "DAYTONA BEACH SHORES", "Daytona Beach Shores — also 'the Shores' or 'Daytona Shores'"},
	{"daytona_beach", "DAYTONA BEACH", "Daytona Beach — 'Daytona' alone means this, not the Shores"},
	{"ormond_beach", "ORMOND BEACH", "Ormond Beach — also 'Ormond'"},
}

// rampAliases are the spoken forms the resolver's alias table knows,
// spelled into the option descriptions so Jev can match them.
var rampAliases = map[string]string{
	"DB-059":  "'ISB' or 'Speedway'",
	"NS-118":  "'Third Ave' or '3rd'",
	"NS-141":  "'Twenty-seventh' or '27th'",
	"DBS-076": "'Portal'",
	"DBS-067": "'Botefur'",
	"OB-034":  "'Rockerfeller'",
	"PI-097":  "'Beach Street in Ponce'",
}

var weekdayOptions = []string{"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}

// routeQuestions builds the request. ramps may be empty (the ramp
// question is then omitted and ramp questions fall to the model).
func routeQuestions(ramps []models.RampStatusWithSince) map[string]jev.Question {
	qs := map[string]jev.Question{
		"intent": jev.Choice(
			"What kind of question is this? The app reports whether Volusia County's beach driving ramps are open or closed, right now and up to a week ahead.",
			map[string]any{
				intentStatus:  "Whether the beach, beach driving, the ramps, or one named ramp is open, closed, drivable, or possible to get onto — right now or at a stated future time, not in general. Includes terse forms such as 'open?', 'beach status?', or a ramp name followed by a day.",
				intentBestDay: "Which day this weekend or this week is the best one for the beach, when the person should go, or a comparison of days ('Saturday or Sunday — which looks better?').",
				intentPast:    "What happened before now: yesterday, last weekend, earlier today, or any past time.",
				intentOther:   "Anything else — tides, surf, weather, water temperature, sharks, turtles, 4x4 rules, how the app works, a greeting, why something happened, or a general or habitual question ('usually', 'normally', 'ever', 'how often').",
			}),
		"city": jev.Choice(
			"Which city does the question name? A nickname counts as naming the city: 'NSB', 'Smyrna', 'the Shores', 'Daytona', 'Ormond', 'the Inlet'. Pick none_named when no city or nickname appears, even if the question mentions the beach, the ramps, or a ramp's street name.",
			func() map[string]any {
				m := map[string]any{noneNamed: "The question names no city."}
				for _, c := range cityOptions {
					m[c.key] = c.desc
				}
				return m
			}()),
		"day": jev.Choice(
			"Which day does the question ask about?",
			func() map[string]any {
				m := map[string]any{
					"unstated": "No day is mentioned at all — the question is only about the beach, a place, or a time of day.",
					"today":    "Today, this morning/afternoon/evening, tonight, or right now.",
					"tomorrow": "Tomorrow.",
					"other":    "Next week, a calendar date, a vague time such as 'later' or 'soon', or a day in the past.",
				}
				for _, d := range weekdayOptions {
					m[d] = "The question names " + strings.ToUpper(d[:1]) + d[1:] + " (in full or abbreviated)."
				}
				return m
			}()),
		"daypart": jev.Choice(
			"What time of day does the question ask about? If a clock time appears, pick clock_time even when the question also says morning, afternoon, or evening.",
			map[string]any{
				"now":        "Right now, currently, at the moment, or no time of day is mentioned at all.",
				"morning":    "Morning, early, first thing, or sunrise — with no clock time given.",
				"midday":     "The words noon, midday, or lunchtime — with no digits given.",
				"afternoon":  "Afternoon — with no clock time given.",
				"evening":    "Evening, tonight, late, or sunset — with no clock time given.",
				"clock_time": "A clock time in digits is given, such as 2, 2:30, 10am, 4 in the afternoon, or 5 o'clock. The word 'noon' alone is midday, not this.",
				"other":      "Later, earlier, or a time of day that fits none of the others.",
			}),
		"hour": jev.Choice(
			"If the question gives a clock time, which hour number does it say? Pick none when there is no clock time.",
			func() map[string]any {
				m := map[string]any{"none": "No clock time is given."}
				for h := 1; h <= 12; h++ {
					m[strconv.Itoa(h)] = nil
				}
				return m
			}()),
		"minute": jev.Choice(
			"If the question gives a clock time, which minutes does it say? A bare hour such as '2pm' or '10' is 00. Pick none when there is no clock time.",
			map[string]any{
				"00":    "On the hour, or no minutes given with the hour.",
				"15":    nil,
				"30":    nil,
				"45":    nil,
				"other": "Minutes other than 00, 15, 30, or 45.",
				"none":  "No clock time is given.",
			}),
		"meridiem": jev.Choice(
			"If the question gives a clock time, does it say am or pm?",
			map[string]any{
				"am":       "Morning: am, a.m., or 'in the morning' after the time.",
				"pm":       "Afternoon or evening: pm, p.m., or 'in the afternoon/evening' after the time.",
				"unstated": "The clock time has no am/pm, or there is no clock time.",
			}),
	}
	if len(ramps) > 0 {
		opts := map[string]any{noneNamed: "The question names no ramp: it mentions only a city, 'the beach', 'the ramps' in general, or nothing of the kind."}
		for _, r := range ramps {
			desc := predict.RampDisplayName(r) + " (" + models.PrettyCityName(r.City) + ")"
			if alias, ok := rampAliases[r.AccessID]; ok {
				desc += " — also " + alias
			}
			opts[r.AccessID] = desc
		}
		qs["ramp"] = jev.Choice(
			"Which ramp does the question name? A ramp is named by its street or landmark, with or without the words 'ramp', 'approach', 'Ave', or 'Blvd', and often after 'at' or 'on' — 'Flagler', 'the Dunlawton ramp', 'Silver Beach', 'Cardinal in Ormond', 'get on at Granada'. The options list every ramp with its city. Pick none_named only when no ramp's name appears.",
			opts)
	}
	return qs
}

// jevRoute asks Jev about the question and assembles a plan. ok is false
// when the plan should not be made (low confidence, out of scope, an
// instant code cannot place); trace.Err is set when the call itself
// failed and the caller should fall back to the pattern router.
func jevRoute(ctx context.Context, client *jev.Client, question, contextCity string, now time.Time, ramps []models.RampStatusWithSince) (quickPlan, routeTrace, bool) {
	var tr routeTrace
	q := strings.TrimSpace(question)
	if q == "" || len(q) > 300 {
		tr.Reason = "empty or too long"
		return quickPlan{}, tr, false
	}
	state := map[string]any{"question": q}
	res, err := client.Ask(ctx, state, routeQuestions(ramps))
	if err != nil {
		tr.Err = err.Error()
		return quickPlan{}, tr, false
	}
	tr.Latency = res.Latency
	tr.InputTokens = res.Usage.InputTokens
	tr.Model = res.Model
	tr.Intent, tr.IntentConf = classProb(res, "intent", nil)
	tr.City, tr.CityConf = classProb(res, "city", nil)
	tr.Ramp, _ = res.Choice("ramp")
	tr.RampConf = tr.RampProb
	tr.RampProb, tr.RampMargin = topMargin(res, "ramp")
	tr.RampConf = tr.RampProb
	tr.Day, tr.DayConf = classProb(res, "day", map[string]string{"unstated": "today"})
	// A future day with no time of day means the afternoon, so "now" and
	// "afternoon" are one outcome there.
	var daypartSame map[string]string
	if tr.Day != "today" && tr.Day != "unstated" {
		daypartSame = map[string]string{"afternoon": "now"}
	}
	tr.Daypart, tr.DaypartConf = classProb(res, "daypart", daypartSame)
	tr.Hour, tr.HourConf = classProb(res, "hour", nil)
	tr.Minute, _ = res.Choice("minute")
	tr.Meridiem, _ = res.Choice("meridiem")

	plan, reason := assemblePlan(tr, contextCity, now, ramps)
	tr.Reason = reason
	return plan, tr, reason == ""
}

// assemblePlan is the code half of the router: the same calendar and
// clock rules the pattern router applies (quickWhen), fed by Jev's
// components instead of regex captures. It returns the reason the plan
// was not made, "" on success.
func assemblePlan(tr routeTrace, contextCity string, now time.Time, ramps []models.RampStatusWithSince) (quickPlan, string) {
	if tr.IntentConf < routeIntentFloor {
		return quickPlan{}, fmt.Sprintf("intent %s below floor (%.2f)", tr.Intent, tr.IntentConf)
	}
	switch tr.Intent {
	case intentBestDay:
		return quickPlan{Kind: planWeekend}, ""
	case intentPast, intentOther:
		return quickPlan{}, "intent " + tr.Intent
	case intentStatus:
	default:
		return quickPlan{}, "unknown intent " + tr.Intent
	}

	// When.
	at, isNow, reason := whenFromParts(tr, now)
	if reason != "" {
		return quickPlan{}, reason
	}

	// Who: a ramp when one is named clearly, else a city.
	if tr.Ramp != "" && tr.Ramp != noneNamed {
		if tr.RampProb < rampMinProb || tr.RampMargin < rampMinMargin {
			return quickPlan{}, fmt.Sprintf("ramp %s unclear (p %.2f, margin %.2f)", tr.Ramp, tr.RampProb, tr.RampMargin)
		}
		city := ""
		for _, r := range ramps {
			if r.AccessID == tr.Ramp {
				city = r.City
				break
			}
		}
		if city == "" {
			return quickPlan{}, "ramp " + tr.Ramp + " not in roster"
		}
		if isNow {
			return quickPlan{Kind: planRampNow, City: city, AccessID: tr.Ramp}, ""
		}
		return quickPlan{Kind: planRampAt, City: city, AccessID: tr.Ramp, At: at}, ""
	}

	if tr.CityConf < routePartFloor {
		return quickPlan{}, fmt.Sprintf("city %s below floor (%.2f)", tr.City, tr.CityConf)
	}
	city := ""
	if tr.City != noneNamed {
		for _, c := range cityOptions {
			if c.key == tr.City {
				city = c.gis
			}
		}
		if city == "" {
			return quickPlan{}, "unknown city option " + tr.City
		}
	} else if k, _, ok := ResolveCity(contextCity); ok {
		city = k
	} else {
		return quickPlan{}, "no city named and no board city"
	}
	if isNow {
		return quickPlan{Kind: planCityNow, City: city}, ""
	}
	return quickPlan{Kind: planCityAt, City: city, At: at}, ""
}

// whenFromParts turns the day/daypart/clock components into an instant,
// with quickWhen's rules: a bare future day means the afternoon, a clock
// hour 1–7 with no am/pm means afternoon, a same-weekday name is
// ambiguous, and an instant already behind the clock is the model's.
func whenFromParts(tr routeTrace, now time.Time) (at time.Time, isNow bool, reason string) {
	if tr.DayConf < routePartFloor {
		return at, false, fmt.Sprintf("day %s below floor (%.2f)", tr.Day, tr.DayConf)
	}
	if tr.DaypartConf < routePartFloor {
		return at, false, fmt.Sprintf("daypart %s below floor (%.2f)", tr.Daypart, tr.DaypartConf)
	}
	et := now.In(eastern)
	day := time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern)
	switch tr.Day {
	case "today", "unstated":
	case "tomorrow":
		day = day.AddDate(0, 0, 1)
	case "other":
		return at, false, "day is other"
	default:
		target, found := weekdayFor(tr.Day)
		if !found {
			return at, false, "unknown day " + tr.Day
		}
		delta := (int(target) - int(day.Weekday()) + 7) % 7
		if delta == 0 {
			return at, false, "named weekday is today: ambiguous"
		}
		day = day.AddDate(0, 0, delta)
	}

	if (tr.Day == "today" || tr.Day == "unstated") && tr.Daypart == "now" {
		return now, true, ""
	}

	hour, minute := -1, 0
	switch tr.Daypart {
	case "now": // a future day with no time of day → the afternoon
		hour = 14
	case "morning":
		hour = 10
	case "midday":
		hour = 12
	case "afternoon":
		hour = 14
	case "evening":
		hour = 18
	case "clock_time":
		if tr.HourConf < routePartFloor {
			return at, false, fmt.Sprintf("hour %s below floor (%.2f)", tr.Hour, tr.HourConf)
		}
		h, err := strconv.Atoi(tr.Hour)
		if err != nil {
			return at, false, "clock time without an hour"
		}
		switch tr.Minute {
		case "00", "none", "":
			minute = 0
		case "15", "30", "45":
			minute, _ = strconv.Atoi(tr.Minute)
		default:
			return at, false, "odd minutes"
		}
		switch tr.Meridiem {
		case "am":
			if h == 12 {
				h = 0
			}
		case "pm":
			if h < 12 {
				h += 12
			}
		default:
			if h >= 1 && h <= 7 {
				h += 12
			}
		}
		hour = h
	default:
		return at, false, "daypart " + tr.Daypart
	}
	at = time.Date(day.Year(), day.Month(), day.Day(), hour, minute, 0, 0, eastern)
	if at.Before(now) {
		return at, false, "instant already past"
	}
	return at, false, ""
}

// classProb returns a Choice answer's pick and the summed probability of
// every option in the same outcome class (same maps option → class name;
// unmapped options are their own class).
func classProb(res *jev.Result, id string, same map[string]string) (string, float64) {
	a, ok := res.Answers[id]
	if !ok || a.Type != "choice" {
		return "", 0
	}
	class := func(opt string) string {
		if c, ok := same[opt]; ok {
			return c
		}
		return opt
	}
	chosen := class(a.Choice)
	var p float64
	for opt, prob := range a.Probabilities {
		if class(opt) == chosen {
			p += prob
		}
	}
	return a.Choice, p
}

// topMargin reads a Choice answer's distribution: the chosen option's
// probability and its lead over the runner-up.
func topMargin(res *jev.Result, id string) (top, margin float64) {
	a, ok := res.Answers[id]
	if !ok || a.Type != "choice" {
		return 0, 0
	}
	var second float64
	for k, p := range a.Probabilities {
		if k == a.Choice {
			top = p
		} else if p > second {
			second = p
		}
	}
	return top, top - second
}

func round2(f float64) float64 { return float64(int(f*100+0.5)) / 100 }
