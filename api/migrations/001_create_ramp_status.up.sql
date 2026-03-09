CREATE TABLE IF NOT EXISTS ramp_status (
    id BIGSERIAL PRIMARY KEY,
    ramp_name VARCHAR(255) NOT NULL,
    access_status VARCHAR(100) NOT NULL,
    status_category VARCHAR(20) NOT NULL,
    object_id BIGINT NOT NULL UNIQUE,
    city VARCHAR(100) NOT NULL,
    access_id VARCHAR(50) NOT NULL UNIQUE,
    location VARCHAR(255) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ramp_status_city ON ramp_status(city);
CREATE INDEX idx_ramp_status_access_id ON ramp_status(access_id);
CREATE INDEX idx_ramp_status_status_category ON ramp_status(status_category);
