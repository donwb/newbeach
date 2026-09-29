package chat

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/jev"
)

// fakeJev scripts the System One endpoint: every request gets the same
// canned answer map (a Jev answer is a function of the question, and one
// test asks one question), and the requests are kept for inspection.
type fakeJev struct {
	mu       sync.Mutex
	answers  map[string]any
	status   int
	requests []map[string]any
	srv      *httptest.Server
}

func newFakeJev(t *testing.T, answers map[string]any) *fakeJev {
	f := &fakeJev{answers: answers, status: http.StatusOK}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req map[string]any
		_ = json.Unmarshal(body, &req)
		f.mu.Lock()
		f.requests = append(f.requests, req)
		status, answers := f.status, f.answers
		f.mu.Unlock()
		if status != http.StatusOK {
			w.WriteHeader(status)
			_, _ = w.Write([]byte(`{"error":"scripted failure"}`))
			return
		}
		out, _ := json.Marshal(map[string]any{
			"model":   "jev-test",
			"answers": answers,
			"usage":   map[string]any{"input_tokens": 900, "output_tokens": 40},
		})
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(out)
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeJev) client() *jev.Client {
	return jev.New("test", jev.WithBaseURL(f.srv.URL), jev.WithModel("jev-test"))
}

func (f *fakeJev) calls() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.requests)
}

func choiceAnswer(choice string, conf float64) map[string]any {
	return map[string]any{"type": "choice", "choice": choice, "confidence": conf, "probabilities": map[string]float64{choice: conf, "_other": 1 - conf}}
}

func noulAnswer(p float64) map[string]any {
	return map[string]any{"type": "noul", "noul": p}
}

// routeAnswers is a full, confident answer set; tests override fields.
func routeAnswers(over map[string]any) map[string]any {
	a := map[string]any{
		"intent":   choiceAnswer(intentStatus, 0.95),
		"city":     choiceAnswer("new_smyrna_beach", 0.95),
		"ramp":     choiceAnswer(noneNamed, 0.95),
		"day":      choiceAnswer("today", 0.95),
		"daypart":  choiceAnswer("now", 0.95),
		"hour":     choiceAnswer("none", 0.95),
		"minute":   choiceAnswer("none", 0.95),
		"meridiem": choiceAnswer("unstated", 0.95),
	}
	for k, v := range over {
		a[k] = v
	}
	return a
}

