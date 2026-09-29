package chat

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/jev"
)

// The guard is the backstop behind the prompt: the engine's copy rules are
// enforceable facts, not style preferences, so a reply that turns "could
// close" into "will close" or quotes a minute-precise time the engine never
// said gets one corrective round and then a templated fallback. It reads
// the reply against the sources the tools produced, never against the
// model's own account of them.

var (
	promiseRe = regexp.MustCompile(`(?i)\b(will|going to|definitely|certainly|is likely to|are likely to)\b[^.!?]{0,40}\bclos`)
	likelyRe  = regexp.MustCompile(`(?i)\blikely\b`)
	clockRe   = regexp.MustCompile(`(?i)\b(\d{1,2}):(\d{2})\s*(am|pm)\b`)
)

// checkCopy returns the rule violations in reply, empty when it is clean.
func checkCopy(reply string, sources []Source) []string {
	var problems []string
	anyLikely := false
	var corpus strings.Builder
	for _, s := range sources {
		if s.Risk == "likely" {
			anyLikely = true
		}
		corpus.WriteString(strings.ToLower(s.Headline))
		corpus.WriteString(" ")
		corpus.WriteString(strings.ToLower(s.Detail))
		corpus.WriteString(" ")
		corpus.WriteString(strings.ToLower(s.WindowLabel))
		corpus.WriteString(" ")
		corpus.WriteString(strings.ToLower(s.ReopenLabel))
		corpus.WriteString(" ")
		corpus.WriteString(strings.ToLower(s.BestWindowLabel))
		corpus.WriteString(" ")
		corpus.WriteString(strings.ToLower(s.AtLabel))
		corpus.WriteString(" ")
		for _, r := range s.Ramps {
			if r.Risk == "likely" {
				anyLikely = true
			}
			corpus.WriteString(strings.ToLower(r.Headline))
			corpus.WriteString(" ")
		}
	}
	known := corpus.String()

	if promiseRe.MatchString(reply) && !anyLikely {
		problems = append(problems, "promises a closure the engine only calls possible")
	}
	if likelyRe.MatchString(reply) && !anyLikely {
		problems = append(problems, "says likely when no source is likely")
	}
	for _, m := range clockRe.FindAllStringSubmatch(reply, -1) {
		minute := m[2]
		if minute == "00" || minute == "30" {
			continue
		}
		quoted := strings.ToLower(strings.TrimSpace(m[0]))
		if !strings.Contains(known, strings.ReplaceAll(quoted, " ", "")) {
			problems = append(problems, "quotes a minute-precise time the engine did not say: "+m[0])
		}
	}
	return problems
}

// templatedReply is the fallback when the model cannot be talked back into
// the engine's words: the engine's own headline and detail, nothing added.
func templatedReply(sources []Source) string {
	for _, s := range sources {
		if s.Kind == "ramp_outlook" {
			var b strings.Builder
			b.WriteString(s.Name)
			if s.AtLabel != "" {
				b.WriteString(", " + s.AtLabel)
			}
			b.WriteString(": " + s.Headline)
			if s.Detail != "" {
				b.WriteString(". " + s.Detail)
			}
			if !strings.HasSuffix(b.String(), ".") {
				b.WriteString(".")
			}
			return b.String()
		}
	}
	for _, s := range sources {
		if s.Kind == "city_now" || s.Kind == "city_outlook" {
			var b strings.Builder
			b.WriteString(s.City)
			if s.AtLabel != "" {
				b.WriteString(", " + s.AtLabel)
			}
			if s.Headline != "" {
				b.WriteString(": " + s.Headline)
			}
			if s.Detail != "" {
				b.WriteString(". " + s.Detail)
			}
			if !strings.HasSuffix(b.String(), ".") {
				b.WriteString(".")
			}
			return b.String()
		}
	}
	for _, s := range sources {
		if s.Kind == "weekend_day" {
			line := s.Weekday + ": " + s.Headline
			if s.Detail != "" {
				line += ". " + s.Detail
			}
			if !strings.HasSuffix(line, ".") {
				line += "."
			}
			return line
		}
	}
	return "The outlook did not have an answer for that one."
}

