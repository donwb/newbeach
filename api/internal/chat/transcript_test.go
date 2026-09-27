package chat

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRequestValidate(t *testing.T) {
	ok := Request{Messages: []Turn{{Role: RoleUser, Text: "hi"}}}
	assert.NoError(t, ok.Validate())

	ok = Request{Messages: []Turn{{Role: RoleUser, Text: "a"}, {Role: RoleAssistant, Text: "b"}, {Role: RoleUser, Text: "c"}}}
	assert.NoError(t, ok.Validate())

	assert.Error(t, Request{}.Validate(), "empty")
	assert.Error(t, Request{Messages: []Turn{{Role: RoleAssistant, Text: "x"}}}.Validate(), "last turn must be the user")
	assert.Error(t, Request{Messages: []Turn{{Role: RoleUser, Text: "a"}, {Role: RoleUser, Text: "b"}}}.Validate(), "roles must alternate")
	assert.Error(t, Request{Messages: []Turn{{Role: "system", Text: "a"}}}.Validate(), "unknown role")
	assert.Error(t, Request{Messages: []Turn{{Role: RoleUser, Text: ""}}}.Validate(), "empty text")
	assert.Error(t, Request{Messages: []Turn{{Role: RoleUser, Text: strings.Repeat("x", maxTurnRune+1)}}}.Validate(), "too long")

	many := Request{}
	for i := 0; i < maxTurns+1; i++ {
		role := RoleUser
		if i%2 == 1 {
			role = RoleAssistant
		}
		many.Messages = append(many.Messages, Turn{Role: role, Text: "t"})
	}
	assert.Error(t, many.Validate(), "too many turns")
}