func TestAssemblePlan(t *testing.T) {
	now := fixedNow() // Wednesday 2026-06-10 9:00am ET
	e := func(day, hour, min int) time.Time { return time.Date(2026, 6, day, hour, min, 0, 0, eastern) }
	conf := func(tr routeTrace) routeTrace {
		// A trace with every confidence high unless the case sets it.
		if tr.IntentConf == 0 {
			tr.IntentConf = 0.9
		}
		if tr.CityConf == 0 {
			tr.CityConf = 0.9
		}
		if tr.RampProb == 0 {
			tr.RampProb, tr.RampMargin = 0.9, 0.8
		}
		if tr.DayConf == 0 {
			tr.DayConf = 0.9
		}
		if tr.DaypartConf == 0 {
			tr.DaypartConf = 0.9
		}
		if tr.HourConf == 0 {
			tr.HourConf = 0.9
		}
		return tr
	}
	ramps := rosterFixture()

	tests := []struct {
		name    string
		tr      routeTrace
		ctxCity string
		want    quickPlan
		reason  string
	}{
		{"city now", conf(routeTrace{Intent: intentStatus, City: "new_smyrna_beach", Day: "today", Daypart: "now"}), "",
			quickPlan{Kind: planCityNow, City: "NEW SMYRNA BEACH"}, ""},
		{"board city fills in", conf(routeTrace{Intent: intentStatus, City: noneNamed, Day: "today", Daypart: "now"}), "nsb",
			quickPlan{Kind: planCityNow, City: "NEW SMYRNA BEACH"}, ""},
		{"no city anywhere", conf(routeTrace{Intent: intentStatus, City: noneNamed, Day: "today", Daypart: "now"}), "",
			quickPlan{}, "no city named and no board city"},
		{"this afternoon", conf(routeTrace{Intent: intentStatus, City: "daytona_beach", Day: "today", Daypart: "afternoon"}), "",
			quickPlan{Kind: planCityAt, City: "DAYTONA BEACH", At: e(10, 14, 0)}, ""},
		{"tomorrow morning", conf(routeTrace{Intent: intentStatus, City: "ormond_beach", Day: "tomorrow", Daypart: "morning"}), "",
			quickPlan{Kind: planCityAt, City: "ORMOND BEACH", At: e(11, 10, 0)}, ""},
		{"bare tomorrow is the afternoon", conf(routeTrace{Intent: intentStatus, City: "ormond_beach", Day: "tomorrow", Daypart: "now"}), "",
			quickPlan{Kind: planCityAt, City: "ORMOND BEACH", At: e(11, 14, 0)}, ""},
		{"saturday at 2 means 2pm", conf(routeTrace{Intent: intentStatus, City: "daytona_beach", Day: "saturday", Daypart: "clock_time", Hour: "2", Minute: "00", Meridiem: "unstated"}), "",
			quickPlan{Kind: planCityAt, City: "DAYTONA BEACH", At: e(13, 14, 0)}, ""},
		{"saturday 2:30pm", conf(routeTrace{Intent: intentStatus, City: "daytona_beach", Day: "saturday", Daypart: "clock_time", Hour: "2", Minute: "30", Meridiem: "pm"}), "",
			quickPlan{Kind: planCityAt, City: "DAYTONA BEACH", At: e(13, 14, 30)}, ""},
		{"sat 10am", conf(routeTrace{Intent: intentStatus, City: "daytona_beach", Day: "saturday", Daypart: "clock_time", Hour: "10", Minute: "none", Meridiem: "am"}), "",
			quickPlan{Kind: planCityAt, City: "DAYTONA BEACH", At: e(13, 10, 0)}, ""},
		{"friday noon", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "friday", Daypart: "midday"}), "",
			quickPlan{Kind: planCityAt, City: "PONCE INLET", At: e(12, 12, 0)}, ""},
		{"12am is midnight", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "friday", Daypart: "clock_time", Hour: "12", Minute: "00", Meridiem: "am"}), "",
			quickPlan{Kind: planCityAt, City: "PONCE INLET", At: e(12, 0, 0)}, ""},
		{"today at 8am is already past", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "today", Daypart: "clock_time", Hour: "8", Minute: "00", Meridiem: "am"}), "",
			quickPlan{}, "instant already past"},
		{"today at 5 is 5pm", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "today", Daypart: "clock_time", Hour: "5", Minute: "00", Meridiem: "unstated"}), "",
			quickPlan{Kind: planCityAt, City: "PONCE INLET", At: e(10, 17, 0)}, ""},
		{"wednesday on a wednesday is ambiguous", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "wednesday", Daypart: "now"}), "",
			quickPlan{}, "named weekday is today: ambiguous"},
		{"next week is other", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "other", Daypart: "now"}), "",
			quickPlan{}, "day is other"},
		{"later is other daypart", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "today", Daypart: "other"}), "",
			quickPlan{}, "daypart other"},
		{"odd minutes go to the model", conf(routeTrace{Intent: intentStatus, City: "ponce_inlet", Day: "today", Daypart: "clock_time", Hour: "3", Minute: "other", Meridiem: "pm"}), "",
			quickPlan{}, "odd minutes"},
		{"best day", conf(routeTrace{Intent: intentBestDay}), "",
			quickPlan{Kind: planWeekend}, ""},
		{"past", conf(routeTrace{Intent: intentPast, City: "ponce_inlet", Day: "other", Daypart: "now"}), "",
			quickPlan{}, "intent past"},
		{"other", conf(routeTrace{Intent: intentOther}), "",
			quickPlan{}, "intent other"},
		{"low intent confidence", routeTrace{Intent: intentStatus, IntentConf: 0.5, CityConf: 0.9, DayConf: 0.9, DaypartConf: 0.9, City: "ponce_inlet", Day: "today", Daypart: "now"}, "",
			quickPlan{}, "intent open_or_closed below floor (0.50)"},
		{"low city confidence", routeTrace{Intent: intentStatus, IntentConf: 0.9, CityConf: 0.4, DayConf: 0.9, DaypartConf: 0.9, City: "ponce_inlet", Ramp: noneNamed, Day: "today", Daypart: "now"}, "",
			quickPlan{}, "city ponce_inlet below floor (0.40)"},
		{"low hour confidence", routeTrace{Intent: intentStatus, IntentConf: 0.9, CityConf: 0.9, DayConf: 0.9, DaypartConf: 0.9, HourConf: 0.3, City: "ponce_inlet", Ramp: noneNamed, Day: "today", Daypart: "clock_time", Hour: "3", Minute: "00"}, "",
			quickPlan{}, "hour 3 below floor (0.30)"},
		{"ramp now", conf(routeTrace{Intent: intentStatus, Ramp: "NS-110", Day: "today", Daypart: "now"}), "",
			quickPlan{Kind: planRampNow, City: "NEW SMYRNA BEACH", AccessID: "NS-110"}, ""},
		{"ramp friday at 2pm", conf(routeTrace{Intent: intentStatus, Ramp: "NS-110", Day: "friday", Daypart: "clock_time", Hour: "2", Minute: "00", Meridiem: "pm"}), "",
			quickPlan{Kind: planRampAt, City: "NEW SMYRNA BEACH", AccessID: "NS-110", At: e(12, 14, 0)}, ""},
		{"no ramp named falls to the city", conf(routeTrace{Intent: intentStatus, Ramp: noneNamed, City: "ormond_beach", Day: "today", Daypart: "now"}), "",
			quickPlan{Kind: planCityNow, City: "ORMOND BEACH"}, ""},
		{"unstated day is today", conf(routeTrace{Intent: intentStatus, City: "ormond_beach", Day: "unstated", Daypart: "now"}), "",
			quickPlan{Kind: planCityNow, City: "ORMOND BEACH"}, ""},
		{"unstated day with an evening", conf(routeTrace{Intent: intentStatus, City: "ormond_beach", Day: "unstated", Daypart: "evening"}), "",
			quickPlan{Kind: planCityAt, City: "ORMOND BEACH", At: e(10, 18, 0)}, ""},
		{"ramp unclear goes to the model", routeTrace{Intent: intentStatus, IntentConf: 0.9, RampProb: 0.45, RampMargin: 0.1, DayConf: 0.9, DaypartConf: 0.9, Ramp: "NS-110", Day: "today", Daypart: "now"}, "",
			quickPlan{}, "ramp NS-110 unclear (p 0.45, margin 0.10)"},
		{"ramp not in roster", conf(routeTrace{Intent: intentStatus, Ramp: "ZZ-1", Day: "today", Daypart: "now"}), "",
			quickPlan{}, "ramp ZZ-1 not in roster"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, reason := assemblePlan(tt.tr, tt.ctxCity, now, ramps)
			assert.Equal(t, tt.reason, reason)
			if tt.reason == "" {
				assert.True(t, tt.want.same(got), "want %s got %s", tt.want, got)
			}
		})
	}
}

