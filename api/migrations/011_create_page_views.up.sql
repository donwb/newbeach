-- First-party page-view log: one row per HTML page navigation (never API
-- calls or assets). Exists to answer "who is visiting besides me?" —
-- notably whether Volusia County staff open /county/ after outreach.
CREATE TABLE page_views (
    id         BIGSERIAL PRIMARY KEY,
    viewed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    path       TEXT NOT NULL,
    ip         TEXT NOT NULL,
    user_agent TEXT NOT NULL DEFAULT '',
    referer    TEXT NOT NULL DEFAULT ''
);

CREATE INDEX page_views_viewed_at_idx ON page_views (viewed_at DESC);
CREATE INDEX page_views_path_idx ON page_views (path);
