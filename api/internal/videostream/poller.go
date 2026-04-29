package videostream

import (
	"context"
	"log/slog"
	"time"
)

// SafetyPoll periodically refreshes the HLS URL so the stored value stays warm
// even when no client is actively watching. The primary refresh path is the
// /api/v2/video/refresh endpoint driven by client playback failures; this poll
// is the long-interval backstop.
//
// Blocks until ctx is cancelled.
func (r *Refresher) SafetyPoll(ctx context.Context, interval time.Duration) {
	logger := r.logger.With("loop", "safety-poll", "interval", interval)
	logger.Info("starting safety-net video stream poller")

	t := time.NewTicker(interval)
	defer t.Stop()

	for {
		select {
		case <-ctx.Done():
			logger.Info("safety-net poller shutting down")
			return
		case <-t.C:
			if _, err := r.Refresh(ctx); err != nil {
				logger.Warn("safety-net refresh failed", "err", err)
			} else {
				slog.Default().Debug("safety-net refresh ok")
			}
		}
	}
}
