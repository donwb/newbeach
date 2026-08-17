package database

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/donwb/beach/api/internal/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// UpsertRampStatus inserts or updates a ramp status record, using access_id
// as the conflict key. On conflict it updates every mutable field and bumps
// updated_at to NOW().
func UpsertRampStatus(ctx context.Context, pool *pgxpool.Pool, ramp models.RampStatus) error {
	const query = `
		INSERT INTO ramp_status (ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
		ON CONFLICT (access_id) DO UPDATE SET
			ramp_name       = EXCLUDED.ramp_name,
			access_status   = EXCLUDED.access_status,
			status_category = EXCLUDED.status_category,
			object_id       = EXCLUDED.object_id,
			city            = EXCLUDED.city,
			location        = EXCLUDED.location,
			updated_at      = NOW()
	`

	_, err := pool.Exec(ctx, query,
		ramp.RampName,
		ramp.AccessStatus,
		ramp.StatusCategory,
		ramp.ObjectID,
		ramp.City,
		ramp.AccessID,
		ramp.Location,
	)
	if err != nil {
		return fmt.Errorf("upserting ramp status for access_id %s: %w", ramp.AccessID, err)
	}

	return nil
}

// InsertRampHistory appends a status-change record to the ramp_status_history
// table. The recorded_at timestamp is set to NOW() by the database.
func InsertRampHistory(ctx context.Context, pool *pgxpool.Pool, accessID, status string) error {
	const query = `
		INSERT INTO ramp_status_history (access_id, access_status)
		VALUES ($1, $2)
	`

	_, err := pool.Exec(ctx, query, accessID, status)
	if err != nil {
		return fmt.Errorf("inserting ramp history for access_id %s: %w", accessID, err)
	}

	return nil
}

// GetAllRamps returns every ramp_status row ordered by city then ramp_name.
func GetAllRamps(ctx context.Context, pool *pgxpool.Pool) ([]models.RampStatus, error) {
	const query = `
		SELECT id, ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at
		FROM ramp_status
		ORDER BY city, ramp_name
	`

	rows, err := pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("querying all ramps: %w", err)
	}
	defer rows.Close()

	return scanRamps(rows)
}

// GetRampsByCity returns all ramp_status rows for the given city.
func GetRampsByCity(ctx context.Context, pool *pgxpool.Pool, city string) ([]models.RampStatus, error) {
	const query = `
		SELECT id, ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at
		FROM ramp_status
		WHERE city = $1
		ORDER BY ramp_name
	`

	rows, err := pool.Query(ctx, query, city)
	if err != nil {
		return nil, fmt.Errorf("querying ramps for city %s: %w", city, err)
	}
	defer rows.Close()

	return scanRamps(rows)
}

// GetRampsWithStatusSince returns ramps along with the time each ramp's
// current status took effect (the most recent history entry, if any) and any
// operator-curated metadata (LEFT JOIN — all metadata fields nullable).
// Empty city or status skips that filter.
func GetRampsWithStatusSince(ctx context.Context, pool *pgxpool.Pool, city, status string) ([]models.RampStatusWithSince, error) {
	query := `
		SELECT r.id, r.ramp_name, r.access_status, r.status_category, r.object_id, r.city, r.access_id, r.location, r.updated_at,
		       h.recorded_at,
		       m.short_name, m.address, m.driving_hours, m.closure_height_ft, m.sort_order
		FROM ramp_status r
		LEFT JOIN LATERAL (
			SELECT recorded_at
			FROM ramp_status_history
			WHERE access_id = r.access_id
			ORDER BY recorded_at DESC
			LIMIT 1
		) h ON true
		LEFT JOIN ramp_metadata m ON m.access_id = r.access_id
		WHERE 1=1
	`
	args := make([]interface{}, 0, 2)
	if city != "" {
		args = append(args, city)
		query += fmt.Sprintf(" AND r.city = $%d", len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(" AND r.status_category = $%d", len(args))
	}
	query += " ORDER BY r.city, r.ramp_name"

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying ramps with status since (city=%q status=%q): %w", city, status, err)
	}
	defer rows.Close()

	var ramps []models.RampStatusWithSince
	for rows.Next() {
		var r models.RampStatusWithSince
		if err := rows.Scan(
			&r.ID, &r.RampName, &r.AccessStatus, &r.StatusCategory,
			&r.ObjectID, &r.City, &r.AccessID, &r.Location, &r.UpdatedAt,
			&r.StatusSince,
			&r.ShortName, &r.Address, &r.DrivingHours, &r.ClosureHeightFt, &r.SortOrder,
		); err != nil {
			return nil, fmt.Errorf("scanning ramp with status since row: %w", err)
		}
		ramps = append(ramps, r)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating ramps with status since rows: %w", err)
	}

	return ramps, nil
}