// --- The Jev guard ---------------------------------------------------------
//
// The promise rule is semantic — "will close", "count on it being shut",
// "expect it closed by two" all break it and no pattern lists them all —
// so in Jev mode a Noul judges it over the reply and the engine's lines.
// The other two rules stay in code on purpose: "likely" is a reserved
// word (a literal check is the right tool) and a minute-precise clock time
// is a number (Jev's docs say to keep numbers in code). Jev replaces the
// one regex that was doing a judgment's job.

const (
	// guardPromiseFloor is the Noul probability above which the reply is
	// treated as promising a closure. Erring high means a missed promise
	// slips out in the engine's voice; erring low means an extra corrective
	// round. Tune against chat.guard logs.
	guardPromiseFloor = 0.6
)

// guardTrace is what the Jev guard saw, for logs and comparison.
type guardTrace struct {
	Promises    float64
	Unsupported float64
	Latency     time.Duration
	InputTokens int64
	Err         string
}

// engineLines flattens the sources to the strings the model was allowed
// to quote.
func engineLines(sources []Source) []string {
	var lines []string
	add := func(s string) {
		if s = strings.TrimSpace(s); s != "" {
			lines = append(lines, s)
		}
	}
	for _, s := range sources {
		add(s.Headline)
		add(s.Detail)
		add(s.WindowLabel)
		add(s.ReopenLabel)
		add(s.BestWindowLabel)
		for _, r := range s.Ramps {
			add(r.Headline)
		}
	}
	return lines
}

// jevCheckCopy asks Jev whether the reply promises a closure. It returns
// the semantic problems (the literal rules are appended by the caller)
// and a trace; trace.Err set means the call failed and the caller should
// use the pattern rule instead.
func jevCheckCopy(ctx context.Context, client *jev.Client, reply string, sources []Source) ([]string, guardTrace) {
	var tr guardTrace
	state := map[string]any{
		"reply":        reply,
		"engine_lines": engineLines(sources),
	}
	res, err := client.Ask(ctx, state, map[string]jev.Question{
		"promises_closure": jev.Noul(
			"Does `reply` state that a ramp, the ramps, or the beach will be closed or will close, or is likely to close, as a certainty or a strong expectation?",
			&jev.NoulCriteria{
				True:  "The reply says a closure will happen, is going to happen, is likely, is expected, or should be counted on.",
				False: "Every closure in the reply is described as possible, could happen, or might happen — or the reply mentions no closure, or says something will stay open.",
			}),
		"unsupported_claim": jev.Noul(
			"Does `reply` state a fact about a ramp or the beach opening or closing, or a clock time, that does not appear in `engine_lines`?",
			&jev.NoulCriteria{
				True:  "The reply adds an opening, closing, or time that no engine line says.",
				False: "Every opening, closing, and time in the reply is also in an engine line, allowing for rewording.",
			}),
	})
	if err != nil {
		tr.Err = err.Error()
		return nil, tr
	}
	tr.Latency = res.Latency
	tr.InputTokens = res.Usage.InputTokens
	tr.Promises, _ = res.Noul("promises_closure")
	tr.Unsupported, _ = res.Noul("unsupported_claim")

	anyLikely := false
	for _, s := range sources {
		if s.Risk == "likely" {
			anyLikely = true
		}
		for _, r := range s.Ramps {
			if r.Risk == "likely" {
				anyLikely = true
			}
		}
	}
	var problems []string
	if tr.Promises > guardPromiseFloor && !anyLikely {
		problems = append(problems, fmt.Sprintf("promises a closure the engine only calls possible (jev %.2f)", tr.Promises))
	}
	return problems, tr
}

// literalCopyRules are the two rules that stay in code whatever the mode:
// the reserved word and the minute-precise clock.
func literalCopyRules(reply string, sources []Source) []string {
	all := checkCopy(reply, sources)
	var kept []string
	for _, p := range all {
		if !strings.HasPrefix(p, "promises") {
			kept = append(kept, p)
		}
	}
	return kept
}
