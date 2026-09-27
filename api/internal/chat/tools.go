package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/anthropics/anthropic-sdk-go"

	"github.com/donwb/beach/api/internal/predict"
)

const (
	toolResolveRamp   = "resolve_ramp"
	toolRampOutlookAt = "ramp_outlook_at"
	toolWeekend       = "weekend_outlook"
)

// toolDefs are the three tools the model may call. Descriptions carry the
// rules the schema cannot.
func toolDefs() []anthropic.ToolUnionParam {
	resolve := anthropic.ToolParam{
		Name:        toolResolveRamp,
		Description: anthropic.String("Find a beach access ramp by the name a person would use (\"Flagler\", \"27th Ave\", \"Cardinal in Ormond\", \"Dunlawton\"). Returns matching ramps with their access_id. When exact is false, ask the user which one they mean; when no ramp matches, the whole roster is included grouped by city."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"query": map[string]any{"type": "string", "description": "The ramp as the user said it, optionally with a city."},
			},
			Required: []string{"query"},
		},
	}
	outlookAt := anthropic.ToolParam{
		Name:        toolRampOutlookAt,
		Description: anthropic.String("The prediction engine's read on one ramp at one instant, today through about seven days ahead: risk (none|possible|likely|scheduled|closed_now), reason, headline and detail copy to quote, the predicted closure window, and where the instant falls against that day's driving hours (target_vs_hours). Returns an error sentence for a past instant or one too far ahead."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"access_id": map[string]any{"type": "string", "description": "The ramp's access_id from resolve_ramp or ramp_context, e.g. NS-110."},
				"time_iso":  map[string]any{"type": "string", "description": "The instant asked about as ISO 8601 with the Eastern offset, e.g. 2026-09-27T14:00:00-04:00."},
			},
			Required: []string{"access_id", "time_iso"},
		},
	}
	weekend := anthropic.ToolParam{
		Name:        toolWeekend,
		Description: anthropic.String("The next seven days graded for a beach day: per-day verdict (great|good|mixed|tough|no_call), headline, why, detail, best window, closure risk label, and weather attributes. Use for \"which day is best\" and whole-day questions. Does not name individual ramps."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{},
		},
	}
	return []anthropic.ToolUnionParam{{OfTool: &resolve}, {OfTool: &outlookAt}, {OfTool: &weekend}}
}

// toolOutcome is what one tool execution produced: the text handed back to
// the model, whether it was an error, and the facts the client should see.
type toolOutcome struct {
	content string
	isError bool
	sources []Source
}

// execTool runs one tool call. Errors the user should hear about come back
// as is_error results in plain words; nothing here panics or returns a Go
// error to the loop, because a failed tool is a normal conversational turn.
func execTool(ctx context.Context, eng Engine, name string, input json.RawMessage) toolOutcome {
	switch name {
	case toolResolveRamp:
		var in struct {
			Query string `json:"query"`
		}
		if err := json.Unmarshal(input, &in); err != nil {
			return toolOutcome{content: "malformed input: " + err.Error(), isError: true}
		}
		ramps, err := eng.Ramps(ctx)
		if err != nil {
			return toolOutcome{content: "the ramp roster is not available right now", isError: true}
		}
		return jsonOutcome(Resolve(ramps, in.Query), nil)

	case toolRampOutlookAt:
		var in struct {
			AccessID string `json:"access_id"`
			TimeISO  string `json:"time_iso"`
		}
		if err := json.Unmarshal(input, &in); err != nil {
			return toolOutcome{content: "malformed input: " + err.Error(), isError: true}
		}
		at, err := parseInstant(in.TimeISO)
		if err != nil {
			return toolOutcome{content: "time_iso could not be read: " + err.Error(), isError: true}
		}
		res, err := eng.OutlookAt(ctx, strings.ToUpper(strings.TrimSpace(in.AccessID)), at)
		if err != nil {
			switch {
			case errors.Is(err, predict.ErrPastTime), errors.Is(err, predict.ErrBeyondHorizon), errors.Is(err, predict.ErrUnknownRamp):
				return toolOutcome{content: err.Error(), isError: true}
			default:
				return toolOutcome{content: "the outlook is not available right now", isError: true}
			}
		}
		return jsonOutcome(res, []Source{sourceFromOutlook(res)})

	case toolWeekend:
		wk, err := eng.Weekend(ctx)
		if err != nil {
			if errors.Is(err, ErrWeekendOff) {
				return toolOutcome{content: err.Error(), isError: true}
			}
			return toolOutcome{content: "the weekend outlook is not available right now", isError: true}
		}
		return jsonOutcome(trimWeekend(wk), sourcesFromWeekend(wk))

	default:
		return toolOutcome{content: "unknown tool " + name, isError: true}
	}
}

