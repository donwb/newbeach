package chat

import (
	"context"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/jev"
	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/predict"
)

// A router turns a first-turn question into a quickPlan: which engine call
// answers it and with what arguments. Two routers exist — the pattern
// router (regexRoute, the original quick path) and the Jev router
// (jevRoute, a System One call). Both produce the same plan type, so the
// answer is built once (runPlan) and the two can be compared question by
// question. Router mode (JEV_MODE) decides which one answers:
//
//	off     the pattern router alone (Jev never called)
//	shadow  the pattern router answers; Jev runs alongside and every
//	        disagreement is logged — the safe way to accumulate evidence
//	on      Jev answers; the pattern router is only the outage fallback
//
// Whatever routes, a question neither router can place goes to the model.

const (
	planCityNow = "city_now"
	planCityAt  = "city_at"
	planRampNow = "ramp_now"
	planRampAt  = "ramp_at"
	planWeekend = "weekend"

	routerRegex = "regex"
	routerJev   = "jev"

	ModeOff    = "off"
	ModeShadow = "shadow"
	ModeOn     = "on"
)

// quickPlan is a routed question: the engine call and its arguments.
type quickPlan struct {
	Kind     string    // planCityNow | planCityAt | planRampNow | planRampAt | planWeekend
	City     string    // GIS key (city plans)
	AccessID string    // ramp plans
	At       time.Time // *At plans
}

// same reports whether two plans would make the same engine call. Instants
// compare to the minute so "2pm" from either router agrees.
func (p quickPlan) same(o quickPlan) bool {
	return p.Kind == o.Kind && p.City == o.City && p.AccessID == o.AccessID &&
		p.At.Truncate(time.Minute).Equal(o.At.Truncate(time.Minute))
}

func (p quickPlan) String() string {
	if p.Kind == "" {
		return "model"
	}
	var b strings.Builder
	b.WriteString(p.Kind)
	if p.City != "" {
		b.WriteString(" " + p.City)
	}
	if p.AccessID != "" {
		b.WriteString(" " + p.AccessID)
	}
	if !p.At.IsZero() {
		b.WriteString(" @" + p.At.In(eastern).Format("Mon 3:04pm"))
	}
	return b.String()
}

// regexRoute is the pattern router: the original quick path's parse,
// unchanged. ok is false when the question is not a shape it knows.
func regexRoute(q, contextCity string, now time.Time) (quickPlan, bool) {
	q = strings.TrimSpace(q)
	if q == "" || len(q) > 160 {
		return quickPlan{}, false
	}
	if weekendRe.MatchString(q) && !intentRe.MatchString(q) {
		return quickPlan{Kind: planWeekend}, true
	}
	if !intentRe.MatchString(q) {
		return quickPlan{}, false
	}
	city, _, ok := ResolveCity(q)
	if !ok {
		city, _, ok = ResolveCity(contextCity)
		if !ok {
			return quickPlan{}, false
		}
	}
	at, isNow, ok := quickWhen(q, now)
	if !ok {
		return quickPlan{}, false
	}
	if isNow {
		return quickPlan{Kind: planCityNow, City: city}, true
	}
	return quickPlan{Kind: planCityAt, City: city, At: at}, true
}

// rampIntentRe catches "is Flagler open right now", "will 27th Ave be open
// tomorrow at 2", "can I use Beachway this afternoon" — a ramp named the
// way people say it, which intentRe (city shapes) does not cover.
var rampIntentRe = regexp.MustCompile(`(?i)^\s*(?:is|are|will|can i (?:use|drive|get on))\s+(?:the\s+)?([a-z0-9' ]+?)(?:\s+ramp)?\s+(?:be\s+)?(?:open|closed|drivable|available)\b`)

