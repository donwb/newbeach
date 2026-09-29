package chat

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/predict"
)

// fixedNow is Wednesday 2026-06-10 9:00am ET.

func TestQuickWhen(t *testing.T) {
	now := fixedNow()
	e := func(day, hour, min int) time.Time { return time.Date(2026, 6, day, hour, min, 0, 0, eastern) }

	tests := []struct {
		q     string
		want  time.Time
		isNow bool
		ok    bool
	}{
		{"can I get on the beach in NSB right now", now, true, true},
		{"are the Daytona ramps open", now, true, true},
		{"is the beach open today", now, true, true},
		{"can I get on the beach this afternoon", e(10, 14, 0), false, true},
		{"is the beach open this evening", e(10, 18, 0), false, true},
		{"are the ramps open tomorrow morning", e(11, 10, 0), false, true},
		{"are the ramps open tomorrow", e(11, 14, 0), false, true},
		{"are the Daytona ramps open Saturday at 2", e(13, 14, 0), false, true},
		{"is the beach open saturday at 2:30pm", e(13, 14, 30), false, true},
		{"is the beach open sat around 10am", e(13, 10, 0), false, true},
		{"can I get on the beach friday at noon", e(12, 12, 0), false, true},
		{"is the beach open at 5", e(10, 17, 0), false, true},
		{"is the beach open at 8am", e(10, 8, 0), false, false}, // already past at 9am
		{"was the beach open yesterday", time.Time{}, false, false},
		{"is the beach open later", time.Time{}, false, false},
		{"is the beach open wednesday", time.Time{}, false, false}, // today is Wednesday: ambiguous
		{"is the beach open next week", time.Time{}, false, false},
	}
	for _, tt := range tests {
		t.Run(tt.q, func(t *testing.T) {
			at, isNow, ok := quickWhen(tt.q, now)
			assert.Equal(t, tt.ok, ok, "ok")
			if tt.ok {
				assert.Equal(t, tt.isNow, isNow, "isNow")
				if !tt.isNow {
					assert.Equal(t, tt.want, at)
				}
			}
		})
	}
}

func TestTryQuickCityNow(t *testing.T) {
	eng := defaultFake()
	for _, q := range []string{
		"Can I get on the beach in NSB right now?",
		"Are the New Smyrna ramps open?",
		"is the beach open in new smyrna beach",
	} {
		resp, ok := TryQuick(context.Background(), eng, q, "")
		require.True(t, ok, q)
		assert.Equal(t, "quick", resp.Model)
		assert.Equal(t, "Four of five ramps open. Flagler Ave closed for high tide since 8:40am · often back open by ~11am.", resp.Reply, "the written reply keeps the engine glyphs")
		assert.Equal(t, "Four of five ramps open. Flagler Ave closed for high tide since 8:40am. Often back open by about 11am.", resp.Spoken)
		require.Len(t, resp.Sources, 1)
		assert.Equal(t, "city_now", resp.Sources[0].Kind)
	}

	// The board's city fills in when the question names none.
	resp, ok := TryQuick(context.Background(), eng, "Can I get on the beach right now?", "nsb")
	require.True(t, ok)
	assert.Equal(t, "city_now", resp.Sources[0].Kind)

	// No city anywhere → the model's problem.
	_, ok = TryQuick(context.Background(), eng, "Can I get on the beach right now?", "")
	assert.False(t, ok)

	// A city the engine doesn't know → fall through, never an error.
	_, ok = TryQuick(context.Background(), eng, "Are the Ormond ramps open?", "")
	assert.False(t, ok)
}

func TestTryQuickCityAt(t *testing.T) {
	eng := defaultFake()
	resp, ok := TryQuick(context.Background(), eng, "Are the NSB ramps open Saturday at 2?", "")
	require.True(t, ok)
	assert.Equal(t, "New Smyrna Beach, Saturday ~2pm: every ramp open. Two could shut on the ~2:30pm high. Flagler Ave could close for the tide.", resp.Reply)
	assert.Contains(t, resp.Spoken, "Saturday about 2pm")
	assert.Equal(t, "city_outlook", resp.Sources[0].Kind)

	// Beyond the horizon → fall through.
	_, ok = TryQuick(context.Background(), eng, "Are the NSB ramps open next week", "")
	assert.False(t, ok)
}

