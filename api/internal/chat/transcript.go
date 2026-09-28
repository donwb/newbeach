package chat

import (
	"errors"
	"fmt"
	"time"
	"unicode/utf8"
)

// Wire types for POST /api/v2/chat. The server is stateless: the client
// sends the whole transcript every turn and gets back the next assistant
// turn plus the engine facts it rested on.

const (
	RoleUser      = "user"
	RoleAssistant = "assistant"

	maxTurns    = 20
	maxTurnRune = 1000
)

// Turn is one prior message in the conversation.
type Turn struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

// Context is optional hints from the client's screen — the city the board
// is showing and, when a ramp is open, that ramp. A question that names
// neither is about these.
type Context struct {
	AccessID string `json:"access_id,omitempty"`
	City     string `json:"city,omitempty"` // GIS key or any alias; resolved server-side
}

// Request is the chat request body.
type Request struct {
	Messages []Turn   `json:"messages"`
	Context  *Context `json:"context,omitempty"`
}

// Validate rejects transcripts the loop should not attempt.
func (r Request) Validate() error {
	if len(r.Messages) == 0 {
		return errors.New("messages is required")
	}
	if len(r.Messages) > maxTurns {
		return fmt.Errorf("too many messages (max %d)", maxTurns)
	}
	for i, m := range r.Messages {
		if m.Role != RoleUser && m.Role != RoleAssistant {
			return fmt.Errorf("messages[%d].role must be user or assistant", i)
		}
		if m.Text == "" {
			return fmt.Errorf("messages[%d].text is empty", i)
		}
		if utf8.RuneCountInString(m.Text) > maxTurnRune {
			return fmt.Errorf("messages[%d].text is too long (max %d characters)", i, maxTurnRune)
		}
		if i > 0 && r.Messages[i-1].Role == m.Role {
			return fmt.Errorf("messages[%d] repeats the %s role; turns must alternate", i, m.Role)
		}
	}
	if r.Messages[len(r.Messages)-1].Role != RoleUser {
		return errors.New("the last message must be from the user")
	}
	return nil
}

// SourceRamp is one ramp row inside a city source.
type SourceRamp struct {
	AccessID string `json:"access_id"`
	Name     string `json:"name"`
	Status   string `json:"status,omitempty"` // live read only
	Risk     string `json:"risk,omitempty"`
	Headline string `json:"headline,omitempty"`
}

// Source is one engine fact the reply rested on, taken from the tool
// results themselves — never from the model's prose — so a client can show
// the fact card the board would show, whatever the words around it say.
type Source struct {
	Kind string `json:"kind"` // ramp_outlook | city_now | city_outlook | weekend_day

	// ramp_outlook
	AccessID    string     `json:"access_id,omitempty"`
	Name        string     `json:"name,omitempty"`
	City        string     `json:"city,omitempty"`
	At          *time.Time `json:"at,omitempty"`
	AtLabel     string     `json:"at_label,omitempty"`
	Risk        string     `json:"risk,omitempty"`
	Reason      string     `json:"reason,omitempty"`
	Headline    string     `json:"headline,omitempty"`
	Detail      string     `json:"detail,omitempty"`
	WindowLabel string     `json:"window_label,omitempty"`
	ReopenLabel string     `json:"reopen_label,omitempty"`
	Relation    string     `json:"target_vs_hours,omitempty"`

	// city_now / city_outlook (City carries the display name; Headline /
	// Detail the verdict; At/AtLabel/Relation for the future read)
	OpenCount *int         `json:"open_count,omitempty"`
	RampCount *int         `json:"ramp_count,omitempty"`
	Ramps     []SourceRamp `json:"ramps,omitempty"`

	// weekend_day
	Date             string `json:"date,omitempty"`
	Weekday          string `json:"weekday,omitempty"`
	Verdict          string `json:"verdict,omitempty"`
	ClosureRiskLabel string `json:"closure_risk_label,omitempty"`
	BestWindowLabel  string `json:"best_window_label,omitempty"`
}

// Usage is the token spend across every model call the reply took.
type Usage struct {
	InputTokens  int64 `json:"input_tokens"`
	OutputTokens int64 `json:"output_tokens"`
	Calls        int   `json:"calls"`
}

// Response is the chat response body.
type Response struct {
	Reply       string    `json:"reply"`
	Sources     []Source  `json:"sources"`
	Model       string    `json:"model"`
	Usage       Usage     `json:"usage"`
	GeneratedAt time.Time `json:"generated_at"`
}
