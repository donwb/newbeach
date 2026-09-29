// Package jev is a small client for TypeSafe's System One endpoint
// (https://docs.typesafe.ai/api). A System One model — Jev — takes a state
// and a map of typed questions and returns typed answers with calibrated
// probabilities: a Choice from a fixed set, a Noul (probability a statement
// is true), or a Score along ordered levels. It never generates text.
//
// The client is deliberately thin: one POST, typed question builders, typed
// answers, a bounded timeout, and one retry on 429/529. TypeSafe publishes
// Python and JavaScript SDKs but no Go one, and the HTTP contract is small
// enough that a wrapper is the whole SDK.
package jev

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

const (
	// DefaultBaseURL is the public API host.
	DefaultBaseURL = "https://api.typesafe.ai"
	// DefaultModel is the alias TypeSafe recommends; it moves on releases.
	// Pin a versioned id (jev-1.13.0) once thresholds are tuned against it.
	DefaultModel = "jev-latest"
	// DefaultTimeout bounds one call end to end. Most answers come back in
	// ~100 ms; the quick path cannot wait much longer than a second before
	// a model round-trip would have been the better bet anyway.
	DefaultTimeout = 2 * time.Second
)

// Client calls the System One endpoint. A nil *Client is safe to pass
// around and reports Enabled() == false, so callers can wire the feature
// unconditionally and switch it on with a key.
type Client struct {
	apiKey  string
	baseURL string
	model   string
	http    *http.Client
}

// Option configures a Client.
type Option func(*Client)

// WithBaseURL points the client at another host (tests, a proxy).
func WithBaseURL(u string) Option { return func(c *Client) { c.baseURL = u } }

// WithModel selects the model or alias sent in every request.
func WithModel(m string) Option {
	return func(c *Client) {
		if m != "" {
			c.model = m
		}
	}
}

// WithTimeout bounds each call including the one retry.
func WithTimeout(d time.Duration) Option { return func(c *Client) { c.http.Timeout = d } }

// WithHTTPClient replaces the transport (tests).
func WithHTTPClient(h *http.Client) Option { return func(c *Client) { c.http = h } }

// New builds a Client. An empty apiKey returns nil — the feature is off.
func New(apiKey string, opts ...Option) *Client {
	if apiKey == "" {
		return nil
	}
	c := &Client{
		apiKey:  apiKey,
		baseURL: DefaultBaseURL,
		model:   DefaultModel,
		http:    &http.Client{Timeout: DefaultTimeout},
	}
	for _, o := range opts {
		o(c)
	}
	return c
}

// Enabled reports whether calls will be made.
func (c *Client) Enabled() bool { return c != nil }

// Model is the model or alias the client sends.
func (c *Client) Model() string {
	if c == nil {
		return ""
	}
	return c.model
}

// Question is one typed question. Build them with Choice, Noul, and Score.
type Question struct {
	Type         string `json:"type"`
	Instructions any    `json:"instructions"`
	Criteria     any    `json:"criteria,omitempty"`
}

// Choice asks the model to pick one option. criteria maps option → a
// description that separates it from the others (nil is allowed). Both the
// option name and its description are shown to the model.
func Choice(instructions any, criteria map[string]any) Question {
	return Question{Type: "choice", Instructions: instructions, Criteria: criteria}
}

// NoulCriteria describes what a yes and a no mean when the boundary needs
// spelling out.
type NoulCriteria struct {
	True  any `json:"true,omitempty"`
	False any `json:"false,omitempty"`
}

// Noul asks a yes/no question; the answer is the probability of yes.
// Phrase it so that a high value means yes. criteria may be nil.
func Noul(instructions any, criteria *NoulCriteria) Question {
	q := Question{Type: "noul", Instructions: instructions}
	if criteria != nil {
		q.Criteria = criteria
	}
	return q
}

// Score rates the state along ordered levels (2–10). The answer is a
// probability-weighted position, and is not to be read as a number to do
// arithmetic on.
func Score(instructions any, levels []any) Question {
	return Question{Type: "score", Instructions: instructions, Criteria: levels}
}

