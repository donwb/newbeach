CREATE TABLE IF NOT EXISTS cameras (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    location    TEXT,
    youtube_url TEXT NOT NULL,
    hls_url     TEXT NOT NULL DEFAULT '',
    sort_order  INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed the Volusia Beaches camera roster, ordered south-to-north along the coast.
-- The New Smyrna Beach cam is the default (sort_order 0); its hls_url is carried
-- over from the existing settings.video_stream_url so the stream does not go dark
-- between this migration running and the next home-cron refresh populating the rest.
INSERT INTO cameras (id, name, location, youtube_url, hls_url, sort_order) VALUES
    ('nsb',              'New Smyrna Beach',   'New Smyrna Beach',   'https://www.youtube.com/watch?v=kB2PZC-ow68',
        COALESCE((SELECT value FROM settings WHERE key = 'video_stream_url'), ''), 0),
    ('ponce-inlet',      'Ponce Inlet',        'Ponce Inlet',        'https://www.youtube.com/watch?v=k7Dsmy0CdKA', '', 1),
    ('dunlawton',        'Dunlawton',          'Daytona Beach Shores','https://www.youtube.com/watch?v=3hwTkO_5KXo', '', 2),
    ('ormond-beach',     'Ormond Beach',       'Ormond Beach',       'https://www.youtube.com/watch?v=wi8WBIcwXRY', '', 3),
    ('ormond-by-the-sea','Ormond-By-The-Sea',  'Ormond-By-The-Sea',  'https://www.youtube.com/watch?v=-grSyQa817o', '', 4)
ON CONFLICT (id) DO NOTHING;
