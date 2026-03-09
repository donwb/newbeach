package database

import (
	"context"
	"fmt"
	"io/fs"
	"log/slog"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// migrationFile holds a parsed migration filename and its SQL content.
type migrationFile struct {
	Version int
	Name    string
	SQL     string
}

// versionRegex matches filenames like "001_create_ramp_status.up.sql" and extracts the version number.
var versionRegex = regexp.MustCompile(`^(\d+)_.+\.up\.sql$`)

// RunMigrations reads embedded SQL migration files from the provided embed.FS,
// determines which have not yet been applied, and runs them in order inside
// individual transactions. It creates the schema_migrations tracking table
// automatically if it does not exist.
func RunMigrations(pool *pgxpool.Pool, migrationsFS fs.FS) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// Ensure the schema_migrations table exists.
	if err := createSchemaMigrationsTable(ctx, pool); err != nil {
		return fmt.Errorf("creating schema_migrations table: %w", err)
	}

	// Collect already-applied versions.
	applied, err := getAppliedVersions(ctx, pool)
	if err != nil {
		return fmt.Errorf("fetching applied migrations: %w", err)
	}

	// Read and parse migration files from the embedded filesystem.
	migrations, err := parseMigrationFiles(migrationsFS)
	if err != nil {
		return fmt.Errorf("parsing migration files: %w", err)
	}

	// Filter to only pending migrations and sort by version.
	var pending []migrationFile
	for _, m := range migrations {
		if !applied[m.Version] {
			pending = append(pending, m)
		}
	}
	sort.Slice(pending, func(i, j int) bool {
		return pending[i].Version < pending[j].Version
	})

	if len(pending) == 0 {
		slog.Info("database is up to date, no pending migrations")
		return nil
	}

	slog.Info("running pending migrations", "count", len(pending))

	for _, m := range pending {
		if err := runSingleMigration(ctx, pool, m); err != nil {
			return fmt.Errorf("running migration %d (%s): %w", m.Version, m.Name, err)
		}
	}

	slog.Info("all migrations applied successfully")
	return nil
}

// createSchemaMigrationsTable creates the tracking table if it does not exist.
func createSchemaMigrationsTable(ctx context.Context, pool *pgxpool.Pool) error {
	const query = `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version BIGINT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
	`
	_, err := pool.Exec(ctx, query)
	return err
}

// getAppliedVersions returns a set of migration versions that have already been applied.
func getAppliedVersions(ctx context.Context, pool *pgxpool.Pool) (map[int]bool, error) {
	rows, err := pool.Query(ctx, "SELECT version FROM schema_migrations ORDER BY version")
	if err != nil {
		return nil, fmt.Errorf("querying schema_migrations: %w", err)
	}
	defer rows.Close()

	applied := make(map[int]bool)
	for rows.Next() {
		var v int
		if err := rows.Scan(&v); err != nil {
			return nil, fmt.Errorf("scanning migration version: %w", err)
		}
		applied[v] = true
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating migration versions: %w", err)
	}

	return applied, nil
}

// parseMigrationFiles walks the embedded FS and extracts all *.up.sql files.
func parseMigrationFiles(migrationsFS fs.FS) ([]migrationFile, error) {
	var migrations []migrationFile

	entries, err := fs.ReadDir(migrationsFS, ".")
	if err != nil {
		return nil, fmt.Errorf("reading migrations directory: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		matches := versionRegex.FindStringSubmatch(entry.Name())
		if matches == nil {
			// Not an up-migration file; skip it.
			continue
		}

		version, err := strconv.Atoi(matches[1])
		if err != nil {
			return nil, fmt.Errorf("parsing version from filename %s: %w", entry.Name(), err)
		}

		content, err := fs.ReadFile(migrationsFS, entry.Name())
		if err != nil {
			return nil, fmt.Errorf("reading migration file %s: %w", entry.Name(), err)
		}

		migrations = append(migrations, migrationFile{
			Version: version,
			Name:    entry.Name(),
			SQL:     string(content),
		})
	}

	return migrations, nil
}

// runSingleMigration executes a single migration inside a transaction and
// records the version in schema_migrations.
func runSingleMigration(ctx context.Context, pool *pgxpool.Pool, m migrationFile) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // rollback after commit is a no-op

	slog.Info("applying migration", "version", m.Version, "file", m.Name)

	if _, err := tx.Exec(ctx, m.SQL); err != nil {
		return fmt.Errorf("executing SQL: %w", err)
	}

	if _, err := tx.Exec(ctx, "INSERT INTO schema_migrations (version) VALUES ($1)", m.Version); err != nil {
		return fmt.Errorf("recording migration version: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("committing transaction: %w", err)
	}

	slog.Info("migration applied", "version", m.Version)
	return nil
}
