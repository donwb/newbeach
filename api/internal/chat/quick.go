package chat

import (
	"context"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/predict"
)

// The quick path answers the common question shapes without a model call:
// "can I get on the beach in NSB right now?", "are the Daytona ramps open
// Saturday at 2?", "which day this weekend is best?". They are the spoken
// questions — Siri gives an intent a few seconds, and a model round-trip
// does not fit — and they are also the questions where the engine's own
// copy IS the answer, so relaying it directly is faster, free, and more
// faithful than asking a model to. Anything the router is not sure about
// falls through to the model; a wrong parse here would be worse than a
// slow answer.

var (
	intentRe     = regexp.MustCompile(`(?i)\b(can (i|we) (get|drive|go) (on|onto|out on) the beach|(is|are) (the )?(beach|ramps?|beach ramps)( in [a-z ]+?)? (open|closed|drivable)|(is|are) [a-z ]+ ramps? (open|closed)|(beach|ramps?) (open|closed)\b|what('s| is) open)`)
	weekendRe    = regexp.MustCompile(`(?i)\b(which|what) day (this weekend|this week|is best|looks best|should i go)|best day\b|when should i go`)
	quickClockRe = regexp.MustCompile(`(?i)\b(?:at |around |by )?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b`)
	timeWords    = regexp.MustCompile(`(?i)\b(morning|afternoon|evening|tonight|noon|midday|lunch(time)?|sunrise|sunset|later|earlier|yesterday|last|ago|next week)\b`)
	dayWords     = regexp.MustCompile(`(?i)\b(tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)\b`)
)

// quickWhen resolves the time phrase in a question. ok is false when the
// question carries a time the router cannot place with confidence — then
// the model reads it.
func quickWhen(q string, now time.Time) (at time.Time, isNow bool, ok bool) {
	et := now.In(eastern)
	lower := strings.ToLower(q)

	dayMatch := dayWords.FindString(lower)
	clock := quickClockRe.FindStringSubmatch(lower)
	words := timeWords.FindString(lower)

	// The past and vague futures are the model's.
	switch words {
	case "yesterday", "last", "ago", "earlier", "later", "next week":
		return time.Time{}, false, false
	}

	// No day, no clock, no daypart: now ("right now", "today", or nothing).
	if dayMatch == "" && clock == nil && words == "" {
		return now, true, true
	}

	// Which day.
	day := time.Date(et.Year(), et.Month(), et.Day(), 0, 0, 0, 0, eastern)
	switch dayMatch {
	case "":
		// today
	case "tomorrow":
		day = day.AddDate(0, 0, 1)
	default:
		target, found := weekdayFor(dayMatch)
		if !found {
			return time.Time{}, false, false
		}
		delta := (int(target) - int(day.Weekday()) + 7) % 7
		if delta == 0 {
			// "Saturday" on a Saturday is ambiguous: today or next week.
			return time.Time{}, false, false
		}
		day = day.AddDate(0, 0, delta)
	}

	// Which hour.
	hour, minute := -1, 0
	if clock != nil {
		h, _ := strconv.Atoi(clock[1])
		if clock[2] != "" {
			minute, _ = strconv.Atoi(clock[2])
		}
		mer := strings.ReplaceAll(clock[3], ".", "")
		switch mer {
		case "am":
			if h == 12 {
				h = 0
			}
		case "pm":
			if h < 12 {
				h += 12
			}
		default:
			// No meridiem: beach hours are 8am–7pm, so 1–7 means afternoon.
			if h >= 1 && h <= 7 {
				h += 12
			}
		}
		if h < 0 || h > 23 || minute > 59 {
			return time.Time{}, false, false
		}
		hour = h
	} else {
		switch words {
		case "morning", "sunrise":
			hour = 10
		case "noon", "midday", "lunch", "lunchtime":
			hour = 12
		case "afternoon":
			hour = 14
		case "evening", "tonight", "sunset":
			hour = 18
		case "":
			hour = 14 // a bare day means the afternoon
		default:
			return time.Time{}, false, false
		}
	}
	at = time.Date(day.Year(), day.Month(), day.Day(), hour, minute, 0, 0, eastern)
	if at.Before(now) {
		// "this morning" at 3pm is a question about the past.
		return time.Time{}, false, false
	}
	return at, false, true
}

func weekdayFor(s string) (time.Weekday, bool) {
	switch strings.ToLower(s) {
	case "sunday", "sun":
		return time.Sunday, true
	case "monday", "mon":
		return time.Monday, true
	case "tuesday", "tue", "tues":
		return time.Tuesday, true
	case "wednesday", "wed":
		return time.Wednesday, true
	case "thursday", "thu", "thur", "thurs":
		return time.Thursday, true
	case "friday", "fri":
		return time.Friday, true
	case "saturday", "sat":
		return time.Saturday, true
	}
	return 0, false
}

// TryQuick answers the question deterministically when it is one of the
// shapes the pattern router knows. contextCity is the board's city (any
// alias). The returned Response carries Model "quick" and zero usage.
// (The Runner goes through Router.Route, which adds the Jev router; this
// is the pattern-only path.)
func TryQuick(ctx context.Context, eng Engine, question, contextCity string) (*Response, bool) {
	now := eng.Now()
	plan, ok := regexRoute(question, contextCity, now)
	if !ok {
		return nil, false
	}
	return runPlan(ctx, eng, plan, now)
}

