// Package camhealth tracks whether each beach camera's relay stream is
// actually serving. State arrives from two reconciling sources: MediaMTX
// runOnReady/runOnNotReady hooks on the relay droplet (instant) and an
// in-process poller that probes each camera's public stream URL (self-heals
// state missed while the API was down). Current state lives in camera_health;
// every flip is appended to camera_health_history.
package camhealth

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Source labels who observed a status, for the audit trail.
const (
	SourceHook = "hook"
	SourcePoll = "poll"
)

// Status is one camera's current health row.
type Status struct {
	CameraID  string    `json:"camera_id"`
	Online    bool      `json:"online"`
	ChangedAt time.Time `json:"changed_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Source    string    `json:"source"`
}

// Transition is one row of flap history.
type Transition struct {
	CameraID   string    `json:"camera_id"`
	Online     bool      `json:"online"`
	Source     string    `json:"source"`
	RecordedAt time.Time `json:"recorded_at"`
}

// SetStatus records an observation for one camera. It upserts the current
// state and, only when online actually flips (or the camera has no state
// yet), stamps changed_at and appends a history row. Returns whether the
// observation was a flip. Unknown camera ids are the caller's problem —
// check the roster first; the FK will reject strays.
func SetStatus(ctx context.Context, pool *pgxpool.Pool, cameraID string, online bool, source string) (flipped bool, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("beginning camera_health tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var prev bool
	known := true
	err = tx.QueryRow(ctx,
		`SELECT online FROM camera_health WHERE camera_id = $1 FOR UPDATE`,
		cameraID).Scan(&prev)
	if err == pgx.ErrNoRows {
		known = false
	} else if err != nil {
		return false, fmt.Errorf("reading camera_health for %s: %w", cameraID, err)
	}

	flipped = !known || prev != online

	if flipped {
		_, err = tx.Exec(ctx, `
			INSERT INTO camera_health (camera_id, online, changed_at, updated_at, source)
			VALUES ($1, $2, NOW(), NOW(), $3)
			ON CONFLICT (camera_id) DO UPDATE
			SET online = $2, changed_at = NOW(), updated_at = NOW(), source = $3`,
			cameraID, online, source)
		if err == nil {
			_, err = tx.Exec(ctx,
				`INSERT INTO camera_health_history (camera_id, online, source) VALUES ($1, $2, $3)`,
				cameraID, online, source)
		}
	} else {
		_, err = tx.Exec(ctx,
			`UPDATE camera_health SET updated_at = NOW(), source = $2 WHERE camera_id = $1`,
			cameraID, source)
	}
	if err != nil {
		return false, fmt.Errorf("writing camera_health for %s: %w", cameraID, err)
	}

	return flipped, tx.Commit(ctx)
}

// GetAll returns the current health of every tracked camera, keyed by id.
// Cameras with no row yet (never observed) are simply absent.
func GetAll(ctx context.Context, pool *pgxpool.Pool) (map[string]Status, error) {
	rows, err := pool.Query(ctx,
		`SELECT camera_id, online, changed_at, updated_at, source FROM camera_health`)
	if err != nil {
		return nil, fmt.Errorf("querying camera_health: %w", err)
	}
	defer rows.Close()

	out := make(map[string]Status)
	for rows.Next() {
		var s Status
		if err := rows.Scan(&s.CameraID, &s.Online, &s.ChangedAt, &s.UpdatedAt, &s.Source); err != nil {
			return nil, fmt.Errorf("scanning camera_health row: %w", err)
		}
		out[s.CameraID] = s
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating camera_health rows: %w", err)
	}
	return out, nil
}

// RecentTransitions returns the newest limit flap-history rows across all
// cameras, newest first.
func RecentTransitions(ctx context.Context, pool *pgxpool.Pool, limit int) ([]Transition, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := pool.Query(ctx, `
		SELECT camera_id, online, source, recorded_at
		FROM camera_health_history
		ORDER BY recorded_at DESC, id DESC
		LIMIT $1`, limit)
	if err != nil {
		return nil, fmt.Errorf("querying camera_health_history: %w", err)
	}
	defer rows.Close()

	out := make([]Transition, 0, limit)
	for rows.Next() {
		var t Transition
		if err := rows.Scan(&t.CameraID, &t.Online, &t.Source, &t.RecordedAt); err != nil {
			return nil, fmt.Errorf("scanning camera_health_history row: %w", err)
		}
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating camera_health_history rows: %w", err)
	}
	return out, nil
}
