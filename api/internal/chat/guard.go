package chat

import (
	"regexp"
	"strings"
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
