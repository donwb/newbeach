-- camera_health is the relay's view of each camera stream: online means a
-- publisher (the home restreamer) is connected to MediaMTX for that path, so
-- the public HLS URL is serving. Written from two sources that reconcile to
-- the same truth: MediaMTX runOnReady/runOnNotReady hooks (instant, source
-- 'hook') and the in-process poller probing each stream_url (catches
-- transitions missed while the API was down, source 'poll').
CREATE TABLE IF NOT EXISTS camera_health (
    camera_id  TEXT PRIMARY KEY REFERENCES cameras(id) ON DELETE CASCADE,
    online     BOOLEAN NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- when online last flipped
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- last confirmation of the current state
    source     TEXT NOT NULL                        -- 'hook' or 'poll' (who last confirmed)
);

-- Append-only log of transitions (flap history). Rows are written only when
-- online actually flips, never on steady-state confirmations.
CREATE TABLE IF NOT EXISTS camera_health_history (
    id          BIGSERIAL PRIMARY KEY,
    camera_id   TEXT NOT NULL,
    online      BOOLEAN NOT NULL,
    source      TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_camera_health_history_cam_time
    ON camera_health_history(camera_id, recorded_at DESC);