func TestRouteQuestionsShape(t *testing.T) {
	qs := routeQuestions(rosterFixture())
	for _, id := range []string{"intent", "city", "ramp", "day", "daypart", "hour", "minute", "meridiem"} {
		require.Contains(t, qs, id)
		assert.Equal(t, "choice", qs[id].Type)
	}
	ramp := qs["ramp"].Criteria.(map[string]any)
	assert.Contains(t, ramp, "NS-110")
	assert.Contains(t, ramp, noneNamed)
	assert.Equal(t, "Flagler Ave (New Smyrna Beach)", ramp["NS-110"])
	assert.Equal(t, "3rd Ave (New Smyrna Beach) — also 'Third Ave' or '3rd'", ramp["NS-118"])

	// No roster → no ramp question, and a ramp intent falls to the model.
	assert.NotContains(t, routeQuestions(nil), "ramp")
}

func TestRouterOnModeAnswersFromJev(t *testing.T) {
	// A phrasing the pattern router does not know, routed by Jev.
	api := newFakeJev(t, routeAnswers(nil))
	router := NewRouter(api.client(), ModeOn)
	eng := defaultFake()

	q := "any chance of getting on the sand in New Smyrna at the moment?"
	_, ok := regexRoute(q, "", eng.Now())
	require.False(t, ok, "the pattern router must miss this one for the test to mean anything")

	resp, ok := router.Route(context.Background(), eng, q, "")
	require.True(t, ok)
	assert.Equal(t, "quick", resp.Model)
	assert.Equal(t, "city_now", resp.Sources[0].Kind)
	assert.Equal(t, 1, api.calls())

	// The state is the question alone: no board city, no weekday — code
	// applies the context fallback and the calendar.
	req := api.requests[0]
	state := req["state"].(map[string]any)
	assert.Equal(t, q, state["question"])
	assert.Len(t, state, 1)
	assert.Equal(t, "jev-test", req["model"])
}

