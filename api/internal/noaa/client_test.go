package noaa

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func decodePredictionResponse(t *testing.T, raw string) noaaPredictionResponse {
	t.Helper()
	var resp noaaPredictionResponse
	require.NoError(t, json.Unmarshal([]byte(raw), &resp))
	return resp
}

func TestPredictionsFromResponse(t *testing.T) {
	tests := []struct {
		name      string
		raw       string
		wantCount int
	}{
		{
			name: "heights parsed and carried",
			raw: `{"predictions": [
				{"t": "2026-08-14 04:40", "v": "-0.123", "type": "L"},
				{"t": "2026-08-14 10:44", "v": "2.845", "type": "H"}
			]}`,
			wantCount: 2,
		},
		{
			name:      "missing height yields entry with nil height",
			raw:       `{"predictions": [{"t": "2026-08-14 04:40", "v": "", "type": "L"}]}`,
			wantCount: 1,
		},
		{
			name: "unparseable time skipped",
			raw: `{"predictions": [
				{"t": "not-a-time", "v": "1.0", "type": "H"},
				{"t": "2026-08-14 16:57", "v": "-0.1", "type": "L"}
			]}`,
			wantCount: 1,
		},
		{
			name:      "empty response",
			raw:       `{"predictions": []}`,
			wantCount: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			preds := predictionsFromResponse(decodePredictionResponse(t, tt.raw))
			assert.Len(t, preds, tt.wantCount)
		})
	}
}

func TestPredictionsFromResponseHeightValues(t *testing.T) {
	resp := decodePredictionResponse(t, `{"predictions": [
		{"t": "2026-08-14 04:40", "v": " -0.123 ", "type": "L"},
		{"t": "2026-08-14 10:44", "v": "bogus", "type": "H"}
	]}`)

	preds := predictionsFromResponse(resp)
	require.Len(t, preds, 2)

	require.NotNil(t, preds[0].Height)
	assert.InDelta(t, -0.123, *preds[0].Height, 1e-9)
	assert.Equal(t, "L", preds[0].Type)

	assert.Nil(t, preds[1].Height, "unparseable height should be nil, not dropped")
	assert.Equal(t, "H", preds[1].Type)
}

func TestTidePredictionJSONShape(t *testing.T) {
	// The height field is additive and must vanish when absent so existing
	// consumers of /api/v2/tides see an unchanged shape.
	resp := decodePredictionResponse(t, `{"predictions": [
		{"t": "2026-08-14 04:40", "v": "-0.1", "type": "L"},
		{"t": "2026-08-14 10:44", "v": "", "type": "H"}
	]}`)
	preds := predictionsFromResponse(resp)
	require.Len(t, preds, 2)

	withHeight, err := json.Marshal(preds[0])
	require.NoError(t, err)
	assert.Contains(t, string(withHeight), `"height":-0.1`)

	withoutHeight, err := json.Marshal(preds[1])
	require.NoError(t, err)
	assert.NotContains(t, string(withoutHeight), "height")
}
