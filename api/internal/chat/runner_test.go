package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/anthropics/anthropic-sdk-go/option"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeAPI scripts the Messages API: each request pops the next canned
// response body and records the request it received, so the test can check
// what the loop sent back.
type fakeAPI struct {
	mu        sync.Mutex
	responses []string
	requests  []map[string]any
	srv       *httptest.Server
}

func newFakeAPI(t *testing.T, responses ...string) *fakeAPI {
	f := &fakeAPI{responses: responses}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req map[string]any
		_ = json.Unmarshal(body, &req)
		f.mu.Lock()
		f.requests = append(f.requests, req)
		if len(f.responses) == 0 {
			f.mu.Unlock()
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"type":"error","error":{"type":"api_error","message":"script exhausted"}}`))
			return
		}
		next := f.responses[0]
		f.responses = f.responses[1:]
		f.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(next))
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeAPI) runner(eng Engine) *Runner {
	return New(eng, "claude-test", option.WithBaseURL(f.srv.URL), option.WithAPIKey("test-key"), option.WithMaxRetries(0))
}

func textResponse(text string) string {
	return fmt.Sprintf(`{"id":"msg_t","type":"message","role":"assistant","model":"claude-test","content":[{"type":"text","text":%q}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":20}}`, text)
}

func toolUseResponse(calls ...string) string {
	return fmt.Sprintf(`{"id":"msg_u","type":"message","role":"assistant","model":"claude-test","content":[%s],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":30}}`, joinCSV(calls))
}

func toolUse(id, name, input string) string {
	return fmt.Sprintf(`{"type":"tool_use","id":%q,"name":%q,"input":%s}`, id, name, input)
}

func joinCSV(parts []string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += ","
		}
		out += p
	}
	return out
}

func lastUserContent(t *testing.T, req map[string]any) []map[string]any {
	msgs := req["messages"].([]any)
	last := msgs[len(msgs)-1].(map[string]any)
	require.Equal(t, "user", last["role"])
	blocks := last["content"].([]any)
	out := make([]map[string]any, 0, len(blocks))
	for _, b := range blocks {
		out = append(out, b.(map[string]any))
	}
	return out
}

func TestRunnerToolLoop(t *testing.T) {
	api := newFakeAPI(t,
		toolUseResponse(toolUse("toolu_1", toolResolveRamp, `{"query":"flagler"}`)),
		toolUseResponse(toolUse("toolu_2", toolRampOutlookAt, `{"access_id":"NS-110","time_iso":"2026-06-12T14:00:00-04:00"}`)),
		textResponse("Flagler Ave could close around the 2:30pm high tide on Friday. Closure possible around 2:30pm, often back open by ~4:30pm."),
	)
	r := api.runner(defaultFake())

	resp, err := r.Run(context.Background(), Request{
		Messages: []Turn{
			{Role: RoleUser, Text: "hi"},
			{Role: RoleAssistant, Text: "Hello! Ask me about a ramp."},
			{Role: RoleUser, Text: "Will Flagler be open Friday at 2pm?"},
		},
		Context: &Context{AccessID: "ns-110", City: "nsb"},
	})
	require.NoError(t, err)

	assert.Contains(t, resp.Reply, "could close around the 2:30pm")
	require.Len(t, resp.Sources, 1)
	assert.Equal(t, "NS-110", resp.Sources[0].AccessID)
	assert.Equal(t, 3, resp.Usage.Calls)
	assert.Equal(t, int64(300), resp.Usage.InputTokens)
	assert.Equal(t, "claude-test", resp.Model)

	require.Len(t, api.requests, 3)
	first := api.requests[0]
	// The prior transcript rides along, and the system carries the clock and
	// the ramp context.
	assert.Len(t, first["messages"].([]any), 3)
	sys := first["system"].([]any)
	require.Len(t, sys, 2)
	assert.Contains(t, sys[1].(map[string]any)["text"], "ramp_context: the user is looking at ramp access_id NS-110")
	assert.Contains(t, sys[1].(map[string]any)["text"], "board_context: the board is showing New Smyrna Beach")
	assert.NotNil(t, sys[0].(map[string]any)["cache_control"], "the stable prompt is a cache breakpoint")
	assert.Len(t, first["tools"].([]any), 5)
	_, hasThinking := first["thinking"]
	assert.False(t, hasThinking, "thinking left at the model default")

	// Each tool result went back as a user turn with the matching id.
	second := lastUserContent(t, api.requests[1])
	require.Len(t, second, 1)
	assert.Equal(t, "tool_result", second[0]["type"])
	assert.Equal(t, "toolu_1", second[0]["tool_use_id"])
	third := lastUserContent(t, api.requests[2])
	assert.Equal(t, "toolu_2", third[0]["tool_use_id"])
}

