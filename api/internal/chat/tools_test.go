package chat

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/donwb/beach/api/internal/models"
	"github.com/donwb/beach/api/internal/predict"
)

// fakeEngine has a fixed clock and canned answers.
type fakeEngine struct {
	now     time.Time
	ramps   []models.RampStatusWithSince
	outlook func(accessID string, at time.Time) (*predict.RampOutlookAt, error)
	weekend *predict.WeekendOutlook
	wkErr   error
	cityNow func(city string) (*predict.CityNow, error)
	cityAt  func(city string, at time.Time) (*predict.CityOutlookAt, error)
}

func (f *fakeEngine) Now() time.Time { return f.now }
func (f *fakeEngine) Ramps(context.Context) ([]models.RampStatusWithSince, error) {
	return f.ramps, nil
}
func (f *fakeEngine) OutlookAt(_ context.Context, id string, at time.Time) (*predict.RampOutlookAt, error) {
	return f.outlook(id, at)
}
func (f *fakeEngine) Weekend(context.Context) (*predict.WeekendOutlook, error) {
	return f.weekend, f.wkErr
}
func (f *fakeEngine) CityNow(_ context.Context, city string) (*predict.CityNow, error) {
	if f.cityNow == nil {
		return nil, predict.ErrUnknownCity
	}
	return f.cityNow(city)
}
func (f *fakeEngine) CityOutlookAt(_ context.Context, city string, at time.Time) (*predict.CityOutlookAt, error) {
	if f.cityAt == nil {
		return nil, predict.ErrUnknownCity
	}
	return f.cityAt(city, at)
}

func fixedNow() time.Time { return time.Date(2026, 6, 10, 9, 0, 0, 0, eastern) }

func sampleOutlook(id string, at time.Time) *predict.RampOutlookAt {
	return &predict.RampOutlookAt{
		AccessID: id, Name: "Flagler Ave", City: "New Smyrna Beach", At: at, AtLabel: "Friday ~2pm", DaysOut: 2,
		Outlook: predict.RampOutlook{
			AccessID: id, Risk: predict.RiskPossible, Reason: predict.ReasonHighTide,
			Headline: "Could close around the 2:30pm high tide",
			Detail:   "Closure possible around 2:30pm · often back open by ~4:30pm",
			Window:   &predict.Window{Label: "11:30am–5pm"},
		},
		Relation: predict.RelationInside,
	}
}

func defaultFake() *fakeEngine {
	return &fakeEngine{
		now:   fixedNow(),
		ramps: rosterFixture(),
		outlook: func(id string, at time.Time) (*predict.RampOutlookAt, error) {
			if id != "NS-110" {
				return nil, predict.ErrUnknownRamp
			}
			if at.Before(fixedNow().Truncate(24 * time.Hour)) {
				return nil, predict.ErrPastTime
			}
			if at.After(fixedNow().AddDate(0, 0, 7)) {
				return nil, predict.ErrBeyondHorizon
			}
			return sampleOutlook(id, at), nil
		},
		cityNow: func(city string) (*predict.CityNow, error) {
			if city != "NEW SMYRNA BEACH" {
				return nil, predict.ErrUnknownCity
			}
			return &predict.CityNow{
				City: city, DisplayName: "New Smyrna Beach", Now: fixedNow(), OpenCount: 4, RampCount: 5,
				Verdict: &predict.CityVerdict{City: city, DisplayName: "New Smyrna Beach", State: "some_closed",
					Headline: "Four of five ramps open", Detail: "Flagler Ave closed for high tide since 8:40am · often back open by ~11am"},
				Ramps: []predict.CityRampAt{
					{AccessID: "NS-110", Name: "Flagler Ave", Status: "CLOSED FOR HIGH TIDE", Risk: predict.RiskClosedNow, Headline: "Closed for high tide"},
					{AccessID: "NS-141", Name: "27th Ave", Status: "OPEN", Risk: predict.RiskPossible, Headline: "Could close around the 10am high tide"},
				},
			}, nil
		},
		cityAt: func(city string, at time.Time) (*predict.CityOutlookAt, error) {
			if city != "NEW SMYRNA BEACH" {
				return nil, predict.ErrUnknownCity
			}
			if at.After(fixedNow().AddDate(0, 0, 7)) {
				return nil, predict.ErrBeyondHorizon
			}
			return &predict.CityOutlookAt{
				City: city, DisplayName: "New Smyrna Beach", At: at, AtLabel: "Saturday ~2pm", DaysOut: 3,
				Relation: predict.RelationOpenHours, RampCount: 5,
				Counts:  map[string]int{predict.RiskPossible: 2, predict.RiskScheduled: 3},
				Verdict: &predict.CityVerdict{Headline: "Every ramp open", Detail: "Two could shut on the ~2:30pm high"},
				Ramps: []predict.CityRampAt{
					{AccessID: "NS-110", Name: "Flagler Ave", Risk: predict.RiskPossible, Headline: "Could close around the 2:30pm high tide"},
				},
			}, nil
		},
		weekend: &predict.WeekendOutlook{
			Headline: "Saturday looks best",
			Days: []predict.WeekendDay{
				{Date: "2026-06-13", Weekday: "Saturday", IsWeekend: true, Verdict: "great", Headline: "Clear all day", Detail: "No tide trouble expected", ClosureRiskLabel: "Clear all day", Basis: []string{"tide"}},
			},
		},
	}
}

