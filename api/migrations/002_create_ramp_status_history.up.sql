CREATE TABLE IF NOT EXISTS ramp_status_history (
    id BIGSERIAL PRIMARY KEY,
    access_id VARCHAR(50) NOT NULL,
    access_status VARCHAR(100) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ramp_status_history_access_id ON ramp_status_history(access_id);
CREATE INDEX idx_ramp_status_history_recorded_at ON ramp_status_history(recorded_at);