func TestRunnerParallelToolResultsShareOneTurn(t *testing.T) {
	api := newFakeAPI(t,
		toolUseResponse(
			toolUse("toolu_a", toolRampOutlookAt, `{"access_id":"NS-110","time_iso":"2026-06-12T14:00:00-04:00"}`),
			toolUse("toolu_b", toolWeekend, `{}`),
		),
		textResponse("Flagler Ave could close around the 2:30pm high tide; Saturday looks best with no tide trouble expected."),
	)
	resp, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "Flagler Friday 2pm, and the week ahead?"}}})
	require.NoError(t, err)
	assert.Len(t, resp.Sources, 2)

	results := lastUserContent(t, api.requests[1])
	require.Len(t, results, 2, "both results in ONE user message")
	assert.Equal(t, "toolu_a", results[0]["tool_use_id"])
	assert.Equal(t, "toolu_b", results[1]["tool_use_id"])
}

func TestRunnerToolErrorIsRelayedNotFatal(t *testing.T) {
	api := newFakeAPI(t,
		toolUseResponse(toolUse("toolu_1", toolRampOutlookAt, `{"access_id":"NS-110","time_iso":"2026-06-01T14:00:00-04:00"}`)),
		textResponse("That time has already passed; I can only look ahead about a week. Want tomorrow instead?"),
	)
	resp, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "Was Flagler open on June 1?"}}})
	require.NoError(t, err)
	assert.Contains(t, resp.Reply, "already passed")
	assert.Empty(t, resp.Sources)

	results := lastUserContent(t, api.requests[1])
	assert.Equal(t, true, results[0]["is_error"])
}

func TestRunnerGuardCorrectsThenFallsBack(t *testing.T) {
	// The model promises; the corrective round still promises; the reply is
	// the engine's own words.
	api := newFakeAPI(t,
		toolUseResponse(toolUse("toolu_1", toolRampOutlookAt, `{"access_id":"NS-110","time_iso":"2026-06-12T14:00:00-04:00"}`)),
		textResponse("Flagler will close at 2:17pm on Friday."),
		textResponse("Flagler will definitely close at 2:17pm."),
	)
	resp, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "Flagler Friday 2pm?"}}})
	require.NoError(t, err)
	assert.Equal(t, "Flagler Ave, Friday ~2pm: Could close around the 2:30pm high tide. Closure possible around 2:30pm · often back open by ~4:30pm.", resp.Reply)
	assert.Equal(t, 3, resp.Usage.Calls)
	corrective := lastUserContent(t, api.requests[2])
	assert.Contains(t, corrective[0]["text"], "Rewrite your last answer")
}

func TestRunnerGuardAcceptsCorrection(t *testing.T) {
	api := newFakeAPI(t,
		toolUseResponse(toolUse("toolu_1", toolRampOutlookAt, `{"access_id":"NS-110","time_iso":"2026-06-12T14:00:00-04:00"}`)),
		textResponse("Flagler will close at 2:17pm on Friday."),
		textResponse("Flagler Ave could close around the 2:30pm high tide on Friday."),
	)
	resp, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "Flagler Friday 2pm?"}}})
	require.NoError(t, err)
	assert.Equal(t, "Flagler Ave could close around the 2:30pm high tide on Friday.", resp.Reply)
}

func TestRunnerRefusal(t *testing.T) {
	api := newFakeAPI(t, `{"id":"msg_r","type":"message","role":"assistant","model":"claude-test","content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":"other","explanation":""},"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}`)
	resp, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "..."}}})
	require.NoError(t, err)
	assert.Equal(t, refusedReply, resp.Reply)
	assert.Empty(t, resp.Sources)
}

func TestRunnerIterationCap(t *testing.T) {
	var script []string
	for i := 0; i < maxIterations+2; i++ {
		script = append(script, toolUseResponse(toolUse(fmt.Sprintf("toolu_%d", i), toolWeekend, `{}`)))
	}
	api := newFakeAPI(t, script...)
	resp, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "loop"}}})
	require.NoError(t, err)
	assert.Equal(t, stalledReply, resp.Reply)
	assert.Len(t, api.requests, maxIterations)
}

func TestRunnerAPIErrorSurfaces(t *testing.T) {
	api := newFakeAPI(t) // no script: every call 500s
	_, err := api.runner(defaultFake()).Run(context.Background(), Request{Messages: []Turn{{Role: RoleUser, Text: "hi"}}})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "status 500")
}
