package camhealth

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/database"
)

// Poller reconciles camera_health against reality by probing each camera's
// public stream URL. The relay runs hlsAlwaysRemux, so the manifest serves
// 200 exactly when a publisher is connected and 404 when not — a clean
// binary end-to-end signal that also covers Caddy/TLS. Hooks give instant
// transitions; this loop establishes state at boot and repairs anything a
// missed hook left stale.
type Poller struct {
	pool     *pgxpool.Pool
	interval time.Duration
	client   *http.Client
	logger   *slog.Logger
}

// NewPoller creates a camera health poller.
func NewPoller(pool *pgxpool.Pool, interval time.Duration) *Poller {
	return &Poller{
		pool:     pool,
		interval: interval,
		client:   &http.Client{Timeout: 10 * time.Second},
		logger:   slog.Default().With("component", "camhealth"),
	}
}

// Start begins the reconcile loop: one pass immediately (so the API boots
// with real state), then on the configured interval until ctx is cancelled.
func (p *Poller) Start(ctx context.Context) {
	p.logger.Info("starting camera health poller", "interval", p.interval)

	p.reconcile(ctx)

	ticker := time.NewTicker(p.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			p.logger.Info("camera health poller shutting down")
			return
		case <-ticker.C:
			p.reconcile(ctx)
		}
	}
}

// reconcile probes every roster camera once and records the results.
func (p *Poller) reconcile(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	cameras, err := database.ListCameras(ctx, p.pool)
	if err != nil {
		p.logger.Warn("reconcile: listing cameras failed", "err", err)
		return
	}

	for _, cam := range cameras {
		if cam.HLSURL == "" {
			continue
		}
		online, ok := p.probe(ctx, cam.HLSURL)
		if !ok {
			// Probe itself failed (network error, timeout) — that says
			// nothing about the camera, so leave its state alone.
			continue
		}
		flipped, err := SetStatus(ctx, p.pool, cam.ID, online, SourcePoll)
		if err != nil {
			p.logger.Warn("reconcile: recording status failed", "camera", cam.ID, "err", err)
			continue
		}
		if flipped {
			p.logger.Info("camera status changed", "camera", cam.ID, "online", online, "source", SourcePoll)
		}
	}
}

// probe fetches a stream manifest URL and classifies it. The second return
// is false when the request failed outright and no conclusion can be drawn.
func (p *Poller) probe(ctx context.Context, url string) (online bool, ok bool) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false, false
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return false, false
	}
	defer resp.Body.Close()
	return classifyProbe(resp.StatusCode), true
}

// classifyProbe maps a manifest HTTP status to online/offline. Only 2xx is
// online; 404 (no publisher on the relay) and anything else is offline.
func classifyProbe(statusCode int) bool {
	return statusCode >= 200 && statusCode < 300
}