func TestRouterOnModeRampAt(t *testing.T) {
	api := newFakeJev(t, routeAnswers(map[string]any{
		"intent":   choiceAnswer(intentStatus, 0.9),
		"ramp":     choiceAnswer("NS-110", 0.9),
		"day":      choiceAnswer("friday", 0.9),
		"daypart":  choiceAnswer("clock_time", 0.9),
		"hour":     choiceAnswer("2", 0.9),
		"minute":   choiceAnswer("00", 0.9),
		"meridiem": choiceAnswer("pm", 0.9),
	}))
	router := NewRouter(api.client(), ModeOn)
	resp, ok := router.Route(context.Background(), defaultFake(), "is Flagler open Friday at 2pm?", "")
	require.True(t, ok)
	assert.Equal(t, "ramp_outlook", resp.Sources[0].Kind)
	assert.Equal(t, "Flagler Ave, Friday ~2pm: could close around the 2:30pm high tide. Closure possible around 2:30pm · often back open by ~4:30pm.", resp.Reply)
}

func TestRouterOnModeRampNow(t *testing.T) {
	api := newFakeJev(t, routeAnswers(map[string]any{
		"intent": choiceAnswer(intentStatus, 0.9),
		"ramp":   choiceAnswer("NS-110", 0.9),
	}))
	router := NewRouter(api.client(), ModeOn)
	resp, ok := router.Route(context.Background(), defaultFake(), "is Flagler open?", "")
	require.True(t, ok)
	assert.Equal(t, "Flagler Ave is closed for high tide right now.", resp.Reply, "the status is said once")
	assert.Equal(t, "city_now", resp.Sources[0].Kind)
}

func TestRouterOnModeLowConfidenceGoesToModel(t *testing.T) {
	api := newFakeJev(t, routeAnswers(map[string]any{"intent": choiceAnswer(intentStatus, 0.4)}))
	router := NewRouter(api.client(), ModeOn)
	_, ok := router.Route(context.Background(), defaultFake(), "can I get on the beach in NSB right now", "")
	assert.False(t, ok, "Jev decides in on mode, even where the pattern router would have answered")
}

func TestRouterOnModeFallsBackWhenJevIsDown(t *testing.T) {
	api := newFakeJev(t, nil)
	api.status = http.StatusInternalServerError
	router := NewRouter(api.client(), ModeOn)
	resp, ok := router.Route(context.Background(), defaultFake(), "can I get on the beach in NSB right now", "")
	require.True(t, ok, "the pattern router covers the outage")
	assert.Equal(t, "city_now", resp.Sources[0].Kind)
}

func TestRouterShadowModeAnswersFromPatterns(t *testing.T) {
	// Jev would say "other"; shadow mode still answers from the pattern.
	api := newFakeJev(t, routeAnswers(map[string]any{"intent": choiceAnswer(intentOther, 0.9)}))
	router := NewRouter(api.client(), ModeShadow)
	resp, ok := router.Route(context.Background(), defaultFake(), "can I get on the beach in NSB right now", "")
	require.True(t, ok)
	assert.Equal(t, "city_now", resp.Sources[0].Kind)
	// The shadow call happens off the request; give it a moment.
	deadline := time.Now().Add(2 * time.Second)
	for api.calls() == 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	assert.Equal(t, 1, api.calls())
}

