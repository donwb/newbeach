package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestChatKeyAuth pins the chat route's gate: an unconfigured key is 503
// (never open), a wrong or missing key is 401, and only a matching
// X-Chat-Key reaches the handler.
func TestChatKeyAuth(t *testing.T) {
	okHandler := func(c echo.Context) error {
		return c.JSON(http.StatusOK, map[string]string{"status": "reached"})
	}

	tests := []struct {
		name       string
		envKey     string
		headerKey  string
		wantStatus int
	}{
		{"no key configured", "", "anything", http.StatusServiceUnavailable},
		{"wrong key", "secret", "not-secret", http.StatusUnauthorized},
		{"missing header", "secret", "", http.StatusUnauthorized},
		{"correct key", "secret", "secret", http.StatusOK},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("CHAT_API_KEY", tt.envKey)

			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v2/chat", strings.NewReader(`{}`))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			if tt.headerKey != "" {
				req.Header.Set("X-Chat-Key", tt.headerKey)
			}
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			err := chatKeyAuth()(okHandler)(c)
			require.NoError(t, err)
			assert.Equal(t, tt.wantStatus, rec.Code)
		})
	}
}

// TestChatValidation pins the body checks that run before the model is
// ever called: a nil runner never gets reached by a bad body.
func TestChatValidation(t *testing.T) {
	tests := []struct {
		name string
		body string
		want int
	}{
		{"not json", `{nope`, http.StatusBadRequest},
		{"no messages", `{}`, http.StatusBadRequest},
		{"last turn not user", `{"messages":[{"role":"assistant","text":"hi"}]}`, http.StatusBadRequest},
		{"bad role", `{"messages":[{"role":"system","text":"hi"}]}`, http.StatusBadRequest},
		{"valid body, no runner", `{"messages":[{"role":"user","text":"Flagler at 2pm?"}]}`, http.StatusServiceUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v2/chat", strings.NewReader(tt.body))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			err := HandleV2Chat(nil)(c)
			require.NoError(t, err)
			assert.Equal(t, tt.want, rec.Code)
			assert.Contains(t, rec.Body.String(), `"error"`)
		})
	}
}
