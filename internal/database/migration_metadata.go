package database

import (
	"fmt"
	"sort"
)

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

// Phase classifies a migration within the expand-and-contract deployment
// pattern.
//
// The expand-and-contract pattern is the standard safeguard against schema
// drift during zero-downtime deployments:
//
//  1. Expand  — the migration only *adds* to the schema (new tables, new
//     nullable columns, new indexes, new constraints that existing data satisfies).
//     The new schema is fully backward-compatible: the previous binary can still
//     read and write every column it depends on.  Because no existing structure
//     is removed, the binary auto-rollback in install.sh is safe — even if the
//     new binary crashes after migrations, the old binary can resume without
//     SQL errors.
//
//  2. Contract — the migration *removes* schema that was deprecated in a prior
//     Expand release.  By the time this release ships, no running binary
//     references the old columns/tables, so dropping them is safe.  Contract
//     migrations are intentionally NonReversible: putting the old columns back
//     in a hot rollback would require data reconstruction.
//
// Rule enforced at startup: every Expand-phase migration MUST be Reversible.
// A NonReversible Expand migration would mean the old binary cannot safely run
// against the post-rollback schema, defeating the purpose of the pattern.
type Phase int

const (
	// Expand means the migration is purely additive.  The previous binary
	// continues to operate correctly if a rollback is needed after this
	// migration runs.
	Expand Phase = iota

	// Contract means the migration removes schema deprecated in a prior
	// Expand release.  It should only be deployed once every binary that
	// depended on the old schema has been retired.
	Contract
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

	// Phase classifies the migration within the expand-and-contract pattern.
	// Defaults to Expand.  Set to Contract only when the migration removes
	// schema that was deprecated in a previous Expand release.
	Phase Phase
}

// migrationRegistry is the authoritative source of metadata for every
// migration in the migrations/ directory.  Every time a new migration file
// pair (*.up.sql + *.down.sql) is added, a corresponding entry MUST be added
// here.
//
// Expand-and-contract guide for new entries:
//   - New table / nullable column / index → Phase: Expand, Reversibility: Reversible
//   - Drop column / drop table / rename   → Phase: Contract, Reversibility: NonReversible
//     (only after all binaries using the old schema have been retired)
var migrationRegistry = map[uint]*MigrationMeta{
	// 001 - creates the initial application_users table.
	// The down script drops the table; safe to roll back because no previous
	// version of the application exists.
	1: {
		Version:       1,
		Description:   "initial_schema",
		Reversibility: Reversible,
		Phase:         Expand,
	},

	// 002 - adds the audit_logs table and two indexes.
	// The down script drops the table and indexes; the previous application
	// version does not reference audit_logs so rolling back is safe.
	2: {
		Version:       2,
		Description:   "add_audit_logs",
		Reversibility: Reversible,
		Phase:         Expand,
	},
}

// GetMigrationMeta returns the metadata for the given migration version.
// It returns nil when no entry exists for that version.
func GetMigrationMeta(version uint) *MigrationMeta {
	return migrationRegistry[version]
}

// validateExpandContractPhases checks that every registered Expand-phase
// migration is also marked Reversible.
//
// An Expand migration that is NonReversible is a contradiction: if the new
// binary crashes after migrations run and install.sh rolls back to the old
// binary, the old binary must be able to operate against the post-rollback
// schema.  A NonReversible Expand migration would leave the schema in a state
// the old binary cannot handle, causing the exact schema-drift problem that
// the expand-and-contract pattern is designed to prevent.
func validateExpandContractPhases() error {
	var violations []uint
	for version, meta := range migrationRegistry {
		if meta.Phase == Expand && meta.Reversibility == NonReversible {
			violations = append(violations, version)
		}
	}
	if len(violations) == 0 {
		return nil
	}
	sort.Slice(violations, func(i, j int) bool { return violations[i] < violations[j] })
	return fmt.Errorf(
		"expand-and-contract violation: Expand-phase migrations must be Reversible, "+
			"but the following are marked NonReversible: %v. "+
			"Either change the phase to Contract (if the migration removes deprecated schema) "+
			"or change reversibility to Reversible (if the migration is purely additive).",
		violations,
	)
}
