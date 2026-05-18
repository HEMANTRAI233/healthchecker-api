package database

import (
	"context"
	"fmt"
	"io/fs"
	"sort"
	"strings"
)

// RunMigrations applies any pending SQL migration files embedded in migrationFS.
// Migration files must live in a top-level "migrations/" directory inside the FS
// and follow the naming convention NNN_description.sql (sorted lexicographically).
func RunMigrations(migrationFS fs.FS) error {
	// Ensure the tracking table exists.
	_, err := DB.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version    VARCHAR(255) PRIMARY KEY,
			applied_at TIMESTAMPTZ  DEFAULT NOW()
		)
	`)
	if err != nil {
		return fmt.Errorf("failed to create schema_migrations table: %w", err)
	}

	// Fetch already-applied versions.
	rows, err := DB.Query(context.Background(), "SELECT version FROM schema_migrations ORDER BY version")
	if err != nil {
		return fmt.Errorf("failed to query applied migrations: %w", err)
	}
	defer rows.Close()

	applied := make(map[string]bool)
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			return fmt.Errorf("failed to scan migration version: %w", err)
		}
		applied[v] = true
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("error iterating migration rows: %w", err)
	}

	// Collect migration file names.
	entries, err := fs.ReadDir(migrationFS, "migrations")
	if err != nil {
		return fmt.Errorf("failed to read migrations directory: %w", err)
	}

	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			files = append(files, e.Name())
		}
	}
	sort.Strings(files)

	// Apply pending migrations inside individual transactions.
	for _, file := range files {
		version := strings.TrimSuffix(file, ".sql")
		if applied[version] {
			continue
		}

		content, err := fs.ReadFile(migrationFS, "migrations/"+file)
		if err != nil {
			return fmt.Errorf("failed to read migration file %s: %w", file, err)
		}

		tx, err := DB.Begin(context.Background())
		if err != nil {
			return fmt.Errorf("failed to begin transaction for migration %s: %w", file, err)
		}

		if _, err = tx.Exec(context.Background(), string(content)); err != nil {
			_ = tx.Rollback(context.Background())
			return fmt.Errorf("failed to apply migration %s: %w", file, err)
		}

		if _, err = tx.Exec(context.Background(),
			"INSERT INTO schema_migrations (version) VALUES ($1)", version,
		); err != nil {
			_ = tx.Rollback(context.Background())
			return fmt.Errorf("failed to record migration %s: %w", file, err)
		}

		if err = tx.Commit(context.Background()); err != nil {
			return fmt.Errorf("failed to commit migration %s: %w", file, err)
		}

		fmt.Printf("Applied migration: %s\n", file)
	}

	return nil
}
