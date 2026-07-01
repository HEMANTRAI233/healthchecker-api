package database

// Reversibility describes whether a migration can be safely rolled back.
//
// Guidelines:
//   - Mark a migration Reversible only when its down script returns the schema
//     to a state that is fully compatible with the previous application version.
//     Typical reversible operations: adding a nullable column, adding an index,
//     creating a new table, adding a new constraint that old code never violates.
//   - Mark a migration NonReversible when data would be permanently lost or
//     when running the down script while the previous code is active would break
//     that code.  Typical non-reversible operations: dropping a column, dropping
//     a table, renaming a column/table, migrating data to a new structure.
//   - Prefer expand-and-contract patterns so that most migrations stay
//     Reversible.  Reserve NonReversible for exceptional schema redesigns, not
//     routine releases.
type Reversibility int

const (
	// Reversible means the migration has a safe down script and the previous
	// application version can continue to operate after the rollback.
	Reversible Reversibility = iota

	// NonReversible means rolling back would cause data loss or break the
	// previous application version.  Manual intervention is required.
	NonReversible
)

// MigrationMeta records metadata for a single numbered migration.
type MigrationMeta struct {
	// Version matches the numeric prefix in the migration filename (e.g. 1 for
	// 001_initial_schema.up.sql).
	Version uint

	// Description is a human-readable label for the migration.
	Description string

	// Reversibility declares whether an automatic rollback via the down script
	// is safe when this migration fails mid-flight.
	Reversibility Reversibility
}

// migrationRegistry is the authoritative source of metadata for every
// migration in the migrations/ directory.  Every time a new migration file
// pair (*.up.sql + *.down.sql) is added, a corresponding entry MUST be added
// here.
var migrationRegistry = map[uint]*MigrationMeta{
	// 001 - creates the initial application_users table.
	// The down script drops the table; safe to roll back because no previous
	// version of the application exists.
	1: {
		Version:       1,
		Description:   "initial_schema",
		Reversibility: Reversible,
	},

	// 002 - adds the audit_logs table and two indexes.
	// The down script drops the table and indexes; the previous application
	// version does not reference audit_logs so rolling back is safe.
	2: {
		Version:       2,
		Description:   "add_audit_logs",
		Reversibility: Reversible,
	},
}

// GetMigrationMeta returns the metadata for the given migration version.
// It returns nil when no entry exists for that version.
func GetMigrationMeta(version uint) *MigrationMeta {
	return migrationRegistry[version]
}
