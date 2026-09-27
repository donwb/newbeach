package chat

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func possibleSource() []Source {
	return []Source{{
		Kind: "ramp_outlook", Name: "Flagler Ave", AtLabel: "Friday ~2pm", Risk: "possible",
		Headline:    "Could close around the 2:30pm high tide",
		Detail:      "Closure possible around 2:30pm · often back open by ~4:30pm",
		WindowLabel: "11:30am–5pm",
	}}
}

func TestCheckCopy(t *testing.T) {
	src := possibleSource()

	assert.Empty(t, checkCopy("Flagler Ave could close around the 2:30pm high tide on Friday. Closure possible around 2:30pm, often back open by ~4:30pm.", src))
	assert.Empty(t, checkCopy("Probably fine at 2pm, but it could close around the 2:30pm high tide.", src), "half hours are always allowed")

	assert.NotEmpty(t, checkCopy("Flagler will close at 2:30pm.", src), "will close is a promise")
	assert.NotEmpty(t, checkCopy("Flagler is likely to close for the tide.", src), "likely without a likely source")
	assert.NotEmpty(t, checkCopy("It closes around 2:17pm.", src), "a minute-precise time the engine never said")

	likely := possibleSource()
	likely[0].Risk = "likely"
	assert.Empty(t, checkCopy("Flagler is likely to close around the 2:30pm high tide.", likely), "likely is fine when the engine said likely")

	// The word "will" about something other than closing is fine.
	assert.Empty(t, checkCopy("You will have the whole afternoon; no tide trouble expected.", src))
}

func TestTemplatedReply(t *testing.T) {
	got := templatedReply(possibleSource())
	assert.Equal(t, "Flagler Ave, Friday ~2pm: Could close around the 2:30pm high tide. Closure possible around 2:30pm · often back open by ~4:30pm.", got)

	got = templatedReply([]Source{{Kind: "weekend_day", Weekday: "Saturday", Headline: "Clear all day", Detail: "No tide trouble expected"}})
	assert.Equal(t, "Saturday: Clear all day. No tide trouble expected.", got)

	assert.NotEmpty(t, templatedReply(nil))
}