// regexRouteWithRoster is regexRoute plus the ramp shapes: when the city
// parse fails, a question that names one ramp exactly (Resolve, exact)
// becomes a ramp plan. A name that is really a city alias ("is NSB open")
// becomes the city plan. ramps may be nil — then only city shapes route.
func regexRouteWithRoster(q, contextCity string, now time.Time, ramps []models.RampStatusWithSince) (quickPlan, bool) {
	if plan, ok := regexRoute(q, contextCity, now); ok {
		return plan, true
	}
	m := rampIntentRe.FindStringSubmatch(strings.TrimSpace(q))
	if m == nil || len(q) > 160 {
		return quickPlan{}, false
	}
	name := strings.TrimSpace(m[1])
	at, isNow, ok := quickWhen(q, now)
	if !ok {
		return quickPlan{}, false
	}
	if city, _, ok := ResolveCity(name); ok {
		if isNow {
			return quickPlan{Kind: planCityNow, City: city}, true
		}
		return quickPlan{Kind: planCityAt, City: city, At: at}, true
	}
	if len(ramps) == 0 {
		return quickPlan{}, false
	}
	res := Resolve(ramps, name)
	if !res.Exact || len(res.Matches) == 0 {
		return quickPlan{}, false
	}
	id := res.Matches[0].AccessID
	cityKey := ""
	for i := range ramps {
		if ramps[i].AccessID == id {
			cityKey = ramps[i].City
			break
		}
	}
	if isNow {
		return quickPlan{Kind: planRampNow, City: cityKey, AccessID: id}, true
	}
	return quickPlan{Kind: planRampAt, City: cityKey, AccessID: id, At: at}, true
}

// runPlan makes the engine call and builds the reply in the engine's own
// words. ok is false when the engine could not answer (unknown city, past
// instant, beyond the horizon…) — then the model reads the question.
func runPlan(ctx context.Context, eng Engine, plan quickPlan, now time.Time) (*Response, bool) {
	switch plan.Kind {
	case planWeekend:
		wk, err := eng.Weekend(ctx)
		if err != nil {
			return nil, false
		}
		return finishQuick(quickWeekendReply(wk), sourcesFromWeekend(wk), now), true
	case planCityNow:
		res, err := eng.CityNow(ctx, plan.City)
		if err != nil {
			return nil, false
		}
		return finishQuick(quickCityNowReply(res), []Source{sourceFromCityNow(res)}, now), true
	case planCityAt:
		res, err := eng.CityOutlookAt(ctx, plan.City, plan.At)
		if err != nil {
			return nil, false
		}
		return finishQuick(quickCityAtReply(res), []Source{sourceFromCityAt(res)}, now), true
	case planRampNow:
		res, err := eng.CityNow(ctx, plan.City)
		if err != nil {
			return nil, false
		}
		for _, r := range res.Ramps {
			if r.AccessID == plan.AccessID {
				return finishQuick(quickRampNowReply(res, r), []Source{sourceFromCityNow(res)}, now), true
			}
		}
		return nil, false
	case planRampAt:
		res, err := eng.OutlookAt(ctx, plan.AccessID, plan.At)
		if err != nil {
			return nil, false
		}
		return finishQuick(quickRampAtReply(res), []Source{sourceFromOutlook(res)}, now), true
	}
	return nil, false
}

// quickRampNowReply: one ramp's live status and outlook line.
func quickRampNowReply(c *predict.CityNow, r predict.CityRampAt) string {
	var b strings.Builder
	status := predictStatusWords(r.Status)
	b.WriteString(r.Name + " is " + strings.ToLower(status) + " right now.")
	// The outlook headline for a closed ramp is the status again ("Closed
	// for high tide"); say it once and keep the detail (the reopen read).
	if r.Headline != "" && !strings.EqualFold(strings.TrimSuffix(r.Headline, "."), status) {
		b.WriteString(" " + sentence(r.Headline))
	}
	if r.Detail != "" {
		b.WriteString(" " + sentence(r.Detail))
	}
	return b.String()
}

// quickRampAtReply: the replayed outlook for one ramp at the instant.
func quickRampAtReply(r *predict.RampOutlookAt) string {
	lead := r.Name + ", " + r.AtLabel + ": "
	switch r.Relation {
	case predict.RelationBeforeOpen:
		return lead + "the beach isn't open for driving yet then. Beach driving opens " + r.Schedule.OpensLabel + "."
	case predict.RelationAfterClose:
		return lead + "driving will already have ended for the day. Beach driving closes around " + r.Schedule.ClosesLabel + "."
	}
	var b strings.Builder
	b.WriteString(lead)
	if r.Outlook.Headline != "" {
		b.WriteString(sentence(lowerFirst(r.Outlook.Headline)))
		if r.Outlook.Detail != "" {
			b.WriteString(" " + sentence(r.Outlook.Detail))
		}
	} else {
		b.WriteString("no tide trouble expected.")
	}
	return b.String()
}

