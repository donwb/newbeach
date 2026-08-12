-- ArcGIS OBJECTIDs are not stable identifiers: the county reassigns them when
-- the Beaches layer is republished, which can hand one ramp another ramp's old
-- OBJECTID and make the upsert violate this constraint. access_id is the real
-- unique key.
ALTER TABLE ramp_status DROP CONSTRAINT IF EXISTS ramp_status_object_id_key;
