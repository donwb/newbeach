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
	// routeIntentFloor is the confidence the intent Choice must reach.
	// Conservative to start; the eval (make jev-eval) reports how the
	// fixture behaves as it moves.
	routeIntentFloor = 0.7
	// routePartFloor applies to every other consumed Choice.
	routePartFloor = 0.6

	intentCity    = "city_status"
	intentRamp    = "ramp_status"
	intentBestDay = "best_day"
	intentPast    = "past"
	intentOther   = "other"

	noneNamed = "none_named"
)

// routeTrace is what the Jev router saw, for logs and the eval.
type routeTrace struct {
	Intent      string
	IntentConf  float64
	City        string
	CityConf    float64
	Ramp        string
	RampConf    float64
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

var weekdayOptions = []string{"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}

// routeQuestions builds the request. ramps may be empty (the ramp
// question is then omitted and ramp questions fall to the model).
func routeQuestions(ramps []models.RampStatusWithSince) map[string]jev.Question {
	qs := map[string]jev.Question{
		"intent": jev.Choice(
			"What is the question asking? The app reports whether Volusia County's beach driving ramps are open or closed, right now and up to a week ahead.",
			map[string]any{
				intentCity:    "Whether the beach, the ramps, or beach driving — in a named city or in general — is open, closed, or drivable, either right now or at a stated future time. No individual ramp is named.",
				intentRamp:    "Whether one specific named ramp or beach approach is open or closed, right now or at a stated future time. Ramps are named after a street or landmark, such as Flagler, 27th Ave, Beachway, Dunlawton, Cardinal, Granada, or Silver Beach.",
				intentBestDay: "Which day this weekend or this week is the best one for the beach, or when the person should go.",
				intentPast:    "What happened before now: yesterday, last weekend, earlier today, or any past time.",
				intentOther:   "Anything else — tides, surf, weather, water temperature, sharks, turtles, how the app works, a greeting, or a question that only makes sense as a follow-up to an earlier message.",
			}),
		"city": jev.Choice(
			"Which city does the question name? Pick none_named when the question does not name a city, even if it mentions the beach or the ramps.",
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
					"today":    "Today, right now, or no day is mentioned.",
					"tomorrow": "Tomorrow.",
					"other":    "Next week, a calendar date, a vague time such as 'later' or 'soon', or a day in the past.",
				}
				for _, d := range weekdayOptions {
					m[d] = "The question names " + strings.ToUpper(d[:1]) + d[1:] + " (in full or abbreviated)."
				}
				return m
			}()),
		"daypart": jev.Choice(
			"What time of day does the question ask about?",
			map[string]any{
				"now":        "Right now, currently, at the moment, or no time of day is mentioned at all.",
				"morning":    "Morning, early, first thing, or sunrise.",
				"midday":     "Noon, midday, or lunchtime.",
				"afternoon":  "Afternoon.",
				"evening":    "Evening, tonight, late, or sunset.",
				"clock_time": "A clock time is given, such as 2, 2:30, 10am, or 5 o'clock.",
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
		opts := map[string]any{noneNamed: "The question names no specific ramp — it is about a city, the beach in general, or something else."}
		for _, r := range ramps {
			opts[r.AccessID] = predict.RampDisplayName(r) + " (" + models.PrettyCityName(r.City) + ")"
		}
		qs["ramp"] = jev.Choice(
			"Which ramp or beach approach does the question name? Ramps are named by a street or landmark; the options list every ramp with its city. Pick none_named when no specific ramp is named.",
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
	et := now.In(eastern)
	state := map[string]any{
		"question":      q,
		"today_weekday": et.Weekday().String(),
	}
	res, err := client.Ask(ctx, state, routeQuestions(ramps))
	if err != nil {
		tr.Err = err.Error()
		return quickPlan{}, tr, false
	}
	tr.Latency = res.Latency
	tr.InputTokens = res.Usage.InputTokens
	tr.Model = res.Model
	tr.Intent, tr.IntentConf = res.Choice("intent")
	tr.City, tr.CityConf = res.Choice("city")
	tr.Ramp, tr.RampConf = res.Choice("ramp")
	tr.Day, tr.DayConf = res.Choice("day")
	tr.Daypart, tr.DaypartConf = res.Choice("daypart")
	tr.Hour, tr.HourConf = res.Choice("hour")
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
	case intentCity, intentRamp:
	default:
		return quickPlan{}, "unknown intent " + tr.Intent
	}

	// When.
	at, isNow, reason := whenFromParts(tr, now)
	if reason != "" {
		return quickPlan{}, reason
	}

	// Who: a ramp, or a city.
	if tr.Intent == intentRamp {
		if tr.Ramp == "" {
			return quickPlan{}, "ramp question but no roster"
		}
		if tr.RampConf < routePartFloor {
			return quickPlan{}, fmt.Sprintf("ramp %s below floor (%.2f)", tr.Ramp, tr.RampConf)
		}
		if tr.Ramp == noneNamed {
			return quickPlan{}, "ramp question names no ramp"
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
	case "today":
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

	if tr.Day == "today" && tr.Daypart == "now" {
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

func round2(f float64) float64 { return float64(int(f*100+0.5)) / 100 }
