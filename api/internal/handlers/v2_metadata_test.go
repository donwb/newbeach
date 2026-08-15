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

	"github.com/donwb/beach/api/internal/models"
)

func strPtr(s string) *string     { return &s }
func floatPtr(f float64) *float64 { return &f }
func intPtr(i int) *int           { return &i }

// TestRampStatusWithSinceMetadataJSON pins the wire contract of the v2 ramps
// response: with no metadata the JSON key set is exactly what it was before
// ramp_metadata existed (strictly additive change), and with metadata present
// the new nullable fields appear.
func TestRampStatusWithSinceMetadataJSON(t *testing.T) {
	base := models.RampStatusWithSince{
		RampStatus: models.RampStatus{
			ID:             1,
			RampName:       "BEACHWAY AV",
			AccessStatus:   "OPEN",
			StatusCategory: "open",
			ObjectID:       42,
			City:           "New Smyrna Beach",
			AccessID:       "NSB-001",
			Location:       "100 N Atlantic Ave",
			UpdatedAt:      time.Date(2026, 8, 15, 12, 0, 0, 0, time.UTC),
		},
	}

	t.Run("nil metadata omits every new field", func(t *testing.T) {
		raw, err := json.Marshal(base)
		require.NoError(t, err)

		var m map[string]interface{}
		require.NoError(t, json.Unmarshal(raw, &m))

		// Exactly the pre-metadata key set: existing consumers (web, TRMNL,
		// tvOS, iOS) must see byte-identical JSON for ramps without metadata.
		wantKeys := []string{
			"id", "ramp_name", "access_status", "status_category",
			"object_id", "city", "access_id", "location", "last_updated",
		}
		assert.Len(t, m, len(wantKeys))
		for _, k := range wantKeys {
			assert.Contains(t, m, k)
		}
		for _, k := range []string{"short_name", "address", "driving_hours", "closure_height_ft", "sort_order", "status_since"} {
			assert.NotContains(t, m, k)
		}
	})

	t.Run("populated metadata serializes the new fields", func(t *testing.T) {
		r := base
		since := time.Date(2026, 8, 15, 6, 0, 0, 0, time.UTC)
		r.StatusSince = &since
		r.ShortName = strPtr("Beachway")
		r.Address = strPtr("100 N Atlantic Ave, New Smyrna Beach, FL")
		r.DrivingHours = strPtr("Sunrise to sunset")
		r.ClosureHeightFt = floatPtr(2.5)
		r.SortOrder = intPtr(1)

		raw, err := json.Marshal(r)
		require.NoError(t, err)

		var m map[string]interface{}
		require.NoError(t, json.Unmarshal(raw, &m))

		assert.Equal(t, "Beachway", m["short_name"])
		assert.Equal(t, "100 N Atlantic Ave, New Smyrna Beach, FL", m["address"])
		assert.Equal(t, "Sunrise to sunset", m["driving_hours"])
		assert.Equal(t, 2.5, m["closure_height_ft"])
		assert.Equal(t, float64(1), m["sort_order"])
	})
}

