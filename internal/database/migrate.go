package database

import (
	"fmt"
	"io/fs"
	"log"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"

	"healthchecker-api/internal/config"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

// PreUpgradeVersionFile is the path where RunMigrations writes the schema
// version that was active before it applied any new migrations.
//
// install.sh reads this file when the new binary crashes after a successful
// migration run.  It passes the saved version to the new binary via
// --rollback-schema so the DB schema is restored to the pre-upgrade state
// before the old binary is resumed, preventing schema drift.
const PreUpgradeVersionFile = "/opt/healthchecker/.pre_upgrade_schema_version"

// nilVersionSentinel is written to PreUpgradeVersionFile when no migrations
// had been applied before the upgrade (golang-migrate ErrNilVersion).  The
// --rollback-schema handler treats this value as "roll back everything".
const nilVersionSentinel = int64(-1)

// newMigrator creates a golang-migrate instance backed by the embedded
// migration files and the application's Postgres connection string.
func newMigrator() (*migrate.Migrate, error) {
	u := &url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(config.AppConfig.DBUser, config.AppConfig.DBPassword),
		Host:     config.AppConfig.DBHost + ":" + config.AppConfig.DBPort,
		Path:     "/" + config.AppConfig.DBName,
		RawQuery: "sslmode=" + config.AppConfig.DBSSLMode,
	}
	connectionString := u.String()

	migrationsFS, err := iofs.New(MigrationFiles, "migrations")
	if err != nil {
		return nil, err
	}

	return migrate.NewWithSourceInstance("iofs", migrationsFS, connectionString)
}

// savePreUpgradeVersion writes version to PreUpgradeVersionFile.  Errors are
// logged but do not abort the migration run; the file is best-effort.
func savePreUpgradeVersion(version int64) {
	data := strconv.FormatInt(version, 10)
	if err := os.WriteFile(PreUpgradeVersionFile, []byte(data), 0644); err != nil {
		log.Printf("warning: could not write pre-upgrade schema version to %s: %v", PreUpgradeVersionFile, err)
	}
}

// GetCurrentVersion returns the current schema version as a signed int64.
// It returns nilVersionSentinel (-1) when no migrations have been applied yet
// (golang-migrate ErrNilVersion).
func GetCurrentVersion() (int64, error) {
	m, err := newMigrator()
	if err != nil {
		return 0, fmt.Errorf("creating migrator: %w", err)
	}

	version, _, err := m.Version()
	if err == migrate.ErrNilVersion {
		return nilVersionSentinel, nil
	}
	if err != nil {
		return 0, fmt.Errorf("reading schema version: %w", err)
	}
	return int64(version), nil
}

// RollbackSchemaToVersion migrates the database schema back to targetVersion.
//
// Pass nilVersionSentinel (-1) to roll back all migrations (i.e. the schema
// was empty before the upgrade).  Any other non-negative value is passed to
// golang-migrate's Migrate(), which applies down scripts until the schema
// reaches that version.
//
// This function is invoked by the --rollback-schema CLI flag, which is called
// by install.sh during its binary auto-rollback to prevent schema drift:
//
// ${new_binary} --rollback-schema ${pre_upgrade_version}
func RollbackSchemaToVersion(targetVersion int64) error {
	m, err := newMigrator()
	if err != nil {
		return fmt.Errorf("creating migrator: %w", err)
	}

	if targetVersion == nilVersionSentinel {
		// No migrations existed before the upgrade; roll everything back.
		log.Printf("schema rollback: rolling back all migrations (pre-upgrade schema was empty)")
		err = m.Down()
	} else {
		log.Printf("schema rollback: rolling back to version %d", targetVersion)
		err = m.Migrate(uint(targetVersion))
	}

	if err == nil || err == migrate.ErrNoChange {
		log.Printf("schema rollback: complete (target version: %d)", targetVersion)
		return nil
	}
	return fmt.Errorf("schema rollback to version %d failed: %w", targetVersion, err)
}

// validateMigrationParity checks that every *.up.sql file in the migrations
// directory has a corresponding *.down.sql file, ensuring every migration
// ships with a rollback script.
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
// Behaviour:
//  1. All migration files are validated for up/down parity before any SQL runs.
//  2. The expand-and-contract phase rules are validated: every Expand-phase
//     migration must be Reversible (see validateExpandContractPhases).
//  3. The current schema version is persisted to PreUpgradeVersionFile before
//     any migrations run.  install.sh reads this file when rolling back the
//     binary after a crash-after-migration, allowing it to restore the DB
//     schema to the pre-upgrade state via --rollback-schema.
//  4. If a migration fails and its version is classified as Reversible in the
//     metadata registry, the runner automatically rolls back that one step via
//     the down script so the database is left in a clean state.
//  5. If a migration fails and its version is classified as NonReversible, a
//     protective automatic rollback is still attempted via the down script.
//     Because the up script did not complete, no data has been permanently
//     transformed, so the rollback restores the database to its prior clean
//     state with no data loss.  The error returned clearly indicates that the
//     migration is non-reversible and that data integrity should be verified.
//  6. If a migration fails and has no registry entry, no automatic rollback is
//     attempted.  The golang-migrate internal tracking table
//     (schema_migrations) will retain a dirty=true record for the failed
//     version, signalling that manual intervention is required before
//     migrations can proceed again.
func RunMigrations() error {
	if err := validateMigrationParity(); err != nil {
		return err
	}

	if err := validateExpandContractPhases(); err != nil {
		return err
	}

	m, err := newMigrator()
	if err != nil {
		return err
	}

	// Persist the pre-upgrade schema version BEFORE running Up() so that
	// install.sh can restore the schema if the new binary crashes after a
	// successful migration run (schema drift prevention).
	preUpgradeVersion, _, vErr := m.Version()
	if vErr == migrate.ErrNilVersion {
		savePreUpgradeVersion(nilVersionSentinel)
	} else if vErr == nil {
		savePreUpgradeVersion(int64(preUpgradeVersion))
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
		// Although this migration is marked NonReversible, its up script did not
		// complete successfully, meaning no destructive or irreversible data
		// transformation has been committed.  A protective rollback via the down
		// script is therefore safe and returns the database to its prior clean
		// state with no data loss.
		log.Printf(
			"migration %d (%s) failed and is marked NonReversible -- attempting protective rollback to prevent dirty state: %v",
			version, meta.Description, err,
		)

		if rollbackErr := m.Steps(-1); rollbackErr != nil {
			return fmt.Errorf(
				"migration %d (%s) failed (non-reversible) and protective rollback also failed (manual fix required): original=%w, rollback=%v",
				version, meta.Description, err, rollbackErr,
			)
		}

		log.Printf(
			"migration %d (%s) protective rollback completed; database restored to clean state (non-reversible migration -- verify data integrity)",
			version, meta.Description,
		)
		return fmt.Errorf(
			"migration %d (%s) failed and was rolled back (non-reversible: verify data integrity): %w",
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
