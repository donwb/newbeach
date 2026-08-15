CREATE TABLE IF NOT EXISTS ramp_metadata (
    access_id         VARCHAR(50) PRIMARY KEY,
    short_name        TEXT,
    address           TEXT,
    driving_hours     TEXT,
    closure_height_ft DOUBLE PRECISION,
    sort_order        INTEGER
);

-- Seed the New Smyrna Beach driver order (the order a driver meets the ramps
-- heading north of the inlet), matching web/js/order.js CITY_ORDER:
--   BEACHWAY AV=1, CRAWFORD RD=2, FLAGLER AV=3, 3RD AV=4, 27TH AV=5.
--
-- access_id values come from the county GIS feed (the AccessID attribute) and
-- are not knowable statically, so seed by joining ramp_status on the uppercase
-- (city, ramp_name) pair — the same keys order.js matches on. Ramps not yet
-- ingested simply get no seed row; the admin metadata endpoint can fill them
-- in later. ON CONFLICT DO NOTHING keeps the migration re-runnable and never
-- overwrites operator-curated values.
INSERT INTO ramp_metadata (access_id, sort_order)
SELECT r.access_id, v.sort_order
FROM ramp_status r
JOIN (VALUES
    ('BEACHWAY AV', 1),
    ('CRAWFORD RD', 2),
    ('FLAGLER AV', 3),
    ('3RD AV', 4),
    ('27TH AV', 5)
) AS v(ramp_name, sort_order)
    ON UPPER(r.ramp_name) = v.ramp_name
WHERE UPPER(r.city) = 'NEW SMYRNA BEACH'
ON CONFLICT (access_id) DO NOTHING;
