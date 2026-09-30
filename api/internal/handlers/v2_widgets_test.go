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

// The registration handler validates before touching the database, so a
// nil pool is safe for the rejection cases.
func TestRegisterWidgetPushTokenValidation(t *testing.T) {
	tests := []struct {
		name string
		body string
		want int
	}{
		{"not json", `{nope`, http.StatusBadRequest},
		{"missing token", `{}`, http.StatusBadRequest},
		{"not hex", `{"token":"zzzz-not-hex"}`, http.StatusBadRequest},
		{"too short", `{"token":"abc"}`, http.StatusBadRequest},
		{"bad environment", `{"token":"0123456789abcdef0123456789abcdef","environment":"staging"}`, http.StatusBadRequest},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v2/widgets/push-token", strings.NewReader(tt.body))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)
			err := HandleV2RegisterWidgetPushToken(nil, "com.donwb.BeachRampTV")(c)
			require.NoError(t, err)
			assert.Equal(t, tt.want, rec.Code)
			assert.Contains(t, rec.Body.String(), `"error"`)
		})
	}
}

func TestAdminWidgetPushWithoutNotifier(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest(http.MethodPost, "/api/v2/admin/widgets/push", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	require.NoError(t, HandleAdminWidgetPush(nil, nil)(c))
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
}
