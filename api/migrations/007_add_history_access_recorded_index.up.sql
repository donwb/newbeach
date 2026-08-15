CREATE INDEX IF NOT EXISTS idx_ramp_status_history_access_recorded
    ON ramp_status_history(access_id, recorded_at);
