package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newStaticTestServer mirrors the static-serving setup in main: routes are
// registered first, then the HTML5 static middleware with the /api/ skipper.
func newStaticTestServer(t *testing.T) *echo.Echo {
	t.Helper()

	webDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(webDir, "index.html"), []byte("<title>Volusia Beach Info</title>"), 0o644))
	require.NoError(t, os.WriteFile(filepath.Join(webDir, "app.js"), []byte("// app"), 0o644))

	e := echo.New()

	// Stand-ins for the v1 legacy route and a v2 JSON route.
	e.GET("/ramps", func(c echo.Context) error {
		return c.JSON(http.StatusOK, []string{"v1"})
	})
	e.GET("/api/v2/ramps", func(c echo.Context) error {
		return c.JSON(http.StatusOK, []string{"v2"})
	})

	e.Use(middleware.StaticWithConfig(middleware.StaticConfig{
		Root:  webDir,
		HTML5: true,
		Skipper: func(c echo.Context) bool {
			return strings.HasPrefix(c.Request().URL.Path, "/api/")
		},
	}))

	return e
}

func TestSPAFallback(t *testing.T) {
	e := newStaticTestServer(t)

	tests := []struct {
		name         string
		path         string
		wantStatus   int
		wantContains string
		wantJSON     bool
	}{
		{"spa ramp route serves index", "/ramp/5", http.StatusOK, "Volusia Beach Info", false},
		{"spa tide route serves index", "/tide", http.StatusOK, "Volusia Beach Info", false},
		{"spa water route serves index", "/water", http.StatusOK, "Volusia Beach Info", false},
		{"spa wind route serves index", "/wind", http.StatusOK, "Volusia Beach Info", false},
		{"root serves index", "/", http.StatusOK, "Volusia Beach Info", false},
		{"real asset served as file", "/app.js", http.StatusOK, "// app", false},
		{"v1 route not swallowed", "/ramps", http.StatusOK, "v1", true},
		{"v2 route not swallowed", "/api/v2/ramps", http.StatusOK, "v2", true},
		{"unknown api path stays JSON 404", "/api/v2/nope", http.StatusNotFound, "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			rec := httptest.NewRecorder()
			e.ServeHTTP(rec, req)

			assert.Equal(t, tt.wantStatus, rec.Code)
			if tt.wantContains != "" {
				assert.Contains(t, rec.Body.String(), tt.wantContains)
			}
			if tt.wantJSON {
				assert.Contains(t, rec.Header().Get(echo.HeaderContentType), "json")
			} else {
				assert.NotContains(t, rec.Header().Get(echo.HeaderContentType), "json")
			}
		})
	}
}
