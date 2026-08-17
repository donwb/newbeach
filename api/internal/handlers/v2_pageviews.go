package handlers

import (
	"context"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/donwb/beach/api/internal/database"
	"github.com/donwb/beach/api/internal/models"
)

// rampPathRe matches SPA ramp-detail deep links (/ramp/:id).
var rampPathRe = regexp.MustCompile(`^/ramp/\d+/?$`)

// isPageView reports whether a request path is an HTML page navigation worth
// logging: the board, the static /county/ page, and the SPA deep links.
// Assets and API calls never match.
func isPageView(path string) bool {
	switch strings.TrimSuffix(path, "/") {
	case "", "/county", "/tide", "/water", "/wind", "/privacy", "/support":
		return true
	}
	return rampPathRe.MatchString(path)
}

// clip returns s truncated to max bytes — header values are attacker-supplied
// and must not bloat the table.
func clip(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}

// pageViewLogger records successful GET page navigations to the page_views
// table. Recording is asynchronous and best-effort: it must never slow down
// or fail a user request.
func pageViewLogger(pool *pgxpool.Pool) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			err := next(c)
			if c.Request().Method != http.MethodGet || !isPageView(c.Request().URL.Path) {
				return err
			}
			if status := c.Response().Status; status >= 400 {
				return err
			}

			view := models.PageView{
				Path:      c.Request().URL.Path,
				IP:        c.RealIP(),
				UserAgent: clip(c.Request().UserAgent(), 500),
				Referer:   clip(c.Request().Referer(), 500),
			}
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				if err := database.InsertPageView(ctx, pool, view); err != nil {
					slog.Warn("recording page view failed", "path", view.Path, "err", err)
				}
			}()
			return err
		}
	}
}

// parsePageViewSince interprets the admin endpoint's since parameter: empty
// means the last 7 days, a bare date means midnight UTC that day, otherwise
// RFC 3339.
func parsePageViewSince(raw string, now time.Time) (time.Time, error) {
	if raw == "" {
		return now.AddDate(0, 0, -7), nil
	}
	if t, err := time.Parse("2006-01-02", raw); err == nil {
		return t, nil
	}
	return time.Parse(time.RFC3339, raw)
}

// splitIPs turns a comma-separated exclude_ip value into a clean slice.
func splitIPs(raw string) []string {
	if raw == "" {
		return nil
	}
	ips := []string{}
	for _, ip := range strings.Split(raw, ",") {
		if ip = strings.TrimSpace(ip); ip != "" {
			ips = append(ips, ip)
		}
	}
	return ips
}

// HandleAdminPageViews reports who has been reading the site.
// GET /api/v2/admin/pageviews?since=2026-08-18&path=/county/&exclude_ip=a,b&group=ip&limit=500
// Default window is the last 7 days. group=ip returns per-visitor rollups
// (views, first/last seen, distinct paths, latest user agent) instead of raw rows.
func HandleAdminPageViews(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		since, err := parsePageViewSince(c.QueryParam("since"), time.Now())
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "since must be YYYY-MM-DD or RFC 3339"})
		}
		excludeIPs := splitIPs(c.QueryParam("exclude_ip"))

		if c.QueryParam("group") == "ip" {
			summaries, err := database.SummarizePageViewIPs(ctx, pool, since, excludeIPs)
			if err != nil {
				slog.Error("summarizing page views failed", "err", err)
				return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to summarize page views"})
			}
			return c.JSON(http.StatusOK, map[string]interface{}{
				"since": since,
				"count": len(summaries),
				"ips":   summaries,
			})
		}

		limit := 500
		if raw := c.QueryParam("limit"); raw != "" {
			if err := echo.QueryParamsBinder(c).Int("limit", &limit).BindError(); err != nil || limit < 1 || limit > 5000 {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "limit must be 1-5000"})
			}
		}

		views, err := database.ListPageViews(ctx, pool, since, c.QueryParam("path"), excludeIPs, limit)
		if err != nil {
			slog.Error("listing page views failed", "err", err)
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list page views"})
		}
		return c.JSON(http.StatusOK, map[string]interface{}{
			"since": since,
			"count": len(views),
			"views": views,
		})
	}
}
