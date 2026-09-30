package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/donwb/beach/api/internal/models"
)

// UpsertWidgetPushToken registers or refreshes a widget push token.
func UpsertWidgetPushToken(ctx context.Context, pool *pgxpool.Pool, token, environment, bundleID string) error {
	const query = `
		INSERT INTO widget_push_tokens (token, environment, bundle_id)
		VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE
		SET environment = EXCLUDED.environment,
		    bundle_id = EXCLUDED.bundle_id,
		    updated_at = now()`
	if _, err := pool.Exec(ctx, query, token, environment, bundleID); err != nil {
		return fmt.Errorf("upserting widget push token: %w", err)
	}
	return nil
}

// ListWidgetPushTokens returns every registered token.
func ListWidgetPushTokens(ctx context.Context, pool *pgxpool.Pool) ([]models.WidgetPushToken, error) {
	rows, err := pool.Query(ctx, `
		SELECT token, environment, bundle_id, created_at, updated_at, last_pushed_at
		FROM widget_push_tokens ORDER BY created_at`)
	if err != nil {
		return nil, fmt.Errorf("listing widget push tokens: %w", err)
	}
	defer rows.Close()
	var out []models.WidgetPushToken
	for rows.Next() {
		var t models.WidgetPushToken
		if err := rows.Scan(&t.Token, &t.Environment, &t.BundleID, &t.CreatedAt, &t.UpdatedAt, &t.LastPushedAt); err != nil {
			return nil, fmt.Errorf("scanning widget push token: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// DeleteWidgetPushToken forgets a token APNs no longer accepts.
func DeleteWidgetPushToken(ctx context.Context, pool *pgxpool.Pool, token string) error {
	if _, err := pool.Exec(ctx, `DELETE FROM widget_push_tokens WHERE token = $1`, token); err != nil {
		return fmt.Errorf("deleting widget push token: %w", err)
	}
	return nil
}

// MarkWidgetPushed records a successful push for the given tokens.
func MarkWidgetPushed(ctx context.Context, pool *pgxpool.Pool, tokens []string, at time.Time) error {
	if len(tokens) == 0 {
		return nil
	}
	if _, err := pool.Exec(ctx, `UPDATE widget_push_tokens SET last_pushed_at = $2 WHERE token = ANY($1)`, tokens, at); err != nil {
		return fmt.Errorf("marking widget pushes: %w", err)
	}
	return nil
}