// GetRampByID returns a single ramp_status row by its primary key.
// Returns nil and no error if the row does not exist.
func GetRampByID(ctx context.Context, pool *pgxpool.Pool, id int64) (*models.RampStatus, error) {
	const query = `
		SELECT id, ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at
		FROM ramp_status
		WHERE id = $1
	`

	row := pool.QueryRow(ctx, query, id)
	ramp, err := scanSingleRamp(row)
	if err != nil {
		return nil, fmt.Errorf("fetching ramp by id %d: %w", id, err)
	}

	return ramp, nil
}

// GetRampByAccessID returns a single ramp_status row by its unique access_id.
// Returns nil and no error if the row does not exist.
func GetRampByAccessID(ctx context.Context, pool *pgxpool.Pool, accessID string) (*models.RampStatus, error) {
	const query = `
		SELECT id, ramp_name, access_status, status_category, object_id, city, access_id, location, updated_at
		FROM ramp_status
		WHERE access_id = $1
	`

	row := pool.QueryRow(ctx, query, accessID)
	ramp, err := scanSingleRamp(row)
	if err != nil {
		return nil, fmt.Errorf("fetching ramp by access_id %s: %w", accessID, err)
	}

	return ramp, nil
}

// GetRampHistory returns the most recent history entries for a specific ramp,
// identified by its access_id. Results are ordered newest-first.
func GetRampHistory(ctx context.Context, pool *pgxpool.Pool, accessID string, limit int) ([]models.RampHistoryEntry, error) {
	const query = `
		SELECT id, access_id, access_status, recorded_at
		FROM ramp_status_history
		WHERE access_id = $1
		ORDER BY recorded_at DESC
		LIMIT $2
	`

	rows, err := pool.Query(ctx, query, accessID, limit)
	if err != nil {
		return nil, fmt.Errorf("querying ramp history for access_id %s: %w", accessID, err)
	}
	defer rows.Close()

	var entries []models.RampHistoryEntry
	for rows.Next() {
		var e models.RampHistoryEntry
		if err := rows.Scan(&e.ID, &e.AccessID, &e.AccessStatus, &e.RecordedAt); err != nil {
			return nil, fmt.Errorf("scanning ramp history row: %w", err)
		}
		entries = append(entries, e)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating ramp history rows: %w", err)
	}

	return entries, nil
}

// GetRampStatusEvents returns a ramp's status-change events from `since`
// onward, plus the single most recent event before `since` (the baseline —
// the status already in effect when the window opens). Results are ordered
// oldest-first.
func GetRampStatusEvents(ctx context.Context, pool *pgxpool.Pool, accessID string, since time.Time) ([]models.StatusEvent, error) {
	const query = `
		SELECT access_status, recorded_at FROM (
			(SELECT access_status, recorded_at
			 FROM ramp_status_history
			 WHERE access_id = $1 AND recorded_at < $2
			 ORDER BY recorded_at DESC
			 LIMIT 1)
			UNION ALL
			(SELECT access_status, recorded_at
			 FROM ramp_status_history
			 WHERE access_id = $1 AND recorded_at >= $2)
		) events
		ORDER BY recorded_at
	`

	rows, err := pool.Query(ctx, query, accessID, since)
	if err != nil {
		return nil, fmt.Errorf("querying status events for access_id %s: %w", accessID, err)
	}
	defer rows.Close()

	var events []models.StatusEvent
	for rows.Next() {
		var e models.StatusEvent
		if err := rows.Scan(&e.AccessStatus, &e.RecordedAt); err != nil {
			return nil, fmt.Errorf("scanning status event row: %w", err)
		}
		events = append(events, e)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating status event rows: %w", err)
	}

	return events, nil
}

