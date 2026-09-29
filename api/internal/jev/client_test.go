package jev

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNilClientIsDisabled(t *testing.T) {
	var c *Client
	assert.False(t, c.Enabled())
	assert.Equal(t, "", c.Model())
	_, err := c.Ask(context.Background(), "x", map[string]Question{"q": Noul("is it?", nil)})
	assert.ErrorIs(t, err, ErrDisabled)
	assert.Nil(t, New(""))
}

func TestAskRoundTrip(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/v1/systemone", r.URL.Path)
		assert.Equal(t, "Bearer k", r.Header.Get("Authorization"))
		body, _ := io.ReadAll(r.Body)
		require.NoError(t, json.Unmarshal(body, &got))
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"jev-1.13.0","answers":{
			"dept":{"type":"choice","choice":"billing","probabilities":{"billing":0.9,"tech":0.1},"confidence":0.8},
			"urgent":{"type":"noul","noul":0.95},
			"mood":{"type":"score","score":1.4,"legend":{"0":"calm","1":"cross","2":"angry"},"probabilities":{"0":0.1,"1":0.4,"2":0.5},"confidence":0.3}
		},"usage":{"input_tokens":300,"output_tokens":20}}`))
	}))
	defer srv.Close()

	c := New("k", WithBaseURL(srv.URL), WithModel("jev-test"))
	res, err := c.Ask(context.Background(), map[string]any{"message": "charged twice"}, map[string]Question{
		"dept":   Choice("Which team?", map[string]any{"billing": "money", "tech": "bugs"}),
		"urgent": Noul("Is it urgent?", &NoulCriteria{True: "time-sensitive", False: "no rush"}),
		"mood":   Score("How cross?", []any{"calm", "cross", "angry"}),
	})
	require.NoError(t, err)

	// The wire shape matches the API reference.
	assert.Equal(t, "jev-test", got["model"])
	assert.Equal(t, "charged twice", got["state"].(map[string]any)["message"])
	qs := got["questions"].(map[string]any)
	assert.Equal(t, "choice", qs["dept"].(map[string]any)["type"])
	assert.Equal(t, "money", qs["dept"].(map[string]any)["criteria"].(map[string]any)["billing"])
	assert.Equal(t, "time-sensitive", qs["urgent"].(map[string]any)["criteria"].(map[string]any)["true"])
	assert.Len(t, qs["mood"].(map[string]any)["criteria"].([]any), 3)

	choice, conf := res.Choice("dept")
	assert.Equal(t, "billing", choice)
	assert.InDelta(t, 0.8, conf, 1e-9)
	p, ok := res.Noul("urgent")
	assert.True(t, ok)
	assert.InDelta(t, 0.95, p, 1e-9)
	_, ok = res.Noul("dept")
	assert.False(t, ok, "type mismatch reads as missing")
	_, conf = res.Choice("missing")
	assert.Zero(t, conf)
	assert.Equal(t, int64(300), res.Usage.InputTokens)
	assert.Equal(t, "jev-1.13.0", res.Model)
	assert.False(t, res.Retried)
	assert.Greater(t, res.Latency, time.Duration(0))
}

func TestAskRetriesOnceOnRateLimit(t *testing.T) {
	var calls int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&calls, 1) == 1 {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"slow down"}`))
			return
		}
		_, _ = w.Write([]byte(`{"model":"jev-1.13.0","answers":{"q":{"type":"noul","noul":0.5}},"usage":{"input_tokens":1,"output_tokens":1}}`))
	}))
	defer srv.Close()

	c := New("k", WithBaseURL(srv.URL))
	res, err := c.Ask(context.Background(), "s", map[string]Question{"q": Noul("?", nil)})
	require.NoError(t, err)
	assert.True(t, res.Retried)
	assert.Equal(t, int32(2), atomic.LoadInt32(&calls))
}

func TestAskSurfacesAPIErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = w.Write([]byte(`{"detail":"criteria required"}`))
	}))
	defer srv.Close()

	c := New("k", WithBaseURL(srv.URL))
	_, err := c.Ask(context.Background(), "s", map[string]Question{"q": Choice("?", nil)})
	var apiErr *APIError
	require.ErrorAs(t, err, &apiErr)
	assert.Equal(t, 422, apiErr.Status)
	assert.Contains(t, err.Error(), "criteria required")
}

func TestAskHonorsTimeout(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer srv.Close()

	c := New("k", WithBaseURL(srv.URL), WithTimeout(30*time.Millisecond))
	_, err := c.Ask(context.Background(), "s", map[string]Question{"q": Noul("?", nil)})
	require.Error(t, err)
}