// Answer is one typed answer. Only the fields for its Type are set.
type Answer struct {
	Type          string             `json:"type"`
	Choice        string             `json:"choice,omitempty"`
	Noul          float64            `json:"noul,omitempty"`
	Score         float64            `json:"score,omitempty"`
	Probabilities map[string]float64 `json:"probabilities,omitempty"`
	Confidence    float64            `json:"confidence,omitempty"`
	Legend        map[string]string  `json:"legend,omitempty"`
}

// Usage is the request's token spend. Output tokens are free but reported.
type Usage struct {
	InputTokens  int64 `json:"input_tokens"`
	OutputTokens int64 `json:"output_tokens"`
}

// Result is one evaluation: answers keyed by the question ids sent.
type Result struct {
	Model   string            `json:"model"`
	Answers map[string]Answer `json:"answers"`
	Usage   Usage             `json:"usage"`
	Latency time.Duration     `json:"-"`
	Retried bool              `json:"-"`
}

// Choice returns the chosen option and confidence for a Choice question,
// or ("", 0) when the answer is missing or of another type.
func (r *Result) Choice(id string) (string, float64) {
	if r == nil {
		return "", 0
	}
	a, ok := r.Answers[id]
	if !ok || a.Type != "choice" {
		return "", 0
	}
	return a.Choice, a.Confidence
}

// Noul returns the probability of yes for a Noul question, or (0, false)
// when the answer is missing or of another type.
func (r *Result) Noul(id string) (float64, bool) {
	if r == nil {
		return 0, false
	}
	a, ok := r.Answers[id]
	if !ok || a.Type != "noul" {
		return 0, false
	}
	return a.Noul, true
}

// APIError is a non-2xx response.
type APIError struct {
	Status int
	Body   string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("jev: status %d: %s", e.Status, truncate(e.Body, 200))
}

// ErrDisabled is returned by Ask on a nil client.
var ErrDisabled = errors.New("jev: client disabled (no API key)")

type request struct {
	State     any                 `json:"state"`
	Model     string              `json:"model"`
	Questions map[string]Question `json:"questions"`
}

// Ask evaluates state against questions in one request. Every question
// sees the same state and is answered independently and in parallel, so
// ask everything the caller might need at once.
func (c *Client) Ask(ctx context.Context, state any, questions map[string]Question) (*Result, error) {
	if c == nil {
		return nil, ErrDisabled
	}
	if len(questions) == 0 {
		return nil, errors.New("jev: no questions")
	}
	body, err := json.Marshal(request{State: state, Model: c.model, Questions: questions})
	if err != nil {
		return nil, fmt.Errorf("jev: encoding request: %w", err)
	}

	start := time.Now()
	res, retried, err := c.post(ctx, body)
	if err != nil {
		return nil, err
	}
	res.Latency = time.Since(start)
	res.Retried = retried
	return res, nil
}

// post sends the body, retrying once on 429/529 after a short, bounded
// pause (retry-after when the server names one, capped so the caller's
// latency budget still holds).
func (c *Client) post(ctx context.Context, body []byte) (*Result, bool, error) {
	res, status, retryAfter, err := c.once(ctx, body)
	if err == nil {
		return res, false, nil
	}
	if status != http.StatusTooManyRequests && status != 529 {
		return nil, false, err
	}
	wait := 300 * time.Millisecond
	if retryAfter > 0 && retryAfter < wait {
		wait = retryAfter
	}
	select {
	case <-ctx.Done():
		return nil, false, ctx.Err()
	case <-time.After(wait):
	}
	res, _, _, err = c.once(ctx, body)
	return res, true, err
}

func (c *Client) once(ctx context.Context, body []byte) (*Result, int, time.Duration, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/systemone", bytes.NewReader(body))
	if err != nil {
		return nil, 0, 0, fmt.Errorf("jev: building request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, 0, 0, fmt.Errorf("jev: %w", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, resp.StatusCode, 0, fmt.Errorf("jev: reading response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		var ra time.Duration
		if s := resp.Header.Get("Retry-After"); s != "" {
			if secs, err := strconv.Atoi(s); err == nil {
				ra = time.Duration(secs) * time.Second
			}
		}
		return nil, resp.StatusCode, ra, &APIError{Status: resp.StatusCode, Body: string(raw)}
	}
	var res Result
	if err := json.Unmarshal(raw, &res); err != nil {
		return nil, resp.StatusCode, 0, fmt.Errorf("jev: decoding response: %w", err)
	}
	return &res, resp.StatusCode, 0, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
