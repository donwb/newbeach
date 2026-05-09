package videostream

import (
	"context"
	"log/slog"
	"time"
)

// SafetyPoll periodically refreshes the HLS URL so the stored value tracks
// YouTube's URL rotation. This is the primary refresh path — the
// /api/v2/video/refresh endpoint exists as an on-demand fallback for clients.
//
// Blocks until ctx is cancelled.
func (r *Refresher) SafetyPoll(ctx context.Context, interval time.Duration) {
	logger := r.logger.With("loop", "video-poll", "interval", interval)
	logger.Info("starting video stream poller")

	t := time.NewTicker(interval)
	defer t.Stop()

	for {
		select {
		case <-ctx.Done():
			logger.Info("video poller shutting down")
			return
		case <-t.C:
			if _, err := r.Refresh(ctx); err != nil {
				logger.Warn("video refresh failed", "err", err)
			} else {
				slog.Default().Debug("video refresh ok")
			}
		}
	}
}
