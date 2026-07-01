package database

import (
	"fmt"
	"io/fs"
	"log"
	"sort"
	"strings"

	"healthchecker-api/internal/config"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

// validateMigrationParity checks that every *.up.sql file in the migrations
// directory has a corresponding *.down.sql file.  This enforces rule 1: every
// migration must ship with a rollback script.
func validateMigrationParity() error {
	entries, err := fs.ReadDir(MigrationFiles, "migrations")
	if err != nil {
		return fmt.Errorf("reading migrations directory: %w", err)
	}

	upFiles := make(map[string]bool)
	downFiles := make(map[string]bool)

	for _, entry := range entries {
		name := entry.Name()
		switch {
		case strings.HasSuffix(name, ".up.sql"):
			upFiles[strings.TrimSuffix(name, ".up.sql")] = true
		case strings.HasSuffix(name, ".down.sql"):
			downFiles[strings.TrimSuffix(name, ".down.sql")] = true
		}
	}

	var missing []string
	for key := range upFiles {
		if !downFiles[key] {
			missing = append(missing, key+".down.sql")
		}
	}

	if len(missing) > 0 {
		sort.Strings(missing)
		return fmt.Errorf(
			"every migration must have a down script; missing: %s",
			strings.Join(missing, ", "),
		)
	}

	return nil
}

// RunMigrations applies all pending database migrations.
//
// Safety rules applied here:
//  1. All migration files are validated for up/down parity before any SQL runs.
//  2. If a migration fails and its version is classified as Reversible in the
//     metadata registry, the runner automatically rolls back that one step via
//     the down script so the database is left in a clean state.
//  3. If a migration fails and its version is classified as NonReversible (or
//     has no registry entry), no automatic rollback is attempted; the dirty flag
//     will remain in schema_migrations and manual intervention is required.
func RunMigrations() error {
	if err := validateMigrationParity(); err != nil {
		return err
	}

	connectionString := fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=%s",
		config.AppConfig.DBUser,
		config.AppConfig.DBPassword,
		config.AppConfig.DBHost,
		config.AppConfig.DBPort,
		config.AppConfig.DBName,
		config.AppConfig.DBSSLMode,
	)

	migrationsFS, err := iofs.New(MigrationFiles, "migrations")
	if err != nil {
		return err
	}

	m, err := migrate.NewWithSourceInstance("iofs", migrationsFS, connectionString)
	if err != nil {
		return err
	}

	err = m.Up()
	if err == nil || err == migrate.ErrNoChange {
		return nil
	}

	// A migration failed.  Determine the dirty version and whether it is safe
	// to roll back automatically.
	version, dirty, vErr := m.Version()
	if vErr != nil || !dirty {
		// Cannot determine dirty version; surface the original error as-is.
		return err
	}

	meta := GetMigrationMeta(version)
	if meta == nil {
		log.Printf(
			"migration %d failed and has no metadata entry -- manual intervention required: %v",
			version, err,
		)
		return fmt.Errorf("migration %d failed (no metadata, manual fix required): %w", version, err)
	}

	if meta.Reversibility == NonReversible {
		log.Printf(
			"migration %d (%s) failed and is marked NonReversible -- manual intervention required: %v",
			version, meta.Description, err,
		)
		return fmt.Errorf(
			"migration %d (%s) failed and is non-reversible (manual fix required): %w",
			version, meta.Description, err,
		)
	}

	// Reversible -- attempt automatic rollback.
	log.Printf(
		"migration %d (%s) failed; it is Reversible -- attempting automatic rollback: %v",
		version, meta.Description, err,
	)

	if rollbackErr := m.Steps(-1); rollbackErr != nil {
		return fmt.Errorf(
			"migration %d (%s) failed and rollback also failed (manual fix required): original=%w, rollback=%v",
			version, meta.Description, err, rollbackErr,
		)
	}

	log.Printf("migration %d (%s) rolled back successfully", version, meta.Description)
	return fmt.Errorf("migration %d (%s) failed and was rolled back: %w", version, meta.Description, err)
}