// TestRampMetadataBodyDecode pins the admin upsert body semantics: fields may
// be absent or explicitly null and both decode to nil pointers (which the
// full-replace upsert stores as SQL NULL, clearing the column).
func TestRampMetadataBodyDecode(t *testing.T) {
	tests := []struct {
		name string
		body string
		want models.RampMetadata
	}{
		{
			name: "full body",
			body: `{"short_name":"Beachway","address":"100 N Atlantic","driving_hours":"7am-7pm","closure_height_ft":2.5,"sort_order":1}`,
			want: models.RampMetadata{
				ShortName:       strPtr("Beachway"),
				Address:         strPtr("100 N Atlantic"),
				DrivingHours:    strPtr("7am-7pm"),
				ClosureHeightFt: floatPtr(2.5),
				SortOrder:       intPtr(1),
			},
		},
		{
			name: "explicit nulls clear fields",
			body: `{"short_name":null,"address":null,"driving_hours":null,"closure_height_ft":null,"sort_order":null}`,
			want: models.RampMetadata{},
		},
		{
			name: "absent fields decode to nil like nulls",
			body: `{"sort_order":3}`,
			want: models.RampMetadata{SortOrder: intPtr(3)},
		},
		{
			name: "empty body clears everything",
			body: `{}`,
			want: models.RampMetadata{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var got models.RampMetadata
			require.NoError(t, json.Unmarshal([]byte(tt.body), &got))
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestParseActivitySince(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		want    *time.Time
		wantErr bool
	}{
		{"empty means no filter", "", nil, false},
		{"valid RFC3339 UTC", "2026-08-15T00:00:00Z",
			timePtr(time.Date(2026, 8, 15, 0, 0, 0, 0, time.UTC)), false},
		{"valid RFC3339 with offset", "2026-08-15T06:30:00-04:00",
			timePtr(time.Date(2026, 8, 15, 6, 30, 0, 0, time.FixedZone("", -4*3600))), false},
		{"date only errors", "2026-08-15", nil, true},
		{"unix seconds errors", "1755216000", nil, true},
		{"garbage errors", "yesterday", nil, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseActivitySince(tt.raw)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			if tt.want == nil {
				assert.Nil(t, got)
				return
			}
			require.NotNil(t, got)
			assert.True(t, tt.want.Equal(*got), "want %v, got %v", tt.want, got)
		})
	}
}

func timePtr(t time.Time) *time.Time { return &t }

// TestActivityInvalidSinceRejected exercises the handler path: an invalid
// since parameter must 400 before any database access (pool is nil, so
// reaching the query would panic and fail the test loudly).
func TestActivityInvalidSinceRejected(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v2/activity?since=not-a-time", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)

	require.NoError(t, HandleV2RecentActivity(nil)(c))
	assert.Equal(t, http.StatusBadRequest, rec.Code)
	assert.Contains(t, rec.Body.String(), "since")
}

// TestAdminRampMetadataAuth exercises the admin route through the same
// apiKeyAuth middleware production uses. The pool is nil, so any request
// that wrongly got past auth and body validation would panic — passing
// tests prove rejection happens before the database is touched.
func TestAdminRampMetadataAuth(t *testing.T) {
	newServer := func() *echo.Echo {
		e := echo.New()
		admin := e.Group("/api/v2/admin")
		admin.Use(apiKeyAuth())
		admin.PUT("/ramps/:id/metadata", HandleAdminUpsertRampMetadata(nil))
		return e
	}

	do := func(e *echo.Echo, key, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPut, "/api/v2/admin/ramps/NSB-001/metadata", strings.NewReader(body))
		req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
		if key != "" {
			req.Header.Set("X-Api-Key", key)
		}
		rec := httptest.NewRecorder()
		e.ServeHTTP(rec, req)
		return rec
	}

	t.Run("missing key is rejected", func(t *testing.T) {
		t.Setenv("ADMIN_API_KEY", "sekrit")
		rec := do(newServer(), "", `{"sort_order":1}`)
		assert.Equal(t, http.StatusUnauthorized, rec.Code)
	})

	t.Run("wrong key is rejected", func(t *testing.T) {
		t.Setenv("ADMIN_API_KEY", "sekrit")
		rec := do(newServer(), "wrong", `{"sort_order":1}`)
		assert.Equal(t, http.StatusUnauthorized, rec.Code)
	})

	t.Run("unconfigured admin key returns 503", func(t *testing.T) {
		t.Setenv("ADMIN_API_KEY", "")
		rec := do(newServer(), "anything", `{"sort_order":1}`)
		assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	})

	t.Run("valid key with malformed body is a 400 from the handler", func(t *testing.T) {
		t.Setenv("ADMIN_API_KEY", "sekrit")
		rec := do(newServer(), "sekrit", `{not json`)
		assert.Equal(t, http.StatusBadRequest, rec.Code)
	})
}