func TestRouterOffWithoutClient(t *testing.T) {
	assert.Equal(t, ModeOff, NewRouter(nil, ModeOn).Mode())
	assert.Equal(t, ModeShadow, NewRouter(newFakeJev(t, nil).client(), "bogus").Mode(), "unknown mode is the safe one")
	var r *Router
	assert.Equal(t, ModeOff, r.Mode())
	resp, ok := r.Route(context.Background(), defaultFake(), "can I get on the beach in NSB right now", "")
	require.True(t, ok)
	assert.Equal(t, "city_now", resp.Sources[0].Kind)
}

func TestJevGuard(t *testing.T) {
	sources := []Source{{Kind: "ramp_outlook", Risk: "possible", Headline: "Could close around the 2:30pm high tide", Detail: "Closure possible around 2:30pm · often back open by ~4:30pm"}}

	api := newFakeJev(t, map[string]any{"promises_closure": noulAnswer(0.91), "unsupported_claim": noulAnswer(0.1)})
	problems, tr := jevCheckCopy(context.Background(), api.client(), "Count on Flagler being shut by two.", sources)
	require.Len(t, problems, 1)
	assert.Contains(t, problems[0], "promises a closure")
	assert.InDelta(t, 0.91, tr.Promises, 1e-9)
	state := api.requests[0]["state"].(map[string]any)
	assert.Equal(t, "Count on Flagler being shut by two.", state["reply"])
	assert.Len(t, state["engine_lines"], 2)

	// A likely source licenses the promise.
	likely := []Source{{Kind: "ramp_outlook", Risk: "likely", Headline: "Likely to close"}}
	problems, _ = jevCheckCopy(context.Background(), api.client(), "It will close.", likely)
	assert.Empty(t, problems)

	// Below the floor: clean.
	api2 := newFakeJev(t, map[string]any{"promises_closure": noulAnswer(0.2), "unsupported_claim": noulAnswer(0.1)})
	problems, _ = jevCheckCopy(context.Background(), api2.client(), "Flagler could close around 2:30pm.", sources)
	assert.Empty(t, problems)

	// The literal rules stay in code.
	lit := literalCopyRules("It is likely to close at 2:17pm.", sources)
	require.Len(t, lit, 2)
	assert.Contains(t, lit[0], "likely")
	assert.Contains(t, lit[1], "2:17pm")
}

func TestRunnerJevGuardOnMode(t *testing.T) {
	// The model promises; Jev catches it; the corrective round fixes it.
	model := newFakeAPI(t,
		toolUseResponse(toolUse("toolu_1", toolRampOutlookAt, `{"access_id":"NS-110","time_iso":"2026-06-12T14:00:00-04:00"}`)),
		textResponse("Flagler is going to be closed Friday afternoon, count on it."),
		textResponse("Flagler Ave could close around the 2:30pm high tide Friday."),
	)
	jevAPI := newFakeJev(t, map[string]any{"promises_closure": noulAnswer(0.9), "unsupported_claim": noulAnswer(0.1)})
	r := model.runner(defaultFake())
	r.SetJev(jevAPI.client(), ModeOn)
	assert.Equal(t, ModeOn, r.JevMode())

	// Route is Jev's too in on mode — script the router to send this to the model.
	jevAPI.answers["intent"] = choiceAnswer(intentOther, 0.9)

	resp, err := r.Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "Will Flagler be open Friday at 2pm?"}}})
	require.NoError(t, err)
	// Both replies scored 0.9 in this script, so the second check trips
	// too and the templated fallback wins: the engine's exact words.
	assert.Equal(t, "Flagler Ave, Friday ~2pm: Could close around the 2:30pm high tide. Closure possible around 2:30pm · often back open by ~4:30pm.", resp.Reply)
	assert.Equal(t, 3, resp.Usage.Calls)
}
