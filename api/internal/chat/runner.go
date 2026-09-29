package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

const (
	// DefaultModel is the model used when CHAT_MODEL is unset.
	DefaultModel = "claude-opus-5"

	// DefaultVoiceModel answers spoken free-form questions (CHAT_VOICE_MODEL
	// unset): the current-generation faster tier, because a listener waits
	// seconds, not tens of seconds.
	DefaultVoiceModel = "claude-sonnet-5"

	// maxIterations caps the tool loop: resolve, outlook, maybe a second
	// ramp or the weekend, then the answer. Anything past six is a model
	// going in circles.
	maxIterations = 6

	// maxTokens is a deliberate short-answer cap; replies are two or three
	// sentences.
	maxTokens = 2048

	refusedReply   = "I can't help with that one."
	stalledReply   = "I couldn't get a straight answer from the outlook on that one. Try asking about one ramp and one time."
	noAnswerReply  = "I didn't come up with an answer for that. Try asking about one ramp at one time."
	correctiveTurn = "Rewrite your last answer using only the engine's exact headline and detail wording. A closure is \"possible\" or \"could\", never \"will\" or \"likely\", unless the engine's risk was exactly \"likely\". Quote only the clock times that appear in the engine's strings. Two or three plain sentences."
)

// Runner owns the model client and drives the tool loop.
type Runner struct {
	client     anthropic.Client
	model      string
	voiceModel string // used for Voice requests; empty = model
	engine     Engine
}

// SetVoiceModel names the model for spoken (Voice) requests — a faster one,
// since Siri and a person holding a phone to their ear both give up early.
func (r *Runner) SetVoiceModel(model string) {
	r.voiceModel = model
}

// New builds a Runner. The client reads ANTHROPIC_API_KEY from the
// environment unless opts override it; tests pass option.WithBaseURL to a
// fake server.
func New(engine Engine, model string, opts ...option.RequestOption) *Runner {
	if model == "" {
		model = DefaultModel
	}
	return &Runner{client: anthropic.NewClient(opts...), model: model, engine: engine}
}