func TestExecToolResolve(t *testing.T) {
	out := execTool(context.Background(), defaultFake(), toolResolveRamp, json.RawMessage(`{"query":"flagler"}`))
	require.False(t, out.isError)
	var res Resolution
	require.NoError(t, json.Unmarshal([]byte(out.content), &res))
	assert.True(t, res.Exact)
	assert.Equal(t, "NS-110", res.Matches[0].AccessID)
	assert.Empty(t, out.sources, "resolving is not a fact the card shows")
}

func TestExecToolOutlookAt(t *testing.T) {
	eng := defaultFake()

	out := execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"ns-110","time_iso":"2026-06-12T14:00:00-04:00"}`))
	require.False(t, out.isError, out.content)
	require.Len(t, out.sources, 1)
	src := out.sources[0]
	assert.Equal(t, "ramp_outlook", src.Kind)
	assert.Equal(t, "NS-110", src.AccessID)
	assert.Equal(t, predict.RiskPossible, src.Risk)
	assert.Equal(t, "11:30am–5pm", src.WindowLabel)
	assert.Contains(t, out.content, `"target_vs_hours":"inside"`)

	// A bare local timestamp reads as Eastern.
	out = execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"NS-110","time_iso":"2026-06-12T14:00"}`))
	require.False(t, out.isError, out.content)
	assert.Equal(t, time.Date(2026, 6, 12, 14, 0, 0, 0, eastern), *out.sources[0].At)

	// Horizon errors come back as plain sentences the model can relay.
	out = execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"NS-110","time_iso":"2026-06-01T14:00:00-04:00"}`))
	assert.True(t, out.isError)
	assert.Equal(t, predict.ErrPastTime.Error(), out.content)

	out = execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"NS-110","time_iso":"2026-06-20T14:00:00-04:00"}`))
	assert.True(t, out.isError)
	assert.Equal(t, predict.ErrBeyondHorizon.Error(), out.content)

	out = execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"XX-1","time_iso":"2026-06-12T14:00:00-04:00"}`))
	assert.True(t, out.isError)

	out = execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"NS-110","time_iso":"friday"}`))
	assert.True(t, out.isError)
	assert.Contains(t, out.content, "time_iso")

	// Any other failure is a generic sentence, never a stack of internals.
	eng.outlook = func(string, time.Time) (*predict.RampOutlookAt, error) {
		return nil, errors.New("pg: connection refused")
	}
	out = execTool(context.Background(), eng, toolRampOutlookAt, json.RawMessage(`{"access_id":"NS-110","time_iso":"2026-06-12T14:00:00-04:00"}`))
	assert.True(t, out.isError)
	assert.NotContains(t, out.content, "pg:")
}