func TestTryQuickWeekend(t *testing.T) {
	eng := defaultFake()
	resp, ok := TryQuick(context.Background(), eng, "Which day this weekend is best?", "nsb")
	require.True(t, ok)
	assert.Equal(t, "Saturday looks best. Saturday: clear all day.", resp.Reply)
	assert.Equal(t, "weekend_day", resp.Sources[0].Kind)

	_, ok = TryQuick(context.Background(), eng, "What does the outlook say about Flagler on Friday?", "nsb")
	assert.False(t, ok, "not a shape the router knows")
	_, ok = TryQuick(context.Background(), eng, "hi", "nsb")
	assert.False(t, ok)
}

func TestSpokenForm(t *testing.T) {
	assert.Equal(t, "Closure possible around 2:30pm. often back open by about 4:30pm", spokenForm("Closure possible around 2:30pm · often back open by ~4:30pm"))
	assert.Equal(t, "Best stretch about 8am to 12pm, clear of the tide", spokenForm("Best stretch ~8am–12pm — clear of the tide"))
	assert.Equal(t, "Seven could shut on the 3pm high.", spokenForm("Seven could shut on the ~3pm high."))
	assert.Equal(t, "Closed for high tide since 7:44am. Often back open around 3pm.", spokenForm("Closed for high tide since 7:44am · often back open around 3pm."))
}

func TestRegexRouteWithRosterRampShapes(t *testing.T) {
	now := fixedNow()
	ramps := rosterFixture()

	plan, ok := regexRouteWithRoster("Is Flagler open right now?", "", now, ramps)
	require.True(t, ok)
	assert.Equal(t, planRampNow, plan.Kind)
	assert.Equal(t, "NS-110", plan.AccessID)
	assert.Equal(t, "NEW SMYRNA BEACH", plan.City)

	plan, ok = regexRouteWithRoster("Will 27th Ave be open tomorrow at 2?", "", now, ramps)
	require.True(t, ok)
	assert.Equal(t, planRampAt, plan.Kind)
	assert.Equal(t, "NS-141", plan.AccessID)
	assert.Equal(t, time.Date(2026, 6, 11, 14, 0, 0, 0, eastern), plan.At)

	plan, ok = regexRouteWithRoster("Is NSB open?", "", now, ramps)
	require.True(t, ok, "a city alias in the ramp slot is the city plan")
	assert.Equal(t, planCityNow, plan.Kind)

	// The city shapes still route first, and unknown names fall through.
	plan, ok = regexRouteWithRoster("Are the Daytona ramps open?", "", now, ramps)
	require.True(t, ok)
	assert.Equal(t, planCityNow, plan.Kind)
	_, ok = regexRouteWithRoster("Is it open?", "", now, ramps)
	assert.False(t, ok)
	_, ok = regexRouteWithRoster("Is Flagler open right now?", "", now, nil)
	assert.False(t, ok, "no roster, no ramp plan")
	_, ok = regexRouteWithRoster("Was Flagler open yesterday?", "", now, ramps)
	assert.False(t, ok)
}

func TestQuickRampNowReplySaysTheStatusOnce(t *testing.T) {
	c := &predict.CityNow{DisplayName: "New Smyrna Beach"}
	r := predict.CityRampAt{Name: "Flagler Ave", Status: "CLOSED FOR HIGH TIDE", Headline: "Closed for high tide", Detail: "often back open around 3pm"}
	assert.Equal(t, "Flagler Ave is closed for high tide right now. often back open around 3pm.", quickRampNowReply(c, r))
	open := predict.CityRampAt{Name: "27th Ave", Status: "OPEN", Headline: "Could close around the 3pm high tide", Detail: "Closure possible around 3pm"}
	assert.Equal(t, "27th Ave is open right now. Could close around the 3pm high tide. Closure possible around 3pm.", quickRampNowReply(c, open))
}
