CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed the video stream URL setting.
INSERT INTO settings (key, value) VALUES ('video_stream_url', '')
ON CONFLICT (key) DO NOTHING;
