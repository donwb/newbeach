package handlers

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/netip"
	"net/url"
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

// isNavigationRequest reports whether a request is a real top-level page
// navigation rather than a script-issued fetch that happens to target a page
// URL. The service worker precaches "/" at install time, and that fetch would
// otherwise land in the log as a phantom visit referred by /sw.js.
//
// Sec-Fetch-Mode separates them: a navigation stays mode=navigate even when the
// worker forwards it itself, while the precache fetch arrives as cors. Browsers
// too old to send Fetch Metadata (before Safari 16.4) omit the header entirely
// and are trusted — undercounting real visits is worse than a little noise.
func isNavigationRequest(r *http.Request) bool {
	mode := r.Header.Get("Sec-Fetch-Mode")
	return mode == "" || mode == "navigate"
}

// clip returns s truncated to max bytes — header values are attacker-supplied
// and must not bloat the table.
func clip(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}

// cleanReferer drops the service worker's own script URL. This site referring
// to itself is not a real source, and recording it buries genuine attribution.
//
// isNavigationRequest already discards the usual culprit — the worker's
// install-time precache of "/" — so this is the backstop for the cases it
// cannot see: browsers that send no Fetch Metadata, and any browser that
// rewrites Referer when the worker forwards a navigation itself.
func cleanReferer(raw string) string {
	if raw == "" {
		return ""
	}
	if u, err := url.Parse(raw); err == nil && u.Path == "/sw.js" {
		return ""
	}
	return clip(raw, 500)
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
			if !isNavigationRequest(c.Request()) {
				return err
			}

			view := models.PageView{
				Path:      c.Request().URL.Path,
				IP:        clip(c.RealIP(), 64),
				UserAgent: clip(c.Request().UserAgent(), 500),
				Referer:   cleanReferer(c.Request().Referer()),
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

// splitIPs turns a comma-separated exclude_ip value into a clean slice of
// exact addresses and CIDR prefixes, normalised for Postgres inet.
//
// Prefixes matter because the owner's own traffic arrives from rotating IPv6
// privacy addresses that share a /64 — excluding them one at a time is a losing
// game, and every rotation reappears as a brand new "visitor". A bare address
// normalises to a full-length prefix, so the query needs only one operator for
// both forms.
//
// Garbage is rejected here rather than passed to the database: exclude_ip is
// interpolated into an inet[] and an unparseable element would fail the whole
// query with an opaque error.
func splitIPs(raw string) ([]string, error) {
	if raw == "" {
		return nil, nil
	}
	ips := []string{}
	for _, tok := range strings.Split(raw, ",") {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		if strings.Contains(tok, "/") {
			prefix, err := netip.ParsePrefix(tok)
			if err != nil {
				return nil, fmt.Errorf("exclude_ip %q is not a valid CIDR prefix", tok)
			}
			// Masked so a prefix written with host bits set (2606::1/64)
			// still means the whole network.
			ips = append(ips, prefix.Masked().String())
			continue
		}
		addr, err := netip.ParseAddr(tok)
		if err != nil {
			return nil, fmt.Errorf("exclude_ip %q is not a valid IP address", tok)
		}
		ips = append(ips, addr.String())
	}
	return ips, nil
}

// HandleAdminPageViews reports who has been reading the site.
// GET /api/v2/admin/pageviews?since=2026-08-18&path=/county/&exclude_ip=a,b&group=ip&limit=500
// Default window is the last 7 days. group=ip returns per-visitor rollups
// (views, first/last seen, distinct paths, latest user agent) instead of raw rows.
//
// exclude_ip accepts exact addresses and CIDR prefixes, comma-separated —
// exclude_ip=2606:9cc0:100:50e::/64 drops a whole rotating IPv6 range in one go.
func HandleAdminPageViews(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		ctx := c.Request().Context()

		since, err := parsePageViewSince(c.QueryParam("since"), time.Now())
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "since must be YYYY-MM-DD or RFC 3339"})
		}
		excludeIPs, err := splitIPs(c.QueryParam("exclude_ip"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
		}

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