// Run answers the transcript's last user turn. It returns an error only
// when the model API itself failed; a refusal, a stalled loop, or a tool
// that errored are all normal replies.
func (r *Runner) Run(ctx context.Context, req Request) (*Response, error) {
	start := time.Now()
	now := r.engine.Now()

	contextID, contextCity, contextCityRaw := "", "", ""
	if req.Context != nil {
		contextID = strings.ToUpper(strings.TrimSpace(req.Context.AccessID))
		contextCityRaw = req.Context.City
		if _, display, ok := ResolveCity(req.Context.City); ok {
			contextCity = display
		}
	}

	// The quick path: a fresh question in one of the shapes the router
	// knows is answered from the engine's own copy, no model. Only for the
	// first turn — a follow-up needs the conversation.
	if len(req.Messages) == 1 {
		if resp, ok := TryQuick(ctx, r.engine, req.Messages[0].Text, contextCityRaw); ok {
			slog.Info("chat.quick", "voice", req.Voice, "ms", time.Since(start).Milliseconds())
			return resp, nil
		}
	}

	model := r.model
	if req.Voice && r.voiceModel != "" {
		model = r.voiceModel
	}

	messages := make([]anthropic.MessageParam, 0, len(req.Messages))
	for _, t := range req.Messages {
		if t.Role == RoleAssistant {
			messages = append(messages, anthropic.NewAssistantMessage(anthropic.NewTextBlock(t.Text)))
		} else {
			messages = append(messages, anthropic.NewUserMessage(anthropic.NewTextBlock(t.Text)))
		}
	}

	// Thinking is left at the model's default on purpose: Claude Opus 5 and
	// Sonnet 5 run adaptive thinking when the field is omitted, and omitting
	// it keeps CHAT_MODEL swappable to a model that rejects the parameter.
	params := anthropic.MessageNewParams{
		Model:     anthropic.Model(model),
		MaxTokens: maxTokens,
		System: []anthropic.TextBlockParam{
			{Text: systemPrompt, CacheControl: anthropic.NewCacheControlEphemeralParam()},
			{Text: nowBlock(now, contextID, contextCity)},
		},
		Tools:    toolDefs(),
		Messages: messages,
	}

	resp := &Response{Model: model, Sources: []Source{}, GeneratedAt: now.UTC()}
	slog.Info("chat.request", "turns", len(req.Messages), "context", contextID, "city", contextCity, "voice", req.Voice, "model", model)

	var lastText string
	stalled := true
	for iter := 0; iter < maxIterations; iter++ {
		msg, err := r.client.Messages.New(ctx, params)
		if err != nil {
			return nil, describeAPIError(err)
		}
		resp.Usage.Calls++
		resp.Usage.InputTokens += msg.Usage.InputTokens + msg.Usage.CacheReadInputTokens + msg.Usage.CacheCreationInputTokens
		resp.Usage.OutputTokens += msg.Usage.OutputTokens
		params.Messages = append(params.Messages, msg.ToParam())

		var results []anthropic.ContentBlockParamUnion
		var texts []string
		for _, block := range msg.Content {
			switch v := block.AsAny().(type) {
			case anthropic.TextBlock:
				if strings.TrimSpace(v.Text) != "" {
					texts = append(texts, strings.TrimSpace(v.Text))
				}
			case anthropic.ToolUseBlock:
				t0 := time.Now()
				out := execTool(ctx, r.engine, v.Name, json.RawMessage(v.JSON.Input.Raw()))
				slog.Info("chat.tool", "name", v.Name, "ms", time.Since(t0).Milliseconds(), "is_error", out.isError)
				results = append(results, anthropic.NewToolResultBlock(v.ID, out.content, out.isError))
				resp.Sources = append(resp.Sources, out.sources...)
			}
		}
		if len(texts) > 0 {
			lastText = strings.Join(texts, "\n\n")
		}

		switch msg.StopReason {
		case anthropic.StopReasonRefusal:
			resp.Reply = refusedReply
			resp.Sources = []Source{}
			slog.Warn("chat.refused", "category", msg.StopDetails.Category)
			return r.finish(resp, start), nil
		case anthropic.StopReasonToolUse:
			if len(results) == 0 {
				// Defensive: a tool_use stop with no tool blocks.
				stalled = true
				continue
			}
			// Every result rides in one user turn.
			params.Messages = append(params.Messages, anthropic.NewUserMessage(results...))
			continue
		default:
			stalled = false
		}
		break
	}

	if stalled {
		resp.Reply = stalledReply
		slog.Warn("chat.stalled", "iterations", maxIterations)
		return r.finish(resp, start), nil
	}
	if lastText == "" {
		resp.Reply = noAnswerReply
		return r.finish(resp, start), nil
	}
	resp.Reply = lastText

	// The copy guard: one corrective round, then the engine's own words.
	if problems := checkCopy(resp.Reply, resp.Sources); len(problems) > 0 {
		slog.Warn("chat.guard_tripped", "problems", problems)
		params.Messages = append(params.Messages, anthropic.NewUserMessage(anthropic.NewTextBlock(correctiveTurn)))
		msg, err := r.client.Messages.New(ctx, params)
		if err == nil {
			resp.Usage.Calls++
			resp.Usage.InputTokens += msg.Usage.InputTokens + msg.Usage.CacheReadInputTokens + msg.Usage.CacheCreationInputTokens
			resp.Usage.OutputTokens += msg.Usage.OutputTokens
			var texts []string
			for _, block := range msg.Content {
				if v, ok := block.AsAny().(anthropic.TextBlock); ok && strings.TrimSpace(v.Text) != "" {
					texts = append(texts, strings.TrimSpace(v.Text))
				}
			}
			if len(texts) > 0 {
				resp.Reply = strings.Join(texts, "\n\n")
			}
		}
		if again := checkCopy(resp.Reply, resp.Sources); len(again) > 0 || err != nil {
			slog.Warn("chat.guard_fallback", "problems", again, "err", err)
			resp.Reply = templatedReply(resp.Sources)
		}
	}
	return r.finish(resp, start), nil
}

func (r *Runner) finish(resp *Response, start time.Time) *Response {
	resp.Spoken = spokenForm(resp.Reply)
	slog.Info("chat.done",
		"calls", resp.Usage.Calls,
		"input_tokens", resp.Usage.InputTokens,
		"output_tokens", resp.Usage.OutputTokens,
		"sources", len(resp.Sources),
		"ms", time.Since(start).Milliseconds())
	return resp
}

// describeAPIError wraps a model API failure with its status so the log
// distinguishes a bad key (401) from a rate limit (429) from an outage.
func describeAPIError(err error) error {
	var apierr *anthropic.Error
	if errors.As(err, &apierr) {
		return fmt.Errorf("model api: status %d: %w", apierr.StatusCode, err)
	}
	return fmt.Errorf("model api: %w", err)
}