// GetRecentHistory returns the most recent history entries across all ramps,
// enriched with ramp_name and city from the ramp_status table.
// Results are ordered newest-first.
func GetRecentHistory(ctx context.Context, pool *pgxpool.Pool, limit int) ([]models.RampHistoryEntry, error) {
	return GetRecentHistoryFiltered(ctx, pool, limit, "", "", nil)
}

// GetRecentHistoryFiltered is GetRecentHistory with optional filters: city
// (exact match on the ramp's city), ramp (the history entry's access_id), and
// since (only entries recorded at or after the given instant). Zero values
// skip each filter, making the no-filter call identical to GetRecentHistory.
func GetRecentHistoryFiltered(ctx context.Context, pool *pgxpool.Pool, limit int, city, ramp string, since *time.Time) ([]models.RampHistoryEntry, error) {
	query, args := buildRecentHistoryQuery(limit, city, ramp, since)

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying recent history: %w", err)
	}
	defer rows.Close()

	var entries []models.RampHistoryEntry
	for rows.Next() {
		var e models.RampHistoryEntry
		if err := rows.Scan(&e.ID, &e.AccessID, &e.AccessStatus, &e.RecordedAt, &e.RampName, &e.City); err != nil {
			return nil, fmt.Errorf("scanning recent history row: %w", err)
		}
		entries = append(entries, e)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating recent history rows: %w", err)
	}

	return entries, nil
}

// buildRecentHistoryQuery assembles the recent-history SQL and its positional
// args. Split out from GetRecentHistoryFiltered so the clause/placeholder
// construction is unit-testable without a database.
func buildRecentHistoryQuery(limit int, city, ramp string, since *time.Time) (string, []interface{}) {
	query := `
		SELECT h.id, h.access_id, h.access_status, h.recorded_at, r.ramp_name, r.city
		FROM ramp_status_history h
		JOIN ramp_status r ON h.access_id = r.access_id
	`
	args := make([]interface{}, 0, 4)
	var clauses []string
	if city != "" {
		args = append(args, city)
		clauses = append(clauses, fmt.Sprintf("r.city = $%d", len(args)))
	}
	if ramp != "" {
		args = append(args, ramp)
		clauses = append(clauses, fmt.Sprintf("h.access_id = $%d", len(args)))
	}
	if since != nil {
		args = append(args, *since)
		clauses = append(clauses, fmt.Sprintf("h.recorded_at >= $%d", len(args)))
	}
	if len(clauses) > 0 {
		query += "	WHERE " + strings.Join(clauses, " AND ") + "\n"
	}
	args = append(args, limit)
	query += fmt.Sprintf(`	ORDER BY h.recorded_at DESC
		LIMIT $%d
	`, len(args))

	return query, args
}

// UpsertRampMetadata inserts or fully replaces the metadata row for an
// access_id and returns the stored row. Nil pointer fields store SQL NULL,
// so an upsert with a missing or null field clears that column.
func UpsertRampMetadata(ctx context.Context, pool *pgxpool.Pool, meta models.RampMetadata) (*models.RampMetadata, error) {
	const query = `
		INSERT INTO ramp_metadata (access_id, short_name, address, driving_hours, closure_height_ft, sort_order)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (access_id) DO UPDATE SET
			short_name        = EXCLUDED.short_name,
			address           = EXCLUDED.address,
			driving_hours     = EXCLUDED.driving_hours,
			closure_height_ft = EXCLUDED.closure_height_ft,
			sort_order        = EXCLUDED.sort_order
		RETURNING access_id, short_name, address, driving_hours, closure_height_ft, sort_order
	`

	var stored models.RampMetadata
	err := pool.QueryRow(ctx, query,
		meta.AccessID,
		meta.ShortName,
		meta.Address,
		meta.DrivingHours,
		meta.ClosureHeightFt,
		meta.SortOrder,
	).Scan(
		&stored.AccessID,
		&stored.ShortName,
		&stored.Address,
		&stored.DrivingHours,
		&stored.ClosureHeightFt,
		&stored.SortOrder,
	)
	if err != nil {
		return nil, fmt.Errorf("upserting ramp metadata for access_id %s: %w", meta.AccessID, err)
	}

	return &stored, nil
}

