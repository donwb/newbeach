-- Widget push tokens (iOS 26 WidgetKit push updates). One row per device
-- widget push token; the ingester pushes "content-changed" to every row
-- when a ramp's status flips, and APNs rejections (410 / BadDeviceToken)
-- delete the row.
CREATE TABLE IF NOT EXISTS widget_push_tokens (
    token          TEXT PRIMARY KEY,
    environment    TEXT NOT NULL DEFAULT 'production',
    bundle_id      TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_pushed_at TIMESTAMPTZ
);
