// Package videostream extracts the live HLS URL from a YouTube live video
// (which rotates a few times a day) by invoking yt-dlp and persists the
// result in the settings table as `video_stream_url`.
//
// The Refresher coalesces concurrent refresh requests with singleflight and
// applies a short cooldown so a flapping client cannot drive yt-dlp traffic.
package videostream

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/singleflight"

	"github.com/donwb/beach/api/internal/database"
)

const (
	settingKey       = "video_stream_url"
	defaultCooldown  = 60 * time.Second
	defaultYouTubeURL = "https://www.youtube.com/watch?v=kB2PZC-ow68"
	ytDLPTimeout     = 30 * time.Second
)

// Refresher resolves the current HLS URL for the configured YouTube live
// stream and persists it to the database.
type Refresher struct {
	pool       *pgxpool.Pool
	youtubeURL string
	ytDLPPath  string
	cooldown   time.Duration
	logger     *slog.Logger

	group singleflight.Group

	mu          sync.Mutex
	lastURL     string
	lastSuccess time.Time
}

// New constructs a Refresher. Pass empty strings to use defaults.
func New(pool *pgxpool.Pool, youtubeURL, ytDLPPath string) *Refresher {
	if youtubeURL == "" {
		youtubeURL = defaultYouTubeURL
	}
	if ytDLPPath == "" {
		ytDLPPath = "yt-dlp"
	}
	return &Refresher{
		pool:       pool,
		youtubeURL: youtubeURL,
		ytDLPPath:  ytDLPPath,
		cooldown:   defaultCooldown,
		logger:     slog.Default().With("component", "videostream"),
	}
}

// Result describes a refresh outcome.
type Result struct {
	URL    string
	Cached bool
}

// Refresh resolves the current HLS URL. Concurrent calls within the cooldown
// window share a single yt-dlp invocation. Calls after a successful refresh
// return the cached URL without re-invoking yt-dlp until the cooldown elapses.
func (r *Refresher) Refresh(ctx context.Context) (Result, error) {
	r.mu.Lock()
	if r.lastURL != "" && time.Since(r.lastSuccess) < r.cooldown {
		url := r.lastURL
		r.mu.Unlock()
		return Result{URL: url, Cached: true}, nil
	}
	r.mu.Unlock()

	v, err, _ := r.group.Do("refresh", func() (any, error) {
		return r.doRefresh(ctx)
	})
	if err != nil {
		return Result{}, err
	}
	return Result{URL: v.(string)}, nil
}

func (r *Refresher) doRefresh(ctx context.Context) (string, error) {
	r.mu.Lock()
	if r.lastURL != "" && time.Since(r.lastSuccess) < r.cooldown {
		url := r.lastURL
		r.mu.Unlock()
		return url, nil
	}
	r.mu.Unlock()

	url, err := r.extract(ctx)
	if err != nil {
		return "", fmt.Errorf("extracting HLS URL: %w", err)
	}

	if err := database.UpsertSetting(ctx, r.pool, settingKey, url); err != nil {
		return "", fmt.Errorf("persisting %s: %w", settingKey, err)
	}

	r.mu.Lock()
	r.lastURL = url
	r.lastSuccess = time.Now()
	r.mu.Unlock()

	r.logger.Info("video stream URL refreshed", "len", len(url))
	return url, nil
}

// extract shells out to yt-dlp to resolve the current HLS URL.
func (r *Refresher) extract(ctx context.Context) (string, error) {
	cctx, cancel := context.WithTimeout(ctx, ytDLPTimeout)
	defer cancel()

	cmd := exec.CommandContext(cctx, r.ytDLPPath,
		"-g",
		"--no-warnings",
		"-f", "best[protocol=m3u8_native]",
		r.youtubeURL,
	)

	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return "", fmt.Errorf("yt-dlp exit %d: %s", ee.ExitCode(), strings.TrimSpace(string(ee.Stderr)))
		}
		return "", err
	}

	url := strings.TrimSpace(string(out))
	if url == "" {
		return "", errors.New("yt-dlp returned empty URL")
	}
	if !strings.HasPrefix(url, "http") {
		return "", fmt.Errorf("yt-dlp returned non-URL output: %q", url)
	}
	return url, nil
}

// PrimeFromDB seeds the in-memory cache from the persisted setting so the
// cooldown applies across restarts. Best-effort; failures are logged.
func (r *Refresher) PrimeFromDB(ctx context.Context) {
	url, err := database.GetSetting(ctx, r.pool, settingKey)
	if err != nil || url == "" {
		return
	}
	r.mu.Lock()
	r.lastURL = url
	// Do not set lastSuccess — we don't know how stale the DB value is, so the
	// next refresh request should re-resolve immediately.
	r.mu.Unlock()
}