// Router owns the routing mode and the Jev client (nil when off).
type Router struct {
	jev  *jev.Client
	mode string
}

// NewRouter builds a Router. A nil client forces ModeOff whatever mode
// says; an unknown mode is treated as shadow, the safe default.
func NewRouter(client *jev.Client, mode string) *Router {
	if !client.Enabled() {
		return &Router{mode: ModeOff}
	}
	switch mode {
	case ModeOff, ModeShadow, ModeOn:
	default:
		mode = ModeShadow
	}
	return &Router{jev: client, mode: mode}
}

// Mode reports the effective mode.
func (r *Router) Mode() string {
	if r == nil {
		return ModeOff
	}
	return r.mode
}

// Route answers a first-turn question from the engine's own copy when a
// router can place it. ok is false when the model should read it.
func (r *Router) Route(ctx context.Context, eng Engine, question, contextCity string) (*Response, bool) {
	now := eng.Now()
	// The roster lets the pattern router place a ramp named outright; it
	// is cached, and nil just means ramp shapes go to the model.
	ramps, rerr := eng.Ramps(ctx)
	if rerr != nil {
		ramps = nil
	}
	if r == nil || r.mode == ModeOff {
		plan, ok := regexRouteWithRoster(question, contextCity, now, ramps)
		if !ok {
			return nil, false
		}
		return runPlan(ctx, eng, plan, now)
	}

	if r.mode == ModeShadow {
		plan, ok := regexRouteWithRoster(question, contextCity, now, ramps)
		// Jev runs beside the answer, off the request's clock, and only
		// its verdict against the pattern router is recorded.
		go r.shadow(eng, question, contextCity, now, plan, ok)
		if !ok {
			return nil, false
		}
		return runPlan(ctx, eng, plan, now)
	}

	// ModeOn: Jev decides. The pattern router only covers an outage.
	start := time.Now()
	plan, trace, ok := jevRoute(ctx, r.jev, question, contextCity, now, ramps)
	if trace.Err != "" {
		fallback, fok := regexRouteWithRoster(question, contextCity, now, ramps)
		slog.Warn("chat.route", "router", routerRegex, "reason", "jev unavailable: "+trace.Err, "plan", fallback.String(), "ms", time.Since(start).Milliseconds())
		if !fok {
			return nil, false
		}
		return runPlan(ctx, eng, fallback, now)
	}
	regexPlan, regexOK := regexRouteWithRoster(question, contextCity, now, ramps)
	slog.Info("chat.route",
		"router", routerJev,
		"plan", plan.String(),
		"regex_plan", regexPlan.String(),
		"agree", ok == regexOK && (!ok || plan.same(regexPlan)),
		"intent", trace.Intent, "intent_conf", trace.IntentConf,
		"reason", trace.Reason,
		"jev_ms", trace.Latency.Milliseconds(),
		"tokens", trace.InputTokens,
		"ms", time.Since(start).Milliseconds())
	if !ok {
		return nil, false
	}
	return runPlan(ctx, eng, plan, now)
}

// shadow runs the Jev router after the fact and logs the comparison. It
// has its own clock budget so a slow call never touches the reply.
func (r *Router) shadow(eng Engine, question, contextCity string, now time.Time, regexPlan quickPlan, regexOK bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ramps, err := eng.Ramps(ctx)
	if err != nil {
		ramps = nil
	}
	plan, trace, ok := jevRoute(ctx, r.jev, question, contextCity, now, ramps)
	if trace.Err != "" {
		slog.Warn("chat.route.shadow", "err", trace.Err)
		return
	}
	slog.Info("chat.route.shadow",
		"agree", ok == regexOK && (!ok || plan.same(regexPlan)),
		"regex_plan", regexPlan.String(),
		"jev_plan", plan.String(),
		"intent", trace.Intent, "intent_conf", trace.IntentConf,
		"reason", trace.Reason,
		"jev_ms", trace.Latency.Milliseconds(),
		"tokens", trace.InputTokens)
}