func jsonOutcome(v any, sources []Source) toolOutcome {
	b, err := json.Marshal(v)
	if err != nil {
		return toolOutcome{content: "could not encode the result", isError: true}
	}
	return toolOutcome{content: string(b), sources: sources}
}

// parseInstant accepts RFC 3339 (with offset) and, as a fallback, a bare
// local timestamp read as Eastern.
func parseInstant(s string) (time.Time, error) {
	s = strings.TrimSpace(s)
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t, nil
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02T15:04", "2006-01-02 15:04"} {
		if t, err := time.ParseInLocation(layout, s, eastern); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("expected an ISO 8601 timestamp, got %q", s)
}

func sourceFromOutlook(r *predict.RampOutlookAt) Source {
	at := r.At
	s := Source{
		Kind:     "ramp_outlook",
		AccessID: r.AccessID,
		Name:     r.Name,
		City:     r.City,
		At:       &at,
		AtLabel:  r.AtLabel,
		Risk:     r.Outlook.Risk,
		Reason:   r.Outlook.Reason,
		Headline: r.Outlook.Headline,
		Detail:   r.Outlook.Detail,
		Relation: r.Relation,
	}
	if r.Outlook.Window != nil {
		s.WindowLabel = r.Outlook.Window.Label
	}
	if r.Outlook.Reopen != nil {
		s.ReopenLabel = r.Outlook.Reopen.Label
	}
	return s
}

// weekendDay is the WeekendDay trimmed to what a narrator needs — the
// model echoes (drivers, basis, surge) stay out of the model's context.
type weekendDay struct {
	Date             string   `json:"date"`
	Weekday          string   `json:"weekday"`
	IsWeekend        bool     `json:"is_weekend"`
	Verdict          string   `json:"verdict"`
	Headline         string   `json:"headline"`
	Why              string   `json:"why,omitempty"`
	Detail           string   `json:"detail,omitempty"`
	BestWindow       string   `json:"best_window,omitempty"`
	ClosurePressure  string   `json:"closure_pressure"`
	ClosureRiskLabel string   `json:"closure_risk_label"`
	SurfLabel        string   `json:"surf_label,omitempty"`
	Opens            string   `json:"opens,omitempty"`
	Closes           string   `json:"closes,omitempty"`
	HighTempF        *float64 `json:"high_temp_f,omitempty"`
	FeelsLikeF       *float64 `json:"feels_like_f,omitempty"`
	RainChancePct    *float64 `json:"rain_chance_pct,omitempty"`
	WindLabel        string   `json:"wind_label,omitempty"`
}

type weekendSummary struct {
	Headline string       `json:"headline"`
	Days     []weekendDay `json:"days"`
}

func trimWeekend(w *predict.WeekendOutlook) weekendSummary {
	out := weekendSummary{Headline: w.Headline}
	for _, d := range w.Days {
		wd := weekendDay{
			Date: d.Date, Weekday: d.Weekday, IsWeekend: d.IsWeekend, Verdict: d.Verdict,
			Headline: d.Headline, Why: d.Why, Detail: d.Detail,
			ClosurePressure: d.ClosurePressure, ClosureRiskLabel: d.ClosureRiskLabel, SurfLabel: d.SurfLabel,
			Opens: d.Schedule.OpensLabel, Closes: d.Schedule.ClosesLabel,
			HighTempF: d.HighTempF, FeelsLikeF: d.FeelsLikeF, RainChancePct: d.RainChancePct, WindLabel: d.WindLabel,
		}
		if d.BestWindow != nil {
			wd.BestWindow = d.BestWindow.Label
		}
		out.Days = append(out.Days, wd)
	}
	return out
}

func sourcesFromWeekend(w *predict.WeekendOutlook) []Source {
	out := make([]Source, 0, len(w.Days))
	for _, d := range w.Days {
		s := Source{
			Kind:             "weekend_day",
			Date:             d.Date,
			Weekday:          d.Weekday,
			Verdict:          d.Verdict,
			Headline:         d.Headline,
			Detail:           d.Detail,
			ClosureRiskLabel: d.ClosureRiskLabel,
		}
		if d.BestWindow != nil {
			s.BestWindowLabel = d.BestWindow.Label
		}
		out = append(out, s)
	}
	return out
}
