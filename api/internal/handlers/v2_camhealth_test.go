package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHookKeyAuth pins the hook endpoint's auth behavior: unconfigured key
// means 503 (never open), wrong key means 401, and only a matching
// X-Hook-Key reaches the handler.
func TestHookKeyAuth(t *testing.T) {
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
			t.Setenv("CAM_HOOK_KEY", tt.envKey)

			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v2/hooks/camera-health", strings.NewReader(`{}`))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			if tt.headerKey != "" {
				req.Header.Set("X-Hook-Key", tt.headerKey)
			}
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			err := hookKeyAuth()(okHandler)(c)
			require.NoError(t, err)
			assert.Equal(t, tt.wantStatus, rec.Code)
		})
	}
}

// TestCameraHealthHookValidation pins the request validation that runs before
// any database access: malformed and incomplete bodies are rejected with 400.
func TestCameraHealthHookValidation(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"malformed json", `{not json`},
		{"missing id", `{"online": true}`},
		{"missing online", `{"id": "nsb"}`},
		{"empty body", `{}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v2/hooks/camera-health", strings.NewReader(tt.body))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			// pool is never reached: validation rejects first.
			err := HandleCameraHealthHook(nil)(c)
			require.NoError(t, err)
			assert.Equal(t, http.StatusBadRequest, rec.Code, "body: %s", tt.body)
		})
	}
}

// TestCameraDTOWireContract pins the roster JSON shape: without health the
// key set is exactly the pre-health contract (strictly additive change), and
// with health the two new fields appear.
func TestCameraDTOWireContract(t *testing.T) {
	base := cameraDTO{
		ID:        "nsb",
		Name:      "New Smyrna Beach",
		Location:  "New Smyrna Beach",
		StreamURL: "https://cams.donwb.com/nsb/index.m3u8",
	}

	t.Run("no health omits online fields", func(t *testing.T) {
		raw, err := json.Marshal(base)
		require.NoError(t, err)

		var m map[string]interface{}
		require.NoError(t, json.Unmarshal(raw, &m))

		wantKeys := []string{"id", "name", "location", "stream_url"}
		assert.Len(t, m, len(wantKeys))
		for _, k := range wantKeys {
			assert.Contains(t, m, k)
		}
		assert.NotContains(t, m, "online")
		assert.NotContains(t, m, "status_changed_at")
	})

	t.Run("health adds online and status_changed_at", func(t *testing.T) {
		online := false
		changed := time.Date(2026, 8, 16, 15, 26, 0, 0, time.UTC)
		withHealth := base
		withHealth.Online = &online
		withHealth.StatusChangedAt = &changed

		raw, err := json.Marshal(withHealth)
		require.NoError(t, err)

		var m map[string]interface{}
		require.NoError(t, json.Unmarshal(raw, &m))

		assert.Equal(t, false, m["online"])
		assert.Equal(t, "2026-08-16T15:26:00Z", m["status_changed_at"])
	})
}
