package database

import (
	"context"
	"fmt"

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

// GetRecentHistory returns the most recent history entries across all ramps,
// enriched with ramp_name and city from the ramp_status table.
// Results are ordered newest-first.
func GetRecentHistory(ctx context.Context, pool *pgxpool.Pool, limit int) ([]models.RampHistoryEntry, error) {
	const query = `
		SELECT h.id, h.access_id, h.access_status, h.recorded_at, r.ramp_name, r.city
		FROM ramp_status_history h
		JOIN ramp_status r ON h.access_id = r.access_id
		ORDER BY h.recorded_at DESC
		LIMIT $1
	`

	rows, err := pool.Query(ctx, query, limit)
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