func finishQuick(reply string, sources []Source, now time.Time) *Response {
	return &Response{
		Reply:       reply,
		Spoken:      spokenForm(reply),
		Sources:     sources,
		Model:       "quick",
		GeneratedAt: now.UTC(),
	}
}

// quickCityNowReply: the live verdict, in the engine's words.
func quickCityNowReply(c *predict.CityNow) string {
	var b strings.Builder
	if c.Verdict != nil && c.Verdict.Headline != "" {
		b.WriteString(sentence(c.Verdict.Headline))
		if c.Verdict.Detail != "" {
			b.WriteString(" " + sentence(c.Verdict.Detail))
		}
		return b.String()
	}
	b.WriteString(strconv.Itoa(c.OpenCount) + " of " + strconv.Itoa(c.RampCount) + " ramps are open in " + c.DisplayName + " right now.")
	for _, r := range c.Ramps {
		if strings.HasPrefix(strings.ToUpper(r.Status), "CLOSED") {
			b.WriteString(" " + r.Name + " is " + strings.ToLower(predictStatusWords(r.Status)) + ".")
		}
	}
	return b.String()
}

// quickCityAtReply: the replayed verdict for the instant, with the day's
// frame when the instant falls outside driving hours.
func quickCityAtReply(c *predict.CityOutlookAt) string {
	lead := c.DisplayName + ", " + c.AtLabel + ": "
	switch c.Relation {
	case predict.RelationBeforeOpen:
		return lead + "the beach isn't open for driving yet then. Beach driving opens " + c.Schedule.OpensLabel + "."
	case predict.RelationAfterClose:
		return lead + "driving will already have ended for the day. Beach driving closes around " + c.Schedule.ClosesLabel + "."
	}
	var b strings.Builder
	b.WriteString(lead)
	if c.Verdict != nil && c.Verdict.Headline != "" {
		b.WriteString(sentence(lowerFirst(c.Verdict.Headline)))
		if c.Verdict.Detail != "" {
			b.WriteString(" " + sentence(c.Verdict.Detail))
		}
	} else {
		b.WriteString("no tide trouble expected.")
	}
	// Name the ramps the tide could close, in their own words, when few.
	var risky []string
	for _, r := range c.Ramps {
		if r.Risk == predict.RiskPossible || r.Risk == predict.RiskLikely {
			risky = append(risky, r.Name)
		}
	}
	if n := len(risky); n > 0 && n <= 3 {
		b.WriteString(" " + joinNames(risky) + " could close for the tide.")
	}
	return b.String()
}

func quickWeekendReply(w *predict.WeekendOutlook) string {
	var b strings.Builder
	if w.Headline != "" {
		b.WriteString(sentence(w.Headline))
	}
	for _, d := range w.Days {
		if !d.IsWeekend {
			continue
		}
		b.WriteString(" " + d.Weekday + ": " + sentence(lowerFirst(d.Headline)))
	}
	return strings.TrimSpace(b.String())
}

func sentence(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	if strings.HasSuffix(s, ".") || strings.HasSuffix(s, "!") || strings.HasSuffix(s, "?") {
		return s
	}
	return s + "."
}

func lowerFirst(s string) string {
	if s == "" {
		return s
	}
	// Keep proper nouns and abbreviations: only lower a leading capital that
	// starts a lowercase word.
	if len(s) > 1 && s[0] >= 'A' && s[0] <= 'Z' && s[1] >= 'a' && s[1] <= 'z' {
		return strings.ToLower(s[:1]) + s[1:]
	}
	return s
}

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

func predictStatusWords(raw string) string {
	switch strings.ToUpper(strings.TrimSpace(raw)) {
	case "CLOSED FOR HIGH TIDE":
		return "closed for high tide"
	case "CLOSED - CLEARED FOR TURTLES":
		return "closed for turtles"
	case "CLOSED":
		return "closed"
	case "OPEN":
		return "open"
	}
	return strings.ToLower(raw)
}

// spokenForm rewrites a reply for text-to-speech: the board's glyphs
// become words, and "~" becomes "about".
func spokenForm(reply string) string {
	s := reply
	s = strings.ReplaceAll(s, " · ", ". ")
	s = strings.ReplaceAll(s, "·", ",")
	s = strings.ReplaceAll(s, " — ", ", ")
	s = strings.ReplaceAll(s, "—", ", ")
	s = strings.ReplaceAll(s, " – ", " to ")
	s = strings.ReplaceAll(s, "–", " to ")
	// "the ~3pm high" reads as "the 3pm high" aloud; "~3pm" elsewhere is
	// "about 3pm".
	s = strings.ReplaceAll(s, "the ~", "the ")
	s = strings.ReplaceAll(s, "~", "about ")
	s = strings.ReplaceAll(s, "  ", " ")
	s = strings.ReplaceAll(s, ". .", ".")
	return strings.TrimSpace(s)
}