func TestExecToolWeekend(t *testing.T) {
	eng := defaultFake()
	out := execTool(context.Background(), eng, toolWeekend, json.RawMessage(`{}`))
	require.False(t, out.isError)
	assert.Contains(t, out.content, `"verdict":"great"`)
	assert.NotContains(t, out.content, `"basis"`, "model echoes stay out of the model's context")
	require.Len(t, out.sources, 1)
	assert.Equal(t, "weekend_day", out.sources[0].Kind)
	assert.Equal(t, "Saturday", out.sources[0].Weekday)

	eng.weekend, eng.wkErr = nil, ErrWeekendOff
	out = execTool(context.Background(), eng, toolWeekend, json.RawMessage(`{}`))
	assert.True(t, out.isError)
	assert.Equal(t, ErrWeekendOff.Error(), out.content)
}

func TestNowBlockNamesTheWeek(t *testing.T) {
	b := nowBlock(fixedNow(), "NS-110", "")
	assert.Contains(t, b, "Wednesday 2026-06-10 9:00am Eastern")
	assert.Contains(t, b, "Offset for timestamps: -04:00")
	assert.Contains(t, b, "tomorrow=Thu 2026-06-11")
	assert.Contains(t, b, "Saturday=Sat 2026-06-13")
	assert.Contains(t, b, "ramp_context: the user is looking at ramp access_id NS-110")
	assert.NotContains(t, nowBlock(fixedNow(), "", ""), "ramp_context")
}

func TestExecToolCityNow(t *testing.T) {
	eng := defaultFake()
	for _, q := range []string{"NSB", "New Smyrna Beach", "new smyrna", "the beach in nsb"} {
		out := execTool(context.Background(), eng, toolCityNow, json.RawMessage(`{"city":"`+q+`"}`))
		require.False(t, out.isError, q+": "+out.content)
		require.Len(t, out.sources, 1)
		src := out.sources[0]
		assert.Equal(t, "city_now", src.Kind)
		assert.Equal(t, "New Smyrna Beach", src.City)
		assert.Equal(t, "Four of five ramps open", src.Headline)
		require.NotNil(t, src.OpenCount)
		assert.Equal(t, 4, *src.OpenCount)
		assert.Len(t, src.Ramps, 2)
		assert.Equal(t, "CLOSED FOR HIGH TIDE", src.Ramps[0].Status)
	}

	out := execTool(context.Background(), eng, toolCityNow, json.RawMessage(`{"city":"Cocoa Beach"}`))
	assert.True(t, out.isError)
	assert.Contains(t, out.content, "Ormond Beach")

	out = execTool(context.Background(), eng, toolCityNow, json.RawMessage(`{"city":"Ormond"}`))
	assert.True(t, out.isError, "the fake only knows NSB")
}

func TestExecToolCityAt(t *testing.T) {
	eng := defaultFake()
	out := execTool(context.Background(), eng, toolCityAt, json.RawMessage(`{"city":"nsb","time_iso":"2026-06-13T14:00:00-04:00"}`))
	require.False(t, out.isError, out.content)
	require.Len(t, out.sources, 1)
	src := out.sources[0]
	assert.Equal(t, "city_outlook", src.Kind)
	assert.Equal(t, "Saturday ~2pm", src.AtLabel)
	assert.Equal(t, predict.RelationOpenHours, src.Relation)
	assert.Equal(t, "Every ramp open", src.Headline)
	assert.Contains(t, out.content, `"counts":{"possible":2,"scheduled":3}`)

	out = execTool(context.Background(), eng, toolCityAt, json.RawMessage(`{"city":"nsb","time_iso":"2026-06-30T14:00:00-04:00"}`))
	assert.True(t, out.isError)
	assert.Equal(t, predict.ErrBeyondHorizon.Error(), out.content)
}

func TestNowBlockCarriesBoardCity(t *testing.T) {
	b := nowBlock(fixedNow(), "", "Daytona Beach")
	assert.Contains(t, b, "board_context: the board is showing Daytona Beach")
	assert.NotContains(t, b, "ramp_context")
}
