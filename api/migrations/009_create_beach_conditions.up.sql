-- beach_conditions is a periodic snapshot of the environmental conditions and
-- county-wide ramp state, recorded on an interval (default every 30 minutes)
-- by the conditions logger. It exists to accumulate training data for the
-- ramp open/close prediction feature: ramp_status_history records *when*
-- statuses changed, and this table records *what the ocean was doing* around
-- those moments. Every condition column is nullable — a snapshot row is
-- written even when some upstream source (NOAA, NWS, NDBC buoy) is down.
CREATE TABLE IF NOT EXISTS beach_conditions (
    id                 BIGSERIAL PRIMARY KEY,
    recorded_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tide_predicted_ft  DOUBLE PRECISION,   -- predicted tide height at recorded_at (ft MLLW)
    next_peak_ft       DOUBLE PRECISION,   -- height of the next predicted high tide
    next_peak_at       TIMESTAMPTZ,        -- time of the next predicted high tide
    wind_speed_mph     DOUBLE PRECISION,
    wind_gust_mph      DOUBLE PRECISION,
    wind_dir           TEXT,               -- cardinal, e.g. "ENE"
    wave_height_ft     DOUBLE PRECISION,   -- NDBC buoy significant wave height
    dominant_period_s  DOUBLE PRECISION,   -- NDBC buoy dominant wave period
    ramps_open         INTEGER,            -- ramps in the "open" category
    ramps_closed_tide  INTEGER,            -- ramps with status CLOSED FOR HIGH TIDE
    ramps_closed_other INTEGER             -- ramps closed for any other reason
);

CREATE INDEX idx_beach_conditions_recorded_at ON beach_conditions(recorded_at);