// --- Cameras ---

// ListCameras returns the full camera roster ordered south-to-north
// (by sort_order, then id for stability).
func ListCameras(ctx context.Context, pool *pgxpool.Pool) ([]models.Camera, error) {
	const query = `
		SELECT id, name, COALESCE(location, ''), youtube_url, hls_url, sort_order, updated_at
		FROM cameras
		ORDER BY sort_order, id
	`
	rows, err := pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("querying cameras: %w", err)
	}
	defer rows.Close()

	cameras := make([]models.Camera, 0)
	for rows.Next() {
		var cam models.Camera
		if err := rows.Scan(&cam.ID, &cam.Name, &cam.Location, &cam.YouTubeURL, &cam.HLSURL, &cam.SortOrder, &cam.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scanning camera row: %w", err)
		}
		cameras = append(cameras, cam)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating camera rows: %w", err)
	}
	return cameras, nil
}

// GetDefaultCameraHLS returns the HLS URL of the default camera (lowest
// sort_order). Used to populate the legacy video_stream_url field in
// /api/v2/config. Returns empty string if no cameras exist.
func GetDefaultCameraHLS(ctx context.Context, pool *pgxpool.Pool) (string, error) {
	var hls string
	err := pool.QueryRow(ctx, `SELECT hls_url FROM cameras ORDER BY sort_order, id LIMIT 1`).Scan(&hls)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", nil
		}
		return "", fmt.Errorf("fetching default camera hls: %w", err)
	}
	return hls, nil
}

// UpdateDefaultCameraHLS sets the HLS URL on the default camera (lowest
// sort_order). Used as a transition bridge so the legacy settings-based
// video_stream_url push keeps the default camera fresh until the cron is
// switched to the per-camera endpoint. No-op (nil) if no cameras exist.
func UpdateDefaultCameraHLS(ctx context.Context, pool *pgxpool.Pool, hlsURL string) error {
	_, err := pool.Exec(ctx,
		`UPDATE cameras SET hls_url = $1, updated_at = NOW()
		 WHERE id = (SELECT id FROM cameras ORDER BY sort_order, id LIMIT 1)`,
		hlsURL)
	if err != nil {
		return fmt.Errorf("updating default camera hls: %w", err)
	}
	return nil
}

