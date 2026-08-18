-- wave_observations is the canonical per-buoy wave time series feeding the
-- wave-aware closure prediction model. Unlike beach_conditions (a snapshot of
-- everything at insert time), rows here carry the buoy's own observation
-- timestamp, so the table can be backfilled from NDBC's monthly archives and
-- kept fresh by the 30-minute conditions logger. The UNIQUE key makes every
-- writer an idempotent upsert.
CREATE TABLE IF NOT EXISTS wave_observations (
    id                BIGSERIAL PRIMARY KEY,
    station_id        TEXT NOT NULL,
    observed_at       TIMESTAMPTZ NOT NULL,   -- the buoy's timestamp, not insert time
    wave_height_ft    DOUBLE PRECISION NOT NULL,
    dominant_period_s DOUBLE PRECISION,
    UNIQUE (station_id, observed_at)
);

CREATE INDEX idx_wave_observations_observed_at ON wave_observations(observed_at);
