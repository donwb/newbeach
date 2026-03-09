package database

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect creates a new pgx connection pool from the given DATABASE_URL.
// It configures the pool with sensible defaults: max 10 connections, min 2,
// and a max connection lifetime of 1 hour.
func Connect(databaseURL string) (*pgxpool.Pool, error) {
	if databaseURL == "" {
		return nil, fmt.Errorf("connecting to database: DATABASE_URL is empty")
	}

	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parsing database URL: %w", err)
	}

	config.MaxConns = 10
	config.MinConns = 2
	config.MaxConnLifetime = 1 * time.Hour
	config.MaxConnIdleTime = 30 * time.Minute
	config.HealthCheckPeriod = 1 * time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("creating connection pool: %w", err)
	}

	// Verify the connection is alive.
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pinging database: %w", err)
	}

	slog.Info("database connection pool established",
		"max_conns", config.MaxConns,
		"min_conns", config.MinConns,
	)

	return pool, nil
}

// Close gracefully shuts down the connection pool.
func Close(pool *pgxpool.Pool) {
	if pool != nil {
		pool.Close()
		slog.Info("database connection pool closed")
	}
}