// UpdateCameraHLS sets the resolved HLS URL for a single camera and bumps
// updated_at. Returns ErrNoRows if the camera id does not exist.
func UpdateCameraHLS(ctx context.Context, pool *pgxpool.Pool, id, hlsURL string) error {
	tag, err := pool.Exec(ctx,
		`UPDATE cameras SET hls_url = $2, updated_at = NOW() WHERE id = $1`,
		id, hlsURL)
	if err != nil {
		return fmt.Errorf("updating camera %s hls: %w", id, err)
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// CameraExists reports whether a camera id is in the roster.
func CameraExists(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	var exists bool
	err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM cameras WHERE id = $1)`, id).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("checking camera %s exists: %w", id, err)
	}
	return exists, nil
}

// --- Settings ---

// GetSetting returns the value for a single settings key.
// Returns empty string if the key does not exist.
func GetSetting(ctx context.Context, pool *pgxpool.Pool, key string) (string, error) {
	var value string
	err := pool.QueryRow(ctx, `SELECT value FROM settings WHERE key = $1`, key).Scan(&value)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", nil
		}
		return "", fmt.Errorf("fetching setting %s: %w", key, err)
	}
	return value, nil
}

// UpsertSetting inserts or updates a settings key-value pair.
func UpsertSetting(ctx context.Context, pool *pgxpool.Pool, key, value string) error {
	const query = `
		INSERT INTO settings (key, value, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (key) DO UPDATE SET
			value = EXCLUDED.value,
			updated_at = NOW()
	`
	_, err := pool.Exec(ctx, query, key, value)
	if err != nil {
		return fmt.Errorf("upserting setting %s: %w", key, err)
	}
	return nil
}

// GetAllSettings returns all settings as a map.
func GetAllSettings(ctx context.Context, pool *pgxpool.Pool) (map[string]string, error) {
	rows, err := pool.Query(ctx, `SELECT key, value FROM settings ORDER BY key`)
	if err != nil {
		return nil, fmt.Errorf("querying all settings: %w", err)
	}
	defer rows.Close()

	settings := make(map[string]string)
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, fmt.Errorf("scanning settings row: %w", err)
		}
		settings[k] = v
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating settings rows: %w", err)
	}
	return settings, nil
}

// GetAllRampHistoryEvents returns every ramp's full status-change history,
// keyed by access_id, each slice ordered oldest-first. Used by the nightly
// prediction trainer; the full table is ~tens of thousands of rows.
func GetAllRampHistoryEvents(ctx context.Context, pool *pgxpool.Pool) (map[string][]models.StatusEvent, error) {
	rows, err := pool.Query(ctx, `
		SELECT access_id, access_status, recorded_at
		FROM ramp_status_history
		ORDER BY access_id, recorded_at
	`)
	if err != nil {
		return nil, fmt.Errorf("querying full ramp history: %w", err)
	}
	defer rows.Close()

	events := make(map[string][]models.StatusEvent)
	for rows.Next() {
		var accessID string
		var e models.StatusEvent
		if err := rows.Scan(&accessID, &e.AccessStatus, &e.RecordedAt); err != nil {
			return nil, fmt.Errorf("scanning full history row: %w", err)
		}
		events[accessID] = append(events[accessID], e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating full history rows: %w", err)
	}
	return events, nil
}

// --- Beach conditions ---

// InsertBeachConditions appends one snapshot row to the beach_conditions
// table. recorded_at defaults to NOW() in the database.
func InsertBeachConditions(ctx context.Context, pool *pgxpool.Pool, c models.BeachConditions) error {
	const query = `
		INSERT INTO beach_conditions (
			tide_predicted_ft, next_peak_ft, next_peak_at,
			wind_speed_mph, wind_gust_mph, wind_dir,
			wave_height_ft, dominant_period_s,
			ramps_open, ramps_closed_tide, ramps_closed_other
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
	`

	_, err := pool.Exec(ctx, query,
		c.TidePredictedFt, c.NextPeakFt, c.NextPeakAt,
		c.WindSpeedMph, c.WindGustMph, c.WindDir,
		c.WaveHeightFt, c.DominantPeriodS,
		c.RampsOpen, c.RampsClosedTide, c.RampsClosedOther,
	)
	if err != nil {
		return fmt.Errorf("inserting beach conditions: %w", err)
	}

	return nil
}

// ListRampStatuses returns the current access_status of every ramp. Category
// mapping stays in Go (models.StatusToCategory) so callers count without
// duplicating the status taxonomy in SQL.
func ListRampStatuses(ctx context.Context, pool *pgxpool.Pool) ([]string, error) {
	rows, err := pool.Query(ctx, `SELECT access_status FROM ramp_status`)
	if err != nil {
		return nil, fmt.Errorf("querying ramp statuses: %w", err)
	}
	defer rows.Close()

	var statuses []string
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err != nil {
			return nil, fmt.Errorf("scanning ramp status: %w", err)
		}
		statuses = append(statuses, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating ramp statuses: %w", err)
	}
	return statuses, nil
}

// scanRamps collects all rows from a pgx.Rows into a slice of RampStatus.
func scanRamps(rows pgx.Rows) ([]models.RampStatus, error) {
	var ramps []models.RampStatus

	for rows.Next() {
		var r models.RampStatus
		if err := rows.Scan(
			&r.ID,
			&r.RampName,
			&r.AccessStatus,
			&r.StatusCategory,
			&r.ObjectID,
			&r.City,
			&r.AccessID,
			&r.Location,
			&r.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scanning ramp row: %w", err)
		}
		ramps = append(ramps, r)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating ramp rows: %w", err)
	}

	return ramps, nil
}

// scanSingleRamp scans a single row into a RampStatus pointer.
// Returns nil with no error when the row does not exist.
func scanSingleRamp(row pgx.Row) (*models.RampStatus, error) {
	var r models.RampStatus
	err := row.Scan(
		&r.ID,
		&r.RampName,
		&r.AccessStatus,
		&r.StatusCategory,
		&r.ObjectID,
		&r.City,
		&r.AccessID,
		&r.Location,
		&r.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &r, nil
}

// InsertPageView records one HTML page navigation. Failures are the caller's
// to log-and-drop — a page view must never fail a user request.
func InsertPageView(ctx context.Context, pool *pgxpool.Pool, view models.PageView) error {
	const query = `
		INSERT INTO page_views (path, ip, user_agent, referer)
		VALUES ($1, $2, $3, $4)
	`
	if _, err := pool.Exec(ctx, query, view.Path, view.IP, view.UserAgent, view.Referer); err != nil {
		return fmt.Errorf("inserting page view: %w", err)
	}
	return nil
}

// ListPageViews returns page views since the given time, newest first,
// optionally filtered to one path and excluding the given IPs (the site
// owner's own addresses).
func ListPageViews(ctx context.Context, pool *pgxpool.Pool, since time.Time, path string, excludeIPs []string, limit int) ([]models.PageView, error) {
	query := `
		SELECT viewed_at, path, ip, user_agent, referer
		FROM page_views
		WHERE viewed_at >= $1
	`
	args := []interface{}{since}
	if path != "" {
		args = append(args, path)
		query += fmt.Sprintf(" AND path = $%d", len(args))
	}
	if len(excludeIPs) > 0 {
		args = append(args, excludeIPs)
		query += fmt.Sprintf(" AND ip != ALL($%d)", len(args))
	}
	args = append(args, limit)
	query += fmt.Sprintf(" ORDER BY viewed_at DESC LIMIT $%d", len(args))

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying page views: %w", err)
	}
	defer rows.Close()

	views := []models.PageView{}
	for rows.Next() {
		var v models.PageView
		if err := rows.Scan(&v.ViewedAt, &v.Path, &v.IP, &v.UserAgent, &v.Referer); err != nil {
			return nil, fmt.Errorf("scanning page view: %w", err)
		}
		views = append(views, v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating page view rows: %w", err)
	}
	return views, nil
}

// SummarizePageViewIPs groups page views since the given time by visitor IP,
// most recently seen first, with the distinct paths each IP touched and its
// latest user agent. excludeIPs removes the site owner's own addresses.
func SummarizePageViewIPs(ctx context.Context, pool *pgxpool.Pool, since time.Time, excludeIPs []string) ([]models.PageViewIPSummary, error) {
	query := `
		SELECT
			ip,
			COUNT(*)                                          AS views,
			MIN(viewed_at)                                    AS first_seen,
			MAX(viewed_at)                                    AS last_seen,
			ARRAY(SELECT DISTINCT p FROM unnest(array_agg(path)) AS p ORDER BY p) AS paths,
			(array_agg(user_agent ORDER BY viewed_at DESC))[1] AS user_agent
		FROM page_views
		WHERE viewed_at >= $1
	`
	args := []interface{}{since}
	if len(excludeIPs) > 0 {
		args = append(args, excludeIPs)
		query += fmt.Sprintf(" AND ip != ALL($%d)", len(args))
	}
	query += " GROUP BY ip ORDER BY last_seen DESC"

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying page view summary: %w", err)
	}
	defer rows.Close()

	summaries := []models.PageViewIPSummary{}
	for rows.Next() {
		var s models.PageViewIPSummary
		if err := rows.Scan(&s.IP, &s.Views, &s.FirstSeen, &s.LastSeen, &s.Paths, &s.UserAgent); err != nil {
			return nil, fmt.Errorf("scanning page view summary: %w", err)
		}
		summaries = append(summaries, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating page view summary rows: %w", err)
	}
	return summaries, nil
}
